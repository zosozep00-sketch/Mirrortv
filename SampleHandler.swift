import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

private let pageHTML = [
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>Mirror TV</title><style>",
    "*{box-sizing:border-box;user-select:none}",
    "html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden;font-family:sans-serif;display:flex;align-items:center;justify-content:center}",
    "#v{width:100vw;height:100vh;object-fit:contain;display:block;transition:transform .2s ease}",
    "#v.cover{object-fit:cover}",
    "#v.fill{object-fit:fill}",
    "#controls{position:fixed;bottom:0;left:0;right:0;padding:24px 20px 16px;background:linear-gradient(transparent,rgba(0,0,0,.85));display:flex;align-items:center;justify-content:space-between;gap:12px;opacity:1;transition:opacity .3s ease;z-index:20}",
    "#controls.hidden{opacity:0;pointer-events:none}",
    ".group{display:flex;align-items:center;gap:10px}",
    ".btn{background:rgba(255,255,255,.15);color:#fff;border:1px solid rgba(255,255,255,.2);padding:8px 14px;border-radius:8px;font-size:14px;font-weight:500;cursor:pointer}",
    ".btn:hover{background:rgba(255,255,255,.28)}",
    ".btn.active{background:#2d7cff;border-color:#2d7cff}",
    ".live-badge{display:flex;align-items:center;gap:6px;color:#fff;font-size:13px;font-weight:600;padding:6px 10px}",
    ".dot{width:8px;height:8px;background:#ff3b30;border-radius:50%;animation:pulse 1.5s infinite}",
    "@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}",
    "#settings-menu{position:fixed;bottom:72px;right:20px;background:rgba(28,28,30,.95);border:1px solid rgba(255,255,255,.15);border-radius:12px;padding:12px;width:240px;color:#fff;display:none;flex-direction:column;gap:12px;z-index:30}",
    "#settings-menu.open{display:flex}",
    ".menu-row{display:flex;justify-content:space-between;align-items:center;font-size:14px}",
    "select{background:#3a3a3c;color:#fff;border:none;padding:6px 10px;border-radius:6px;font-size:13px;outline:none}",
    "</style></head><body>",
    "<img id='v' src='/stream'>",
    "<div id='settings-menu'>",
    "<div class='menu-row'><span>Qualità</span><select id='sel-res' onchange='updateConfig()'><option value='1920'>1080p (Alta)</option><option value='1280' selected>720p (Media)</option><option value='854'>480p (Bassa)</option></select></div>",
    "<div class='menu-row'><span>Fluidità</span><select id='sel-fps' onchange='updateConfig()'><option value='60'>60 FPS</option><option value='30' selected>30 FPS</option><option value='15'>15 FPS</option></select></div>",
    "<div class='menu-row'><span>Proporzioni</span><select id='sel-fit' onchange='toggleFit(this.value)'><option value='contain' selected>Adatta (Intero)</option><option value='cover'>Riempi (Taglia)</option><option value='fill'>Estendi (16:9)</option></select></div>",
    "</div>",
    "<div id='controls'>",
    "<div class='group'><div class='live-badge'><span class='dot'></span> LIVE</div><button id='btn-audio' class='btn' onclick='toggleAudio()'>🔇 Attiva audio</button></div>",
    "<div class='group'><button class='btn' onclick='rotateVideo()'>↻ Ruota</button><button class='btn' onclick='toggleMenu()'>⚙️ Impostazioni</button><button class='btn' onclick='toggleFullscreen()'>⛶ Schermo intero</button></div>",
    "</div>",
    "<script>",
    "var ctx=null,nextTime=0,audioRunning=false,audioAbort=null,rotation=0,hideTimer=null;",
    "function showControls(){var c=document.getElementById('controls');c.classList.remove('hidden');clearTimeout(hideTimer);hideTimer=setTimeout(function(){if(!document.getElementById('settings-menu').classList.contains('open'))c.classList.add('hidden')},3000)}",
    "document.addEventListener('mousemove',showControls);document.addEventListener('touchstart',showControls);showControls();",
    "function toggleMenu(){document.getElementById('settings-menu').classList.toggle('open')}",
    "function toggleFit(m){var i=document.getElementById('v');i.className=m==='contain'?'':m}",
    "function rotateVideo(){rotation=(rotation+90)%360;document.getElementById('v').style.transform='rotate('+rotation+'deg)'}",
    "function toggleFullscreen(){if(!document.fullscreenElement)document.documentElement.requestFullscreen().catch(function(){});else document.exitFullscreen().catch(function(){})}",
    "function updateConfig(){var r=document.getElementById('sel-res').value,f=document.getElementById('sel-fps').value;fetch('/config?res='+r+'&fps='+f).catch(function(){})}",
    "async function toggleAudio(){var b=document.getElementById('btn-audio');if(audioRunning){audioRunning=false;if(audioAbort)audioAbort.abort();if(ctx){ctx.close();ctx=null}b.textContent='🔇 Attiva audio';b.classList.remove('active');return}audioRunning=true;b.textContent='🔊 Audio attivo';b.classList.add('active');audioAbort=new AbortController();try{ctx=new(window.AudioContext||window.webkitAudioContext)({sampleRate:48000});await ctx.resume();var res=await fetch('/audio',{signal:audioAbort.signal}),rd=res.body.getReader(),left=new Uint8Array(0);while(audioRunning){var r=await rd.read();if(r.done)break;var buf=new Uint8Array(left.length+r.value.length);buf.set(left);buf.set(r.value,left.length);var u=buf.length-(buf.length%4);left=buf.slice(u);if(u===0)continue;var n=u/4,i16=new Int16Array(buf.buffer,0,u/2),ab=ctx.createBuffer(2,n,48000),L=ab.getChannelData(0),R=ab.getChannelData(1);for(var i=0;i<n;i++){L[i]=i16[2*i]/32768.0;R[i]=i16[2*i+1]/32768.0}var now=ctx.currentTime;if(nextTime<now+0.05)nextTime=now+0.15;if(nextTime>now+0.8)continue;var src=ctx.createBufferSource();src.buffer=ab;src.connect(ctx.destination);src.start(nextTime);nextTime+=ab.duration}}catch(e){if(audioRunning){audioRunning=false;b.textContent='🔇 Riprova audio';b.classList.remove('active')}}}",
    "</script></body></html>"
].joined()

final class MJPEGServer {
    private var listenFD: Int32 = -1
    private var clients: [Int32] = []
    private var audioClients: [Int32] = []
    private var busy = false
    private var audioPending = 0
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "mirrortv.send")
    private let audioQueue = DispatchQueue(label: "mirrortv.audio")

    var maxResolution: CGFloat = 1280
    var targetFPS: Double = 30.0

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
        } else if path.hasPrefix("/config") {
            if let comps = URLComponents(string: path), let items = comps.queryItems {
                lock.lock()
                for item in items {
                    if item.name == "res", let val = Double(item.value ?? "") {
                        maxResolution = CGFloat(val)
                    } else if item.name == "fps", let val = Double(item.value ?? ""), val > 0 {
                        targetFPS = val
                    }
                }
                lock.unlock()
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
            _ = sendAll(client, Data(head.utf8))
            close(client)
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
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastFrameTime: CFTimeInterval = 0
    private var audioConverter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        server.start(port: 8080)
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        server.stop()
        audioConverter = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            guard server.hasClients else { return }
            let now = CACurrentMediaTime()
            if now - lastFrameTime < (1.0 / server.targetFPS) { return }
            lastFrameTime = now

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            let maxDimension = server.maxResolution
            let scale = min(1.0, maxDimension / max(ciImage.extent.width, ciImage.extent.height))
            if scale < 1.0 {
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]) {
                server.broadcast(jpegData)
            }

        case .audioApp:
            guard server.hasAudioClients else { return }
            guard let pcmData = convertAudioToInt16Stereo(sampleBuffer) else { return }
            server.broadcastAudio(pcmData)

        default:
            break
        }
    }

    private func convertAudioToInt16Stereo(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0, let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }
        inputBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        if audioConverter == nil || audioConverter?.inputFormat != inputFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let converter = audioConverter else { return nil }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var error: NSError?
        var inputProvided = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard error == nil, outputBuffer.frameLength > 0,
              let int16Data = outputBuffer.int16ChannelData else {
            return nil
        }

        let byteCount = Int(outputBuffer.frameLength) * 4
        return Data(bytes: int16Data[0], count: byteCount)
    }
}
