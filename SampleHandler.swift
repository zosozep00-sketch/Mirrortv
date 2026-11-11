import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

private let pageHTML = [
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>MirrorTV by Zoso</title><style>",
    "*{box-sizing:border-box;user-select:none}",
    "html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;display:flex;align-items:center;justify-content:center}",
    "#v{width:100vw;height:100vh;object-fit:contain;display:block;transition:transform .25s ease}",
    "#v.zoomed{transform:scale(1.18)}",
    "#brand{position:fixed;top:18px;left:22px;display:flex;align-items:center;gap:10px;padding:8px 14px;background:rgba(18,18,22,.78);border:1px solid rgba(255,255,255,.15);border-radius:14px;backdrop-filter:blur(10px);z-index:25;transition:opacity .3s ease}",
    "#brand.hidden{opacity:0;pointer-events:none}",
    ".brand-icon{width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,#00f2fe,#ff4b2b);display:flex;align-items:center;justify-content:center;box-shadow:0 0 12px rgba(0,242,254,.5)}",
    ".brand-play{width:0;height:0;border-top:6px solid transparent;border-bottom:6px solid transparent;border-left:10px solid #fff;margin-left:2px}",
    ".brand-text{display:flex;flex-direction:column;line-height:1.1}",
    ".brand-title{color:#fff;font-size:15px;font-weight:800;letter-spacing:.3px}",
    ".brand-sub{font-size:11px;font-weight:600;background:linear-gradient(90deg,#00f2fe,#ff758c);-webkit-background-clip:text;-webkit-text-fill-color:transparent}",
    "#controls{position:fixed;bottom:0;left:0;right:0;padding:28px 22px 18px;background:linear-gradient(transparent,rgba(0,0,0,.9));display:flex;align-items:center;justify-content:space-between;gap:12px;opacity:1;transition:opacity .3s ease;z-index:20}",
    "#controls.hidden{opacity:0;pointer-events:none}",
    ".group{display:flex;align-items:center;gap:10px}",
    ".btn{background:rgba(255,255,255,.14);color:#fff;border:1px solid rgba(255,255,255,.18);padding:8px 14px;border-radius:10px;font-size:14px;font-weight:500;cursor:pointer;backdrop-filter:blur(6px)}",
    ".btn:hover{background:rgba(255,255,255,.26)}",
    ".btn.active{background:linear-gradient(135deg,#00c6ff,#0072ff);border-color:transparent}",
    ".live-badge{display:flex;align-items:center;gap:6px;color:#fff;font-size:12px;font-weight:700;padding:6px 10px;background:rgba(255,59,48,.2);border:1px solid rgba(255,59,48,.4);border-radius:8px}",
    ".dot{width:8px;height:8px;background:#ff3b30;border-radius:50%;animation:pulse 1.5s infinite}",
    "@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}",
    "#settings-menu{position:fixed;bottom:76px;right:22px;background:rgba(22,22,26,.95);border:1px solid rgba(255,255,255,.15);border-radius:14px;padding:14px;width:250px;color:#fff;display:none;flex-direction:column;gap:12px;backdrop-filter:blur(12px);z-index:30}",
    "#settings-menu.open{display:flex}",
    ".menu-row{display:flex;justify-content:space-between;align-items:center;font-size:14px}",
    "select{background:#323238;color:#fff;border:none;padding:6px 10px;border-radius:8px;font-size:13px;outline:none}",
    "</style></head><body>",
    "<div id='brand'><div class='brand-icon'><div class='brand-play'></div></div><div class='brand-text'><span class='brand-title'>MirrorTV</span><span class='brand-sub'>by Zoso</span></div></div>",
    "<img id='v' src='/stream' ondblclick='toggleFullscreen()'>",
    "<div id='settings-menu'>",
    "<div class='menu-row'><span>Qualità</span><select id='sel-res' onchange='updateConfig()'><option value='1920'>1080p HD</option><option value='1280' selected>720p HD</option><option value='854'>480p</option></select></div>",
    "<div class='menu-row'><span>Fluidità</span><select id='sel-fps' onchange='updateConfig()'><option value='60'>60 FPS</option><option value='30' selected>30 FPS</option><option value='15'>15 FPS</option></select></div>",
    "<div class='menu-row'><span>Formato</span><select id='sel-fit' onchange='toggleFit(this.value)'><option value='contain' selected>Adatta (Intero)</option><option value='zoom'>Zoom (118%)</option></select></div>",
    "</div>",
    "<div id='controls'>",
    "<div class='group'><div class='live-badge'><span class='dot'></span> LIVE</div><button id='btn-audio' class='btn' onclick='toggleAudio()'>🔇 Attiva audio</button></div>",
    "<div class='group'><button class='btn' onclick='rotateVideo()'>↻ Ruota</button><button class='btn' onclick='toggleMenu()'>⚙️ Impostazioni</button><button class='btn' onclick='toggleFullscreen()'>⛶ Schermo intero</button></div>",
    "</div>",
    "<script>",
    "var ctx=null,nextTime=0,audioRunning=false,audioAbort=null,rotation=0,zoomed=false,hideTimer=null;",
    "function showControls(){var c=document.getElementById('controls'),b=document.getElementById('brand');c.classList.remove('hidden');b.classList.remove('hidden');clearTimeout(hideTimer);hideTimer=setTimeout(function(){if(!document.getElementById('settings-menu').classList.contains('open')){c.classList.add('hidden');b.classList.add('hidden')}},3000)}",
    "document.addEventListener('mousemove',showControls);document.addEventListener('touchstart',showControls);showControls();",
    "function toggleMenu(){document.getElementById('settings-menu').classList.toggle('open')}",
    "function applyTransform(){var i=document.getElementById('v');i.style.transform='rotate('+rotation+'deg)'+(zoomed?' scale(1.18)':'')}",
    "function toggleFit(m){zoomed=(m==='zoom');applyTransform()}",
    "function rotateVideo(){rotation=(rotation+90)%360;applyTransform()}",
    "function toggleFullscreen(){if(!document.fullscreenElement)document.documentElement.requestFullscreen().catch(function(){});else document.exitFullscreen().catch(function(){})}",
    "function updateConfig(){var r=document.getElementById('sel-res').value,f=document.getElementById('sel-fps').value;fetch('/config?res='+r+'&fps='+f).catch(function(){})}",
    "async function toggleAudio(){var b=document.getElementById('btn-audio');if(audioRunning){audioRunning=false;if(audioAbort)audioAbort.abort();if(ctx){ctx.close();ctx=null}b.textContent='🔇 Attiva audio';b.classList.remove('active');return}audioRunning=true;b.textContent='🔊 Audio attivo';b.classList.add('active');audioAbort=new AbortController();try{ctx=new(window.AudioContext||window.webkitAudioContext)({sampleRate:48000});await ctx.resume();var res=await fetch('/audio',{signal:audioAbort.signal}),rd=res.body.getReader(),left=new Uint8Array(0);while(audioRunning){var r=await rd.read();if(r.done)break;var buf=new Uint8Array(left.length+r.value.length);buf.set(left);buf.set(r.value,left.length);var u=buf.length-(buf.length%4);left=buf.slice(u);if(u===0)continue;var aligned=new Uint8Array(u);aligned.set(buf.subarray(0,u));var n=u/4,i16=new Int16Array(aligned.buffer),ab=ctx.createBuffer(2,n,48000),L=ab.getChannelData(0),R=ab.getChannelData(1);for(var i=0;i<n;i++){L[i]=i16[2*i]/32768.0;R[i]=i16[2*i+1]/32768.0}var now=ctx.currentTime;if(nextTime<now+0.05)nextTime=now+0.25;if(nextTime>now+1.0)continue;var src=ctx.createBufferSource();src.buffer=ab;src.connect(ctx.destination);src.start(nextTime);nextTime+=ab.duration}}catch(e){if(audioRunning){audioRunning=false;b.textContent='🔇 Riprova audio';b.classList.remove('active')}}}",
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
