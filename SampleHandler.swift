import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

private let pageHTML = [
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta http-equiv='X-UA-Compatible' content='IE=edge'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'>",
    "<title>MirrorTV by Zoso</title><style>",
    "*{box-sizing:border-box;-webkit-user-select:none;user-select:none}",
    "html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden;font-family:Arial,Helvetica,sans-serif}",
    "#stage{position:fixed;top:0;left:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center;background:#000}",
    "#v{width:100%;height:100%;max-width:100vw;max-height:100vh;object-fit:contain;display:block;transition:transform .2s ease}",
    "#brand{position:fixed;top:16px;left:18px;display:flex;align-items:center;gap:10px;padding:8px 14px;background:rgba(15,15,20,.85);border:1px solid rgba(255,255,255,.18);border-radius:14px;z-index:25;transition:opacity .3s ease}",
    "#brand.hidden{opacity:0;pointer-events:none}",
    ".app-logo{width:34px;height:34px;border-radius:9px;background:#101218;border:1.5px solid #00f2fe;display:flex;align-items:center;justify-content:center;box-shadow:0 0 10px rgba(0,242,254,.5)}",
    ".brand-text{display:flex;flex-direction:column;line-height:1.15}",
    ".brand-title{color:#fff;font-size:15px;font-weight:800}",
    ".brand-sub{font-size:11px;font-weight:700;color:#00f2fe}",
    "#controls{position:fixed;bottom:0;left:0;right:0;padding:22px 18px 14px;background:rgba(0,0,0,.85);display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px;opacity:1;transition:opacity .3s ease;z-index:20}",
    "#controls.hidden{opacity:0;pointer-events:none}",
    ".group{display:flex;flex-wrap:wrap;align-items:center;gap:8px}",
    ".btn{background:rgba(255,255,255,.15);color:#fff;border:1px solid rgba(255,255,255,.25);padding:7px 12px;border-radius:9px;cursor:pointer;text-align:center;display:inline-flex;flex-direction:column;align-items:center;justify-content:center}",
    ".btn:hover,.btn:focus{background:rgba(255,255,255,.3);outline:2px solid #00f2fe}",
    ".btn.active{background:#0072ff;border-color:#00f2fe}",
    ".lbl-it{font-size:13px;font-weight:700;line-height:1.1}",
    ".lbl-en{font-size:10px;font-weight:400;opacity:.75;line-height:1.1;margin-top:2px}",
    ".live-badge{display:flex;align-items:center;gap:6px;color:#fff;padding:6px 10px;background:rgba(255,59,48,.25);border:1px solid rgba(255,59,48,.5);border-radius:8px}",
    ".dot{width:8px;height:8px;background:#ff3b30;border-radius:50%}",
    "#settings-menu{position:fixed;bottom:82px;right:18px;background:rgba(20,20,25,.96);border:1px solid rgba(255,255,255,.2);border-radius:14px;padding:14px;width:280px;color:#fff;display:none;flex-direction:column;gap:12px;z-index:30}",
    "#settings-menu.open{display:flex}",
    ".menu-row{display:flex;justify-content:space-between;align-items:center}",
    ".menu-lbl{display:flex;flex-direction:column}",
    "select{background:#2c2c34;color:#fff;border:1px solid rgba(255,255,255,.2);padding:6px 8px;border-radius:8px;font-size:12px;outline:none}",
    "</style></head><body>",
    "<div id='brand'>",
    "<div class='app-logo'><svg width='24' height='24' viewBox='0 0 24 24' fill='none'><rect x='2' y='5' width='16' height='12' rx='3' stroke='#00f2fe' stroke-width='2.2'/><path d='M8 9L13 11L8 13V9Z' fill='#ff4b2b'/><path d='M16 3C18.5 3 21 5.5 21 8' stroke='#ff758c' stroke-width='2' stroke-linecap='round'/><line x1='6' y1='20' x2='14' y2='20' stroke='#ff758c' stroke-width='2.2' stroke-linecap='round'/></svg></div>",
    "<div class='brand-text'><span class='brand-title'>MirrorTV</span><span class='brand-sub'>by Zoso</span></div>",
    "</div>",
    "<div id='stage'><img id='v' src='/stream' ondblclick='toggleFullscreen()'></div>",
    "<div id='settings-menu'>",
    "<div class='menu-row'><div class='menu-lbl'><span class='lbl-it'>Risoluzione</span><span class='lbl-en'>Resolution</span></div><select id='sel-res' onchange='updateConfig()'><option value='3840'>4K (2160p)</option><option value='2560'>2K (1440p)</option><option value='1920'>1080p Full HD</option><option value='1280' selected>720p HD</option><option value='854'>480p SD</option><option value='640'>360p</option><option value='426'>240p</option></select></div>",
    "<div class='menu-row'><div class='menu-lbl'><span class='lbl-it'>Fluidità</span><span class='lbl-en'>Frame Rate</span></div><select id='sel-fps' onchange='updateConfig()'><option value='60'>60 FPS</option><option value='50'>50 FPS</option><option value='30' selected>30 FPS</option><option value='24'>24 FPS</option><option value='15'>15 FPS</option><option value='10'>10 FPS</option></select></div>",
    "<div class='menu-row'><div class='menu-lbl'><span class='lbl-it'>Velocità</span><span class='lbl-en'>Playback Speed</span></div><select id='sel-speed' onchange='updateConfig()'><option value='0.25'>0.25x</option><option value='0.5'>0.5x</option><option value='0.75'>0.75x</option><option value='1.0' selected>1.0x (Normale)</option><option value='1.25'>1.25x</option><option value='1.5'>1.5x</option><option value='2.0'>2.0x</option></select></div>",
    "<div class='menu-row'><div class='menu-lbl'><span class='lbl-it'>Formato Schermo</span><span class='lbl-en'>Screen Aspect</span></div><select id='sel-fit' onchange='toggleFit(this.value)'><option value='contain' selected>Adatta / Fit</option><option value='zoom'>Zoom (118%)</option></select></div>",
    "</div>",
    "<div id='controls'>",
    "<div class='group'>",
    "<div class='live-badge'><span class='dot'></span><div><div class='lbl-it'>DAL VIVO</div><div class='lbl-en'>LIVE</div></div></div>",
    "<button id='btn-audio' class='btn' onclick='toggleAudio()'><span id='aud-it' class='lbl-it'>🔇 Attiva Audio</span><span id='aud-en' class='lbl-en'>Enable Audio</span></button>",
    "</div>",
    "<div class='group'>",
    "<button class='btn' onclick='rotateVideo()'><span class='lbl-it'>↻ Ruota</span><span class='lbl-en'>Rotate</span></button>",
    "<button class='btn' onclick='toggleMenu()'><span class='lbl-it'>⚙️ Impostazioni</span><span class='lbl-en'>Settings</span></button>",
    "<button class='btn' onclick='toggleFullscreen()'><span class='lbl-it'>⛶ Schermo Intero</span><span class='lbl-en'>Fullscreen</span></button>",
    "</div>",
    "</div>",
    "<script>",
    "var ctx=null,nextTime=0,audioRunning=false,audioReader=null,audioAbort=null,rotation=0,zoomed=false,hideTimer=null,lastActionId=0,streamSpeed=1.0;",
    "function showControls(){var c=document.getElementById('controls'),b=document.getElementById('brand');c.classList.remove('hidden');b.classList.remove('hidden');clearTimeout(hideTimer);hideTimer=setTimeout(function(){if(!document.getElementById('settings-menu').classList.contains('open')){c.classList.add('hidden');b.classList.add('hidden')}},3500)}",
    "document.addEventListener('mousemove',showControls);document.addEventListener('touchstart',showControls);document.addEventListener('keydown',showControls);showControls();",
    "function toggleMenu(){document.getElementById('settings-menu').classList.toggle('open')}",
    "function applyTransform(){var i=document.getElementById('v');i.style.transform='rotate('+rotation+'deg)'+(zoomed?' scale(1.18)':'')}",
    "function toggleFit(m){zoomed=(m==='zoom');applyTransform();fetch('/config?fit='+m).catch(function(){})}",
    "function rotateVideo(){rotation=(rotation+90)%360;applyTransform();fetch('/config?rot='+rotation).catch(function(){})}",
    "function toggleFullscreen(){if(!document.fullscreenElement){var el=document.documentElement;if(el.requestFullscreen)el.requestFullscreen().catch(function(){});else if(el.webkitRequestFullscreen)el.webkitRequestFullscreen();}else{if(document.exitFullscreen)document.exitFullscreen().catch(function(){});else if(document.webkitExitFullscreen)document.webkitExitFullscreen();}}",
    "function updateConfig(){var r=document.getElementById('sel-res').value,f=document.getElementById('sel-fps').value,s=document.getElementById('sel-speed').value;streamSpeed=parseFloat(s)||1.0;fetch('/config?res='+r+'&fps='+f+'&speed='+s).catch(function(){})}",
    "function setAudioBtn(active,err){var b=document.getElementById('btn-audio'),it=document.getElementById('aud-it'),en=document.getElementById('aud-en');if(active){b.classList.add('active');it.textContent='🔊 Audio Attivo';en.textContent='Audio Active';}else{b.classList.remove('active');it.textContent=err?'🔇 Riprova Audio':'🔇 Attiva Audio';en.textContent=err?'Retry Audio':'Enable Audio';}}",
    "function stopAudioClean(){audioRunning=false;if(audioReader){try{audioReader.cancel()}catch(e){}audioReader=null}if(audioAbort){try{audioAbort.abort()}catch(e){}audioAbort=null}if(ctx){try{ctx.close()}catch(e){}ctx=null}nextTime=0;setAudioBtn(false,false)}",
    "async function startAudioClean(){stopAudioClean();audioRunning=true;setAudioBtn(true,false);audioAbort=new AbortController();try{var sr=44100;try{var rInfo=await fetch('/audio-info');if(rInfo.ok){var v=parseInt(await rInfo.text());if(v>8000)sr=v}}catch(e){}var AC=window.AudioContext||window.webkitAudioContext;ctx=new AC({sampleRate:sr});if(ctx.state==='suspended')await ctx.resume();var res=await fetch('/audio?t='+Date.now(),{signal:audioAbort.signal});audioReader=res.body.getReader();var left=new Uint8Array(0);while(audioRunning){var r=await audioReader.read();if(r.done||!audioRunning)break;var buf=new Uint8Array(left.length+r.value.length);buf.set(left);buf.set(r.value,left.length);var u=buf.length-(buf.length%4);left=buf.slice(u);if(u===0)continue;var aligned=new Uint8Array(u);aligned.set(buf.subarray(0,u));var n=u/4,i16=new Int16Array(aligned.buffer),ab=ctx.createBuffer(2,n,sr),L=ab.getChannelData(0),R=ab.getChannelData(1);for(var i=0;i<n;i++){L[i]=i16[2*i]/32768.0;R[i]=i16[2*i+1]/32768.0}var now=ctx.currentTime;if(nextTime<now+0.04)nextTime=now+0.18;if(nextTime>now+0.75)continue;var src=ctx.createBufferSource();src.buffer=ab;src.playbackRate.value=streamSpeed;src.connect(ctx.destination);src.start(nextTime);nextTime+=(ab.duration/streamSpeed)}}catch(e){if(audioRunning){stopAudioClean();setAudioBtn(false,true)}}}",
    "function toggleAudio(){if(audioRunning){stopAudioClean();fetch('/config?mute=1').catch(function(){})}else{startAudioClean();fetch('/config?mute=0').catch(function(){})}}",
    "setInterval(function(){fetch('/state').then(function(r){return r.json()}).then(function(st){if(st.res&&document.getElementById('sel-res').value!==st.res)document.getElementById('sel-res').value=st.res;if(st.fps&&document.getElementById('sel-fps').value!==st.fps)document.getElementById('sel-fps').value=st.fps;if(st.speed&&document.getElementById('sel-speed').value!==st.speed){document.getElementById('sel-speed').value=st.speed;streamSpeed=parseFloat(st.speed)||1.0}if(st.fit&&document.getElementById('sel-fit').value!==st.fit){document.getElementById('sel-fit').value=st.fit;zoomed=(st.fit==='zoom');applyTransform()}if(typeof st.rot==='number'&&rotation!==st.rot){rotation=st.rot;applyTransform()}if(typeof st.audioMuted==='boolean'){if(st.audioMuted&&audioRunning)stopAudioClean();else if(!st.audioMuted&&!audioRunning)startAudioClean()}if(st.actionId&&st.actionId!==lastActionId){lastActionId=st.actionId;if(st.lastAction==='fullscreen')toggleFullscreen()}}).catch(function(){})},900);",
    "var img=document.getElementById('v');setInterval(function(){if(img.naturalWidth===0)img.src='/stream?t='+Date.now()},4000);",
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
    var streamSpeed: Double = 1.0
    var fitMode: String = "contain"
    var rotation: Int = 0
    var audioMuted: Bool = true
    var actionId: Int = 0
    var lastAction: String = ""
    var detectedSampleRate: Int = 44100

    var effectiveFPS: Double {
        lock.lock(); defer { lock.unlock() }
        return max(5.0, min(60.0, targetFPS * streamSpeed))
    }

    var currentMaxRes: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return maxResolution
    }

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
        guard bound == 0, listen(fd, 12) == 0 else {
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
        var tv = timeval(tv_sec: 1, tv_usec: 500000)
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8](repeating: 0, count: 2048)
        let n = recv(client, &buf, buf.count, 0)
        guard n > 0 else { close(client); return }

        let request = String(decoding: buf[0..<n], as: UTF8.self)
        let parts = request.split(separator: " ")
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if path.hasPrefix("/stream") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock()
                if clients.count >= 4 {
                    let old = clients.removeFirst()
                    close(old)
                }
                clients.append(client)
                lock.unlock()
            } else {
                close(client)
            }
        } else if path.hasPrefix("/audio-info") {
            lock.lock()
            let sr = String(detectedSampleRate)
            lock.unlock()
            let body = Data(sr.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        } else if path.hasPrefix("/audio") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store, no-cache\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock()
                let oldAudio = audioClients
                audioClients.removeAll()
                audioClients.append(client)
                audioPending = 0
                lock.unlock()
                for c in oldAudio { close(c) }
            } else {
                close(client)
            }
        } else if path.hasPrefix("/state") {
            lock.lock()
            let jsonStr = "{\"res\":\"\(Int(maxResolution))\",\"fps\":\"\(Int(targetFPS))\",\"speed\":\"\(streamSpeed)\",\"fit\":\"\(fitMode)\",\"rot\":\(rotation),\"audioMuted\":\(audioMuted),\"actionId\":\(actionId),\"lastAction\":\"\(lastAction)\"}"
            lock.unlock()
            let body = Data(jsonStr.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        } else if path.hasPrefix("/config") {
            if let comps = URLComponents(string: path), let items = comps.queryItems {
                lock.lock()
                for item in items {
                    let v = item.value ?? ""
                    if item.name == "res", let d = Double(v), d > 100 {
                        maxResolution = CGFloat(d)
                    } else if item.name == "fps", let d = Double(v), d > 0 {
                        targetFPS = d
                    } else if item.name == "speed", let d = Double(v), d > 0 {
                        streamSpeed = d
                    } else if item.name == "fit", !v.isEmpty {
                        fitMode = v
                    } else if item.name == "rot", let r = Int(v) {
                        rotation = r % 360
                    } else if item.name == "mute" {
                        audioMuted = (v == "1")
                    } else if item.name == "action", !v.isEmpty {
                        lastAction = v
                        actionId += 1
                    }
                }
                lock.unlock()
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
            _ = sendAll(client, Data(head.utf8))
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
        // Drop-frame automatico: se il client sta ancora scaricando, salta il fotogramma per evitare coda e scatti
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
        if audioClients.isEmpty || audioPending > 6 { lock.unlock(); return }
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
            audioPending = max(0, audioPending - 1)
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
            if now - lastFrameTime < (1.0 / server.effectiveFPS) { return }
            lastFrameTime = now

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            autoreleasepool {
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

                let maxDimension = server.currentMaxRes
                let scale = min(1.0, maxDimension / max(ciImage.extent.width, ciImage.extent.height))
                if scale < 1.0 {
                    ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                }

                // Qualità adattiva per evitare accumuli e scatti alle risoluzioni alte
                let quality: CGFloat = maxDimension >= 2560 ? 0.52 : (maxDimension >= 1920 ? 0.58 : 0.65)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let jpegData = ciContext.jpegRepresentation(
                    of: ciImage,
                    colorSpace: colorSpace,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
                ) {
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
            guard let pcmData = extractCleanStereoPCM(sampleBuffer) else { return }
            server.broadcastAudio(pcmData)

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

        var out = Data(capacity: frameCount * 4)

        if !isFloat && bits == 16 {
            let rawSamples = UnsafeRawPointer(basePtr).bindMemory(to: Int16.self, capacity: totalLength / 2)
            for i in 0..<frameCount {
                var left: Int16 = 0
                var right: Int16 = 0
                if channels >= 2 {
                    if isNonInterleaved {
                        left = rawSamples[i]
                        right = rawSamples[frameCount + i]
                    } else {
                        left = rawSamples[i * channels]
                        right = rawSamples[i * channels + 1]
                    }
                } else {
                    left = rawSamples[i]
                    right = left
                }
                if isBigEndian {
                    left = Int16(bigEndian: left)
                    right = Int16(bigEndian: right)
                }
                var lLE = left.littleEndian
                var rLE = right.littleEndian
                out.append(UnsafeBufferPointer(start: &lLE, count: 1))
                out.append(UnsafeBufferPointer(start: &rLE, count: 1))
            }
            return out
        } else if isFloat && bits == 32 {
            let rawFloats = UnsafeRawPointer(basePtr).bindMemory(to: Float32.self, capacity: totalLength / 4)
            for i in 0..<frameCount {
                var lF: Float32 = 0
                var rF: Float32 = 0
                if channels >= 2 {
                    if isNonInterleaved {
                        lF = rawFloats[i]
                        rF = rawFloats[frameCount + i]
                    } else {
                        lF = rawFloats[i * channels]
                        rF = rawFloats[i * channels + 1]
                    }
                } else {
                    lF = rawFloats[i]
                    rF = lF
                }
                let lClamped = max(-1.0, min(1.0, lF))
                let rClamped = max(-1.0, min(1.0, rF))
                var lLE = Int16(lClamped * 32767.0).littleEndian
                var rLE = Int16(rClamped * 32767.0).littleEndian
                out.append(UnsafeBufferPointer(start: &lLE, count: 1))
                out.append(UnsafeBufferPointer(start: &rLE, count: 1))
            }
            return out
        }

        return nil
    }
}
