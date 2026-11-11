import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Network

private let pageHTML = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mirror TV</title>
<style>
  html,body{margin:0;height:100%;background:#000;overflow:hidden;font-family:sans-serif}
  #v{width:100vw;height:100vh;object-fit:contain;display:block}
  #b{position:fixed;top:16px;right:16px;padding:14px 22px;font-size:20px;border:0;
     border-radius:12px;background:#2d7cff;color:#fff;opacity:.9}
</style>
</head>
<body>
<img id="v" src="/stream">
<button id="b">Attiva audio</button>
<script>
var ctx = null, nextTime = 0, started = false;
async function startAudio() {
  if (started) return;
  started = true;
  var btn = document.getElementById('b');
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    await ctx.resume();
    var res = await fetch('/audio');
    var reader = res.body.getReader();
    var left = new Uint8Array(0);
    btn.style.display = 'none';
    while (true) {
      var r = await reader.read();
      if (r.done) break;
      var buf = new Uint8Array(left.length + r.value.length);
      buf.set(left);
      buf.set(r.value, left.length);
      var usable = buf.length - (buf.length % 4);
      left = buf.slice(usable);
      if (usable === 0) continue;
      var n = usable / 4;
      var i16 = new Int16Array(buf.buffer, 0, usable / 2);
      var ab = ctx.createBuffer(2, n, 48000);
      var L = ab.getChannelData(0), R = ab.getChannelData(1);
      for (var i = 0; i < n; i++) {
        L[i] = i16[2 * i] / 32768;
        R[i] = i16[2 * i + 1] / 32768;
      }
      var now = ctx.currentTime;
      if (nextTime < now + 0.05) nextTime = now + 0.15;
      if (nextTime > now + 0.8) continue;
      var src = ctx.createBufferSource();
      src.buffer = ab;
      src.connect(ctx.destination);
      src.start(nextTime);
      nextTime += ab.duration;
    }
  } catch (e) {
    started = false;
    btn.style.display = 'block';
    btn.textContent = 'Audio non disponibile, riprova';
  }
}
document.getElementById('b').addEventListener('click', startAudio);
document.addEventListener('keydown', startAudio);
</script>
</body>
</html>
"""#

final class NWStreamServer {
    private var listener: NWListener?
    private var videoClients: [NWConnection] = []
    private var audioClients: [NWConnection] = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "mirrortv.nwserver")
    private var busy = false

    func start(port: UInt16 = 8080) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleNewConnection(conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("Errore avvio NWListener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let all = videoClients + audioClients
        videoClients.removeAll()
        audioClients.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }

    private func handleNewConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                conn.cancel()
                return
            }
            let req = String(decoding: data, as: UTF8.self)
            let parts = req.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"

            if path.hasPrefix("/stream") {
                let head = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(head.utf8), completion: .contentProcessed { err in
                    if err == nil {
                        self.lock.lock()
                        self.videoClients.append(conn)
                        self.lock.unlock()
                    } else {
                        conn.cancel()
                    }
                })
            } else if path.hasPrefix("/audio") {
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(head.utf8), completion: .contentProcessed { err in
                    if err == nil {
                        self.lock.lock()
                        self.audioClients.append(conn)
                        self.lock.unlock()
                    } else {
                        conn.cancel()
                    }
                })
            } else {
                let body = Data(pageHTML.utf8)
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                var response = Data(head.utf8)
                response.append(body)
                conn.send(content: response, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
    }

    func broadcast(_ jpeg: Data) {
        lock.lock()
        if busy || videoClients.isEmpty {
            lock.unlock()
            return
        }
        busy = true
        let clients = videoClients
        lock.unlock()

        var packet = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
        packet.append(jpeg)
        packet.append(Data("\r\n".utf8))

        let group = DispatchGroup()
        var deadClients = [ObjectIdentifier]()
        let deadLock = NSLock()

        for client in clients {
            group.enter()
            client.send(content: packet, completion: .contentProcessed { err in
                if err != nil {
                    deadLock.lock()
                    deadClients.append(ObjectIdentifier(client))
                    deadLock.unlock()
                    client.cancel()
                }
                group.leave()
            })
        }

        group.notify(queue: queue) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            if !deadClients.isEmpty {
                let deadSet = Set(deadClients)
                self.videoClients.removeAll { deadSet.contains(ObjectIdentifier($0)) }
            }
            self.busy = false
            self.lock.unlock()
        }
    }

    func broadcastAudio(_ pcm: Data) {
        lock.lock()
        let clients = audioClients
        lock.unlock()
        guard !clients.isEmpty else { return }

        for client in clients {
            client.send(content: pcm, completion: .contentProcessed { [weak self] err in
                if err != nil {
                    client.cancel()
                    self?.lock.lock()
                    self?.audioClients.removeAll { $0 === client }
                    self?.lock.unlock()
                }
            })
        }
    }
}

class SampleHandler: RPBroadcastSampleHandler {
    private let server = NWStreamServer()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastFrameTime: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        server.start(port: 8080)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        server.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            let now = CACurrentMediaTime()
            if now - lastFrameTime < (1.0 / 24.0) { return } // Max 24 fps per non superare i 50MB di RAM
            lastFrameTime = now

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Ridimensiona per fluidità e limite memoria iOS
            let maxDimension: CGFloat = 1280
            let scale = min(1.0, maxDimension / max(ciImage.extent.width, ciImage.extent.height))
            if scale < 1.0 {
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]) {
                server.broadcast(jpegData)
            }

        case .audioApp:
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            if CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
               let ptr = dataPointer, length > 0 {
                let data = Data(bytes: ptr, count: length)
                server.broadcastAudio(data)
            }

        default:
            break
        }
    }
}
