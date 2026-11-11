import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

// Pagina mostrata dalla TV: video (MJPEG) + audio (PCM riprodotto con Web Audio)
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
  #q{position:fixed;top:16px;left:16px;opacity:.85}
  #q button{padding:12px 18px;margin-right:8px;font-size:18px;border:0;border-radius:10px;
     background:#444;color:#fff}
  #q button.on{background:#2d7cff}
</style>
</head>
<body>
<img id="v">
<div id="q">
  <button data-p="3">1 Veloce</button><button data-p="2">2 Normale</button><button data-p="1">3 Qualit&agrave;</button>
</div>
<button id="b">Attiva audio</button>
<script>
var ctx = null, nextTime = 0, started = false;
function setPreset(p) {
  document.getElementById('v').src = '/stream?p=' + p + '&t=' + Date.now();
  var bs = document.querySelectorAll('#q button');
  for (var i = 0; i < bs.length; i++) {
    bs[i].className = (bs[i].getAttribute('data-p') === String(p)) ? 'on' : '';
  }
}
(function () {
  var m = /[?&]p=([123])/.exec(location.search);
  setPreset(m ? m[1] : 2);
  var bs = document.querySelectorAll('#q button');
  for (var i = 0; i < bs.length; i++) {
    bs[i].addEventListener('click', function (e) { e.stopPropagation(); setPreset(this.getAttribute('data-p')); });
  }
})();
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
document.addEventListener('keydown', function (e) {
  if (e.key === '1') { setPreset(3); return; }
  if (e.key === '2') { setPreset(2); return; }
  if (e.key === '3') { setPreset(1); return; }
  startAudio();
});
</script>
</body>
</html>
"""#

// Piccolo server HTTP: video MJPEG su /stream, audio PCM su /audio
final class MJPEGServer {
    private var listenFD: Int32 = -1
    private var clients: [Int32] = []
    private var audioClients: [Int32] = []
    private var busy = false
    private var audioPending = 0
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "mirrortv.send")

    // Qualità del video (cambia dalla TV con i pulsanti 1/2/3)
    var maxSide: CGFloat = 960
    var quality: Double = 0.4
    var minInterval: Double = 1.0 / 20.0

    private func applyPreset(_ path: String) {
        guard let r = path.range(of: "p="), let c = path[r.upperBound...].first else { return }
        switch c {
        case "1": maxSide = 1280; quality = 0.5; minInterval = 1.0 / 15.0
        case "2": maxSide = 960; quality = 0.4; minInterval = 1.0 / 20.0
        case "3": maxSide = 640; quality = 0.35; minInterval = 1.0 / 25.0
        default: break
        }
    }
    private let audioQueue = DispatchQueue(label: "mirrortv.audio")

    var hasClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty
    }

    var hasAudioClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !audioClients.isEmpty
    }

    func start(port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: 0)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return
        }
        listenFD = fd
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        lock.lock()
        let all = clients + audioClients
        clients.removeAll()
        audioClients.removeAll()
        lock.unlock()
        for c in all { close(c) }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            DispatchQueue.global().async { [self] in handle(client) }
        }
    }

    private func handle(_ client: Int32) {
        var yes: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8](repeating: 0, count: 2048)
        let n = recv(client, &buf, buf.count, 0)
        guard n > 0 else { close(client); return }

        let request = String(decoding: buf[0..<n], as: UTF8.self)
        let parts = request.split(separator: " ")
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if path.hasPrefix("/stream") {
            applyPreset(path)
            var nodelay: Int32 = 1
            setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
            var sndbuf: Int32 = 131072
            setsockopt(client, SOL_SOCKET, SO_SNDBUF, &sndbuf, socklen_t(MemoryLayout<Int32>.size))
            let head = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock(); clients.append(client); lock.unlock()
            } else {
                close(client)
            }
        } else if path.hasPrefix("/audio") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock(); audioClients.append(client); lock.unlock()
            } else {
                close(client)
            }
        } else {
            let body = Data(pageHTML.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        }
    }

    func broadcast(_ jpeg: Data) {
        lock.lock()
        if busy || clients.isEmpty { lock.unlock(); return }
        busy = true
        let snapshot = clients
        lock.unlock()

        sendQueue.async { [self] in
            var packet = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
            packet.append(jpeg)
            packet.append(Data("\r\n".utf8))

            var dead = Set<Int32>()
            for fd in snapshot where !sendAll(fd, packet) {
                dead.insert(fd)
            }

            lock.lock()
            clients.removeAll { dead.contains($0) }
            busy = false
            lock.unlock()
            for fd in dead { close(fd) }
        }
    }

    func broadcastAudio(_ pcm: Data) {
        lock.lock()
        if audioClients.isEmpty || audioPending > 20 { lock.unlock(); return }
        audioPending += 1
        let snapshot = audioClients
        lock.unlock()

        audioQueue.async { [self] in
            var dead = Set<Int32>()
            for fd in snapshot where !sendAll(fd, pcm) {
                dead.insert(fd)
            }

            lock.lock()
            audioClients.removeAll { dead.contains($0) }
            audioPending -= 1
            lock.unlock()
            for fd in dead { close(fd) }
        }
    }

    private func sendAll(_ fd: Int32, _ data: Data) -> Bool {
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < data.count {
                let n = send(fd, base + sent, data.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}

class SampleHandler: RPBroadcastSampleHandler {
    private let server = MJPEGServer()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame: CFAbsoluteTime = 0

    // Audio: converto qualunque formato in PCM 16 bit, stereo, 48000 Hz
    private var audioConverter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 48000,
                                             channels: 2,
                                             interleaved: true)!

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        server.start(port: 8080)
    }

    override func broadcastFinished() {
        server.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            handleVideo(sampleBuffer)
        case .audioApp:
            handleAudio(sampleBuffer)
        default:
            break
        }
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard server.hasClients else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame >= server.minInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now

        var image = CIImage(cvPixelBuffer: pixelBuffer)

        if let number = CMGetAttachment(sampleBuffer,
                                        key: RPVideoSampleOrientationKey as CFString,
                                        attachmentModeOut: nil) as? NSNumber,
           let reported = CGImagePropertyOrientation(rawValue: number.uint32Value) {
            // In orizzontale ReplayKit risulta ruotato di 180°: scambio sinistra/destra
            let orientation: CGImagePropertyOrientation
            switch reported {
            case .left: orientation = .right
            case .right: orientation = .left
            case .leftMirrored: orientation = .rightMirrored
            case .rightMirrored: orientation = .leftMirrored
            default: orientation = reported
            }
            image = image.oriented(orientation)
        }

        let longest = max(image.extent.width, image.extent.height)
        let scale = min(1.0, server.maxSide / longest)
        if scale < 1.0 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): server.quality
        ]
        if let jpeg = ciContext.jpegRepresentation(of: image,
                                                   colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                   options: options) {
            server.broadcast(jpeg)
        }
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard server.hasAudioClients,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }

        var desc = asbd.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &desc) else { return }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return }
        inBuffer.frameLength = frames

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: inBuffer.mutableAudioBufferList)
        guard copyStatus == noErr else { return }

        if audioConverter == nil || audioConverter?.inputFormat != inFormat {
            audioConverter = AVAudioConverter(from: inFormat, to: targetFormat)
        }
        guard let converter = audioConverter else { return }

        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return inBuffer
        }

        guard status != .error, outBuffer.frameLength > 0,
              let channel = outBuffer.int16ChannelData else { return }

        let byteCount = Int(outBuffer.frameLength) * 2 * MemoryLayout<Int16>.size
        server.broadcastAudio(Data(bytes: channel[0], count: byteCount))
    }
}
