import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

private let pageHTML = [
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1'>",
    "<title>MirrorTV by Zoso</title><style>",
    "*{box-sizing:border-box;-webkit-user-select:none;user-select:none}",
    "html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;-webkit-justify-content:center;justify-content:center}",
    "#v{width:100vw;height:100vh;object-fit:contain;display:block;transition:transform .2s ease}",
    "#brand{position:fixed;top:18px;left:22px;display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;gap:10px;padding:8px 14px;background:rgba(18,18,22,.85);border:1px solid rgba(255,255,255,.18);border-radius:14px;z-index:25;transition:opacity .3s ease}",
    "#brand.hidden{opacity:0;pointer-events:none}",
    ".brand-icon{width:30px;height:30px;border-radius:8px;background:linear-gradient(135deg,#00f2fe,#ff4b2b);display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;-webkit-justify-content:center;justify-content:center;box-shadow:0 0 12px rgba(0,242,254,.5)}",
    ".brand-play{width:0;height:0;border-top:6px solid transparent;border-bottom:6px solid transparent;border-left:10px solid #fff;margin-left:2px}",
    ".brand-text{display:-webkit-flex;display:flex;-webkit-flex-direction:column;flex-direction:column;line-height:1.1}",
    ".brand-title{color:#fff;font-size:15px;font-weight:800}",
    ".brand-sub{font-size:11px;font-weight:700;color:#00f2fe}",
    "#pause-banner{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.8);color:#fff;padding:16px 28px;border-radius:16px;border:1px solid rgba(255,255,255,.2);font-size:20px;font-weight:700;display:none;z-index:28;text-align:center}",
    "#controls{position:fixed;bottom:0;left:0;right:0;padding:24px 20px 16px;background:linear-gradient(transparent,rgba(0,0,0,.92));display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;-webkit-justify-content:space-between;justify-content:space-between;gap:10px;opacity:1;transition:opacity .3s ease;z-index:20}",
    "#controls.hidden{opacity:0;pointer-events:none}",
    ".group{display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;gap:8px}",
    ".btn{background:rgba(255,255,255,.15);color:#fff;border:1px solid rgba(255,255,255,.2);padding:8px 12px;border-radius:10px;font-size:13px;font-weight:600;cursor:pointer;text-align:center}",
    ".btn small{display:block;font-size:10px;font-weight:400;opacity:.75}",
    ".btn:hover,.btn:focus{background:rgba(255,255,255,.3);outline:2px solid #00f2fe}",
    ".btn.active{background:#0072ff;border-color:#00c6ff}",
    ".live-badge{display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;gap:6px;color:#fff;font-size:12px;font-weight:700;padding:8px 10px;background:rgba(255,59,48,.25);border:1px solid rgba(255,59,48,.5);border-radius:8px}",
    ".dot{width:8px;height:8px;background:#ff3b30;border-radius:50%}",
    "#settings-menu{position:fixed;bottom:82px;right:20px;background:rgba(22,22,26,.96);border:1px solid rgba(255,255,255,.18);border-radius:14px;padding:14px;width:270px;color:#fff;display:none;-webkit-flex-direction:column;flex-direction:column;gap:12px;z-index:30}",
    "#settings-menu.open{display:-webkit-flex;display:flex}",
    ".menu-row{display:-webkit-flex;display:flex;-webkit-justify-content:space-between;justify-content:space-between;-webkit-align-items:center;align-items:center;font-size:13px}",
    ".menu-row span small{display:block;font-size:10px;opacity:.7}",
    "select{background:#323238;color:#fff;border:none;padding:6px 8px;border-radius:8px;font-size:12px}",
    "</style></head><body>",
    "<div id='brand'><div class='brand-icon'><div class='brand-play'></div></div><div class='brand-text'><span class='brand-title'>MirrorTV</span><span class='brand-sub'>by Zoso</span></div></div>",
    "<div id='pause-banner'>IN PAUSA<br><small style='font-size:13px;font-weight:400'>PAUSED</small></div>",
    "<img id='v' src='/stream' ondblclick='toggleFullscreen()'>",
    "<div id='settings-menu'>",
    "<div class='menu-row'><span>Qualità<small>Resolution</small></span><select id='sel-res' onchange='sendCtrl(\"res=\"+this.value)'><option value='3840'>4K (2160p)</option><option value='2560'>2K (1440p)</option><option value='1920'>1080p Full HD</option><option value='1280' selected>720p HD</option><option value='854'>480p SD</option><option value='640'>360p</option><option value='426'>240p</option></select></div>",
    "<div class='menu-row'><span>Fluidità<small>Frame Rate</small></span><select id='sel-fps' onchange='sendCtrl(\"fps=\"+this.value)'><option value='60'>60 FPS</option><option value='50'>50 FPS</option><option value='30' selected>30 FPS</option><option value='25'>25 FPS</option><option value='15'>15 FPS</option><option value='10'>10 FPS</option></select></div>",
    "<div class='menu-row'><span>Velocità<small>Speed</small></span><select id='sel-spd' onchange='sendCtrl(\"speed=\"+this.value)'><option value='0.25'>0.25x</option><option value='0.5'>0.5x</option><option value='0.75'>0.75x</option><option value='1.0' selected>1.0x</option><option value='1.25'>1.25x</option><option value='1.5'>1.5x</option><option value='2.0'>2.0x</option></select></div>",
    "<div class='menu-row'><span>Formato<small>Aspect Fit</small></span><select id='sel-fit' onchange='sendCtrl(\"fit=\"+this.value)'><option value='contain' selected>Adatta / Fit</option><option value='zoom'>Zoom 118%</option></select></div>",
    "</div>",
    "<div id='controls'>",
    "<div class='group'><div class='live-badge'><span class='dot'></span> LIVE</div><button id='btn-pause' class='btn' onclick='togglePause()'>⏸ Pausa<small>Pause</small></button><button id='btn-audio' class='btn' onclick='toggleAudio()'>🔇 Audio<small>Enable Audio</small></button></div>",
    "<div class='group'><button class='btn' onclick='rotateVideo()'>↻ Ruota<small>Rotate</small></button><button class='btn' onclick='toggleMenu()'>⚙️ Opzioni<small>Settings</small></button><button class='btn' onclick='toggleFullscreen()'>⛶ Intero<small>Fullscreen</small></button></div>",
    "</div>",
    "<script>",
    "var ctx=null,nextTime=0,audioRunning=false,audioAbort=null,rotation=0,zoomed=false,paused=false,hideTimer=null;",
    "function showControls(){var c=document.getElementById('controls'),b=document.getElementById('brand');c.classList.remove('hidden');b.classList.remove('hidden');clearTimeout(hideTimer);hideTimer=setTimeout(function(){if(!document.getElementById('settings-menu').classList.contains('open')){c.classList.add('hidden');b.classList.add('hidden')}},3500)}",
    "document.addEventListener('mousemove',showControls);document.addEventListener('touchstart',showControls);document.addEventListener('keydown',showControls);showControls();",
    "function toggleMenu(){document.getElementById('settings-menu').classList.toggle('open')}",
    "function applyTransform(){var i=document.getElementById('v');i.style.transform='rotate('+rotation+'deg)'+(zoomed?' scale(1.18)':'')}",
    "function sendCtrl(q){var x=new XMLHttpRequest();x.open('GET','/control?'+q,true);x.send()}",
    "function togglePause(){paused=!paused;sendCtrl('paused='+(paused?1:0));updateUI()}",
    "function rotateVideo(){rotation=(rotation+90)%360;sendCtrl('rot='+rotation);applyTransform()}",
    "function toggleFullscreen(){if(!document.fullscreenElement){if(document.documentElement.requestFullscreen)document.documentElement.requestFullscreen()}else{if(document.exitFullscreen)document.exitFullscreen()}}",
    "function updateUI(){var pb=document.getElementById('btn-pause'),bn=document.getElementById('pause-banner');if(paused){pb.innerHTML='▶ Riprendi<small>Resume</small>';pb.classList.add('active');bn.style.display='block'}else{pb.innerHTML='⏸ Pausa<small>Pause</small>';pb.classList.remove('active');bn.style.display='none'}applyTransform()}",
    "function toggleAudio(){if(audioRunning){stopAudio();sendCtrl('audio=0')}else{startAudio();sendCtrl('audio=1')}}",
    "function stopAudio(){audioRunning=false;if(audioAbort){try{audioAbort.abort()}catch(e){}audioAbort=null}if(ctx){try{ctx.close()}catch(e){}ctx=null}nextTime=0;var b=document.getElementById('btn-audio');b.innerHTML='🔇 Audio<small>Enable Audio</small>';b.classList.remove('active')}",
    "async function startAudio(){if(audioRunning)return;audioRunning=true;var b=document.getElementById('btn-audio');b.innerHTML='🔊 Attivo<small>Audio On</small>';b.classList.add('active');audioAbort=new AbortController();try{var sr=44100;try{var ri=await fetch('/audio-info');if(ri.ok){var v=parseInt(await ri.text());if(v>8000)sr=v}}catch(e){}var AC=window.AudioContext||window.webkitAudioContext;ctx=new AC({sampleRate:sr});await ctx.resume();var res=await fetch('/audio?t='+Date.now(),{signal:audioAbort.signal}),rd=res.body.getReader(),left=new Uint8Array(0);while(audioRunning){var r=await rd.read();if(r.done)break;var buf=new Uint8Array(left.length+r.value.length);buf.set(left);buf.set(r.value,left.length);var u=buf.length-(buf.length%4);left=buf.slice(u);if(u===0)continue;var aligned=new Uint8Array(u);aligned.set(buf.subarray(0,u));var n=u/4,i16=new Int16Array(aligned.buffer),ab=ctx.createBuffer(2,n,sr),L=ab.getChannelData(0),R=ab.getChannelData(1);for(var i=0;i<n;i++){L[i]=i16[2*i]/32768.0;R[i]=i16[2*i+1]/32768.0}var now=ctx.currentTime;if(nextTime<now+0.04)nextTime=now+0.18;if(nextTime>now+0.9)continue;var src=ctx.createBufferSource();src.buffer=ab;src.connect(ctx.destination);src.start(nextTime);nextTime+=ab.duration}}catch(e){if(audioRunning)stopAudio()}}",
    "setInterval(function(){var x=new XMLHttpRequest();x.open('GET','/state',true);x.onreadystatechange=function(){if(x.readyState===4&&x.status===200){try{var s=JSON.parse(x.responseText);document.getElementById('sel-res').value=s.res;document.getElementById('sel-fps').value=s.fps;document.getElementById('sel-spd').value=s.speed;document.getElementById('sel-fit').value=s.fit;rotation=s.rot;zoomed=(s.fit==='zoom');paused=s.paused;if(s.audio&&!audioRunning)startAudio();if(!s.audio&&audioRunning)stopAudio();updateUI()}catch(e){}}};x.send()},500);",
    "var img=document.getElementById('v');img.onerror=function(){setTimeout(function(){img.src='/stream?t='+Date.now()},1000)};",
    "</script></body></html>"
].joined()

final class MJPEGServer {
    private var listenFD: Int32 = -1
    private var clients: [Int32] = []
    private var audioClients: [Int32] = []
    private var busy = false
    private var audioPending = 0
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "mirrortv.send", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "mirrortv.audio", qos: .userInteractive)

    var maxResolution: CGFloat = 1280
    var targetFPS: Double = 30.0
    var playbackSpeed: String = "1.0"
    var fitMode: String = "contain"
    var rotationDeg: Int = 0
    var isPaused: Bool = false
    var audioRequested: Bool = false
    var detectedSampleRate: Int = 44100

    var hasClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty && !isPaused
    }

    var hasAudioClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !audioClients.isEmpty && !isPaused
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
        guard bound == 0, listen(fd, 16) == 0 else {
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
            DispatchQueue.global(qos: .userInteractive).async { [self] in handle(client) }
        }
    }

    private func handle(_ client: Int32) {
        var yes: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout<Int32>.size))
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
            let head = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock()
                if clients.count > 3 {
                    let old = clients.removeFirst()
                    close(old)
                }
                clients.append(client)
                lock.unlock()
            } else {
                close(client)
            }
        } else if path.hasPrefix("/audio-info") {
            lock.lock(); let sr = String(detectedSampleRate); lock.unlock()
            let body = Data(sr.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        } else if path.hasPrefix("/audio") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock()
                for old in audioClients { close(old) }
                audioClients.removeAll()
                audioClients.append(client)
                audioRequested = true
                lock.unlock()
            } else {
                close(client)
            }
        } else if path.hasPrefix("/control") {
            if let comps = URLComponents(string: path), let items = comps.queryItems {
                lock.lock()
                for item in items {
                    switch item.name {
                    case "res": if let val = Double(item.value ?? "") { maxResolution = CGFloat(val) }
                    case "fps": if let val = Double(item.value ?? ""), val > 0 { targetFPS = val }
                    case "speed": if let val = item.value { playbackSpeed = val }
                    case "fit": if let val = item.value { fitMode = val }
                    case "rot": if let val = Int(item.value ?? "") { rotationDeg = val }
                    case "paused": isPaused = (item.value == "1")
                    case "audio":
                        audioRequested = (item.value == "1")
                        if !audioRequested {
                            for old in audioClients { close(old) }
                            audioClients.removeAll()
                        }
                    default: break
                    }
                }
                lock.unlock()
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\nOK"
            _ = sendAll(client, Data(head.utf8))
            close(client)
        } else if path.hasPrefix("/state") {
            lock.lock()
            let jsonStr = "{\"res\":\"\(Int(maxResolution))\",\"fps\":\"\(Int(targetFPS))\",\"speed\":\"\(playbackSpeed)\",\"fit\":\"\(fitMode)\",\"rot\":\(rotationDeg),\"paused\":\(isPaused),\"audio\":\(audioRequested)}"
            lock.unlock()
            let body = Data(jsonStr.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        } else {
            let body = Data(pageHTML.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        }
    }

    func broadcast(_ jpeg: Data) {
        lock.lock()
        if busy || clients.isEmpty || isPaused { lock.unlock(); return }
        busy = true
        let snapshot = clients
        lock.unlock()

        sendQueue.async { [self] in
            var packet = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
            packet.append(jpeg)
            packet.append(Data("\r\n".utf8))

            var dead = Set<Int32>()
            for fd in snapshot where !sendAll(fd, packet) { dead.insert(fd) }

            lock.lock()
            clients.removeAll { dead.contains($0) }
            busy = false
            lock.unlock()
            for fd in dead { close(fd) }
        }
    }

    func broadcastAudio(_ pcm: Data) {
        lock.lock()
        if audioClients.isEmpty || audioPending > 12 || isPaused { lock.unlock(); return }
        audioPending += 1
        let snapshot = audioClients
        lock.unlock()

        audioQueue.async { [self] in
            var dead = Set<Int32>()
            for fd in snapshot where !sendAll(fd, pcm) { dead.insert(fd) }

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
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
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
            guard server.hasClients else { return }
            let now = CACurrentMediaTime()
            if now - lastFrameTime < (1.0 / server.targetFPS) { return }
            lastFrameTime = now

            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

                if let orientationVal = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
                   let rawOrientation = CGImagePropertyOrientation(rawValue: orientationVal.uint32Value) {
                    let fixedOrientation: CGImagePropertyOrientation
                    switch rawOrientation {
                    case .left: fixedOrientation = .right
                    case .right: fixedOrientation = .left
                    case .down: fixedOrientation = .down
                    default: fixedOrientation = .up
                    }
                    if fixedOrientation != .up {
                        ciImage = ciImage.oriented(fixedOrientation)
                    }
                }

                let maxDimension = server.maxResolution
                let scale = min(1.0, maxDimension / max(ciImage.extent.width, ciImage.extent.height))
                if scale < 1.0 {
                    ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                }

                let quality: CGFloat = maxDimension >= 1920 ? 0.52 : 0.65
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]) {
                    server.broadcast(jpegData)
                }
            }

        case .audioApp:
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                let sr = Int(asbd.mSampleRate)
                if sr > 8000 && server.detectedSampleRate != sr {
                    server.detectedSampleRate = sr
                }
            }
            guard server.hasAudioClients else { return }
            autoreleasepool {
                if let pcmData = extractCleanStereoPCM(sampleBuffer) {
                    server.broadcastAudio(pcmData)
                }
            }

        default:
            break
        }
    }

    private func extractCleanStereoPCM(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPtr.pointee
        let channels = Int(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bits = Int(asbd.mBitsPerChannel)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var totalLength = 0
        var dataPtr: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPtr)
        guard status == kCMBlockBufferNoErr, let basePtr = dataPtr, totalLength > 0 else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        var out = Data(count: frameCount * 4)
        out.withUnsafeMutableBytes { outRaw in
            guard let outInt16 = outRaw.bindMemory(to: Int16.self).baseAddress else { return }
            if !isFloat && bits == 16 {
                let rawSamples = UnsafeRawPointer(basePtr).bindMemory(to: Int16.self, capacity: totalLength / 2)
                for i in 0..<frameCount {
                    var left: Int16 = channels >= 2 ? (isNonInterleaved ? rawSamples[i] : rawSamples[i * channels]) : rawSamples[i]
                    var right: Int16 = channels >= 2 ? (isNonInterleaved ? rawSamples[frameCount + i] : rawSamples[i * channels + 1]) : left
                    if isBigEndian {
                        left = Int16(bigEndian: left)
                        right = Int16(bigEndian: right)
                    }
                    outInt16[2 * i] = left.littleEndian
                    outInt16[2 * i + 1] = right.littleEndian
                }
            } else if isFloat && bits == 32 {
                let rawFloats = UnsafeRawPointer(basePtr).bindMemory(to: Float32.self, capacity: totalLength / 4)
                for i in 0..<frameCount {
                    let lF: Float32 = channels >= 2 ? (isNonInterleaved ? rawFloats[i] : rawFloats[i * channels]) : rawFloats[i]
                    let rF: Float32 = channels >= 2 ? (isNonInterleaved ? rawFloats[frameCount + i] : rawFloats[i * channels + 1]) : lF
                    outInt16[2 * i] = Int16(max(-1.0, min(1.0, lF)) * 32767.0).littleEndian
                    outInt16[2 * i + 1] = Int16(max(-1.0, min(1.0, rF)) * 32767.0).littleEndian
                }
            }
        }
        return out
    }
}
