import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

private let pageHTML = [
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>Mirror TV</title><style>",
    "*{box-sizing:border-box;user-select:none;font-family:'Roboto',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}",
    "html,body{margin:0;padding:0;width:100vw;height:100vh;background:#000;overflow:hidden}",
    "#player{position:relative;width:100vw;height:100vh;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}",
    "#v{width:100%;height:100%;object-fit:contain;display:block;transition:transform .25s ease,filter .2s ease}",
    "#v.zoom{object-fit:cover}",
    "#center-hud{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.7);color:#fff;padding:16px 24px;border-radius:50px;font-size:18px;font-weight:500;opacity:0;pointer-events:none;transition:opacity .2s;z-index:25}",
    "#center-hud.show{opacity:1}",
    "#yt-controls{position:absolute;bottom:0;left:0;right:0;background:linear-gradient(to top,rgba(0,0,0,.9) 0%,rgba(0,0,0,.5) 60%,transparent 100%);padding:30px 16px 12px;display:flex;flex-direction:column;gap:8px;opacity:1;transition:opacity .25s ease;z-index:20}",
    "#yt-controls.hidden{opacity:0;pointer-events:none}",
    ".progress-wrap{width:100%;height:4px;background:rgba(255,255,255,.25);position:relative;cursor:pointer;border-radius:2px}",
    ".progress-bar{width:100%;height:100%;background:#ff0000;border-radius:2px;position:relative}",
    ".progress-dot{width:12px;height:12px;background:#ff0000;border-radius:50%;position:absolute;right:-4px;top:-4px}",
    ".bar-row{display:flex;align-items:center;justify-content:space-between;height:40px}",
    ".left-btns,.right-btns{display:flex;align-items:center;gap:6px}",
    ".yt-btn{background:transparent;border:none;color:#fff;height:36px;min-width:36px;padding:0 8px;border-radius:4px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;font-size:14px;font-weight:500;transition:background .15s}",
    ".yt-btn:hover{background:rgba(255,255,255,.15)}",
    ".yt-btn svg{width:22px;height:22px;fill:#fff}",
    ".live-pill{display:flex;align-items:center;gap:6px;color:#fff;font-size:13px;font-weight:500;padding:0 8px;cursor:default}",
    ".live-dot{width:8px;height:8px;background:#ff0000;border-radius:50%}",
    ".vol-wrap{display:flex;align-items:center;gap:4px}",
    "#vol-slider{width:0;opacity:0;transition:width .2s,opacity .2s;accent-color:#fff;cursor:pointer}",
    ".vol-wrap:hover #vol-slider{width:70px;opacity:1}",
    "#yt-menu{position:absolute;bottom:64px;right:16px;width:270px;background:rgba(28,28,28,.95);border-radius:12px;padding:8px 0;color:#fff;display:none;flex-direction:column;backdrop-filter:blur(16px);box-shadow:0 4px 20px rgba(0,0,0,.6);z-index:30;font-size:14px}",
    "#yt-menu.open{display:flex}",
    ".menu-item{display:flex;align-items:center;justify-content:space-between;padding:10px 16px;cursor:pointer;transition:background .15s}",
    ".menu-item:hover{background:rgba(255,255,255,.1)}",
    ".menu-label{display:flex;align-items:center;gap:10px}",
    ".menu-val{color:#aaa;font-size:13px;display:flex;align-items:center;gap:4px}",
    ".submenu{display:none;flex-direction:column}",
    ".submenu.active{display:flex}",
    ".sub-header{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid rgba(255,255,255,.15);cursor:pointer;font-weight:500}",
    ".sub-opt{padding:10px 16px 10px 38px;cursor:pointer;position:relative}",
    ".sub-opt:hover{background:rgba(255,255,255,.1)}",
    ".sub-opt.selected::before{content:'✓';position:absolute;left:16px;color:#fff}",
    "</style></head><body>",
    "<div id='player' ondblclick='toggleFullscreen()'>",
    "<img id='v' src='/stream'>",
    "<div id='center-hud'></div>",
    "<div id='yt-menu'>",
    "<div id='menu-main'>",
    "<div class='menu-item' onclick='openSub(\"sub-res\")'><span class='menu-label'>🎚️ Qualità</span><span class='menu-val' id='val-res'>720p HD ▸</span></div>",
    "<div class='menu-item' onclick='openSub(\"sub-fps\")'><span class='menu-label'>⚡ Fluidità (FPS)</span><span class='menu-val' id='val-fps'>30 FPS ▸</span></div>",
    "<div class='menu-item' onclick='openSub(\"sub-zoom\")'><span class='menu-label'>📐 Formato schermo</span><span class='menu-val' id='val-zoom'>Adatta ▸</span></div>",
    "<div class='menu-item' onclick='toggleFilter()'><span class='menu-label'>🎬 Modalità Cinema</span><span class='menu-val' id='val-cin'>Off</span></div>",
    "</div>",
    "<div id='sub-res' class='submenu'>",
    "<div class='sub-header' onclick='backMain()'>◂ Qualità</div>",
    "<div class='sub-opt' data-res='1920' onclick='setRes(1920,\"1080p HD\")'>1080p HD</div>",
    "<div class='sub-opt selected' data-res='1280' onclick='setRes(1280,\"720p HD\")'>720p HD</div>",
    "<div class='sub-opt' data-res='854' onclick='setRes(854,\"480p\")'>480p</div>",
    "</div>",
    "<div id='sub-fps' class='submenu'>",
    "<div class='sub-header' onclick='backMain()'>◂ Fluidità (FPS)</div>",
    "<div class='sub-opt' data-fps='60' onclick='setFps(60)'>60 FPS</div>",
    "<div class='sub-opt selected' data-fps='30' onclick='setFps(30)'>30 FPS</div>",
    "<div class='sub-opt' data-fps='15' onclick='setFps(15)'>15 FPS</div>",
    "</div>",
    "<div id='sub-zoom' class='submenu'>",
    "<div class='sub-header' onclick='backMain()'>◂ Formato schermo</div>",
    "<div class='sub-opt selected' data-zoom='fit' onclick='setZoom(\"fit\",\"Adatta\")'>Adatta (Originale)</div>",
    "<div class='sub-opt' data-zoom='zoom' onclick='setZoom(\"zoom\",\"Zoom\")'>Zoom per riempire</div>",
    "</div>",
    "</div>",
    "<div id='yt-controls'>",
    "<div class='progress-wrap' onclick='hud(\"Trasmissione in diretta\")'><div class='progress-bar'><div class='progress-dot'></div></div></div>",
    "<div class='bar-row'>",
    "<div class='left-btns'>",
    "<button class='yt-btn' id='btn-play' onclick='togglePause()' title='Pausa/Riprendi (Spazio)'><svg id='ico-play' viewBox='0 0 24 24'><path d='M6 19h4V5H6v14zm8-14v14h4V5h-4z'/></svg></button>",
    "<div class='vol-wrap'>",
    "<button class='yt-btn' id='btn-vol' onclick='toggleAudio()' title='Audio (M)'><svg id='ico-vol' viewBox='0 0 24 24'><path d='M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z'/></svg></button>",
    "<input type='range' id='vol-slider' min='0' max='1' step='0.05' value='1' oninput='setVolume(this.value)'>",
    "</div>",
    "<div class='live-pill'><span class='live-dot'></span> DAL VIVO</div>",
    "</div>",
    "<div class='right-btns'>",
    "<button class='yt-btn' onclick='snapshot()' title='Cattura schermata'><svg viewBox='0 0 24 24'><path d='M9 2L7.17 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2h-3.17L15 2H9zm3 15c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z'/></svg></button>",
    "<button class='yt-btn' onclick='rotateManual()' title='Ruota manualmente'><svg viewBox='0 0 24 24'><path d='M15.55 5.55L11 1v3.07C7.06 4.56 4 7.92 4 12s3.05 7.44 7 7.93v-2.02c-2.84-.48-5-2.94-5-5.91s2.16-5.43 5-5.91V10l4.55-4.45zM19.93 11c-.17-1.39-.72-2.73-1.62-3.89l-1.42 1.42c.54.75.88 1.6 1.02 2.47h2.02zM13 17.9v2.02c1.39-.17 2.74-.71 3.9-1.61l-1.44-1.44c-.75.54-1.59.89-2.46 1.03zm3.89-2.42l1.42 1.41c.9-1.16 1.45-2.5 1.62-3.89h-2.02c-.14.87-.48 1.72-1.02 2.48z'/></svg></button>",
    "<button class='yt-btn' onclick='toggleMenu()' title='Impostazioni'><svg viewBox='0 0 24 24'><path d='M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z'/></svg></button>",
    "<button class='yt-btn' onclick='togglePiP()' title='Miniplayer'><svg viewBox='0 0 24 24'><path d='M19 7h-8v6h8V7zm2-4H3c-1.1 0-2 .9-2 2v14c0 1.1.9 1.98 2 1.98h18c1.1 0 2-.88 2-1.98V5c0-1.1-.9-2-2-2zm0 16.01H3V4.98h18v14.03z'/></svg></button>",
    "<button class='yt-btn' onclick='toggleFullscreen()' title='Schermo intero (F)'><svg viewBox='0 0 24 24'><path d='M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z'/></svg></button>",
    "</div></div></div></div>",
    "<script>",
    "var ctx=null,gainNode=null,nextTime=0,audioRunning=false,audioAbort=null,paused=false,rotation=0,hideTimer=null,cinema=false;",
    "var icoPlay='<path d=\"M8 5v14l11-7z\"/>',icoPause='<path d=\"M6 19h4V5H6v14zm8-14v14h4V5h-4z\"/>';",
    "var icoMute='<path d=\"M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z\"/>';",
    "var icoVol='<path d=\"M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z\"/>';",
    "function hud(t){var h=document.getElementById('center-hud');h.textContent=t;h.classList.add('show');clearTimeout(h._t);h._t=setTimeout(function(){h.classList.remove('show')},1200)}",
    "function showControls(){var c=document.getElementById('yt-controls');c.classList.remove('hidden');document.body.style.cursor='default';clearTimeout(hideTimer);hideTimer=setTimeout(function(){if(!document.getElementById('yt-menu').classList.contains('open')&&!paused){c.classList.add('hidden');document.body.style.cursor='none'}},2800)}",
    "document.addEventListener('mousemove',showControls);document.addEventListener('touchstart',showControls);showControls();",
    "function toggleMenu(){var m=document.getElementById('yt-menu');m.classList.toggle('open');backMain()}",
    "function openSub(id){document.getElementById('menu-main').style.display='none';document.querySelectorAll('.submenu').forEach(function(s){s.classList.remove('active')});document.getElementById(id).classList.add('active')}",
    "function backMain(){document.querySelectorAll('.submenu').forEach(function(s){s.classList.remove('active')});document.getElementById('menu-main').style.display='flex'}",
    "function setRes(r,lbl){document.getElementById('val-res').textContent=lbl+' ▸';document.querySelectorAll('[data-res]').forEach(function(e){e.classList.toggle('selected',e.dataset.res==r)});fetch('/config?res='+r);backMain();toggleMenu();hud('Qualità: '+lbl)}",
    "function setFps(f){document.getElementById('val-fps').textContent=f+' FPS ▸';document.querySelectorAll('[data-fps]').forEach(function(e){e.classList.toggle('selected',e.dataset.fps==f)});fetch('/config?fps='+f);backMain();toggleMenu();hud(f+' FPS')}",
    "function setZoom(z,lbl){var v=document.getElementById('v');document.getElementById('val-zoom').textContent=lbl+' ▸';document.querySelectorAll('[data-zoom]').forEach(function(e){e.classList.toggle('selected',e.dataset.zoom==z)});if(z==='zoom')v.classList.add('zoom');else v.classList.remove('zoom');backMain();toggleMenu();hud(lbl)}",
    "function toggleFilter(){cinema=!cinema;var v=document.getElementById('v');v.style.filter=cinema?'contrast(1.08) saturate(1.12)':'none';document.getElementById('val-cin').textContent=cinema?'On':'Off';hud(cinema?'Modalità Cinema: On':'Modalità Cinema: Off')}",
    "function togglePause(){var v=document.getElementById('v'),ico=document.getElementById('ico-play');paused=!paused;if(paused){v.src='';ico.innerHTML=icoPlay;hud('In pausa')}else{v.src='/stream?t='+Date.now();ico.innerHTML=icoPause;hud('Dal vivo')}showControls()}",
    "function rotateManual(){rotation=(rotation+90)%360;var v=document.getElementById('v');if(rotation===90||rotation===270){v.style.width='100vh';v.style.height='100vw';v.style.transform='rotate('+rotation+'deg)'}else{v.style.width='100%';v.style.height='100%';v.style.transform='rotate('+rotation+'deg)'}hud('Rotazione: '+rotation+'°')}",
    "function toggleFullscreen(){if(!document.fullscreenElement)document.documentElement.requestFullscreen().catch(function(){});else document.exitFullscreen().catch(function(){})}",
    "function togglePiP(){window.open(location.href,'_blank','width=640,height=360')}",
    "function snapshot(){var v=document.getElementById('v'),c=document.createElement('canvas');c.width=v.naturalWidth||1280;c.height=v.naturalHeight||720;c.getContext('2d').drawImage(v,0,0);var a=document.createElement('a');a.download='MirrorTV_'+Date.now()+'.png';a.href=c.toDataURL();a.click();hud('Schermata salvata')}",
    "function setVolume(val){if(gainNode)gainNode.gain.value=val;document.getElementById('ico-vol').innerHTML=val==0?icoMute:icoVol}",
    "document.addEventListener('keydown',function(e){if(e.code==='Space'){e.preventDefault();togglePause()}else if(e.key==='f'||e.key==='F'){toggleFullscreen()}else if(e.key==='m'||e.key==='M'){toggleAudio()}});",
    "async function toggleAudio(){var ico=document.getElementById('ico-vol');if(audioRunning){audioRunning=false;if(audioAbort)audioAbort.abort();if(ctx){ctx.close();ctx=null}ico.innerHTML=icoMute;hud('Audio disattivato');return}audioRunning=true;ico.innerHTML=icoVol;hud('Audio attivo');audioAbort=new AbortController();try{ctx=new(window.AudioContext||window.webkitAudioContext)({sampleRate:48000});await ctx.resume();gainNode=ctx.createGain();gainNode.gain.value=document.getElementById('vol-slider').value;gainNode.connect(ctx.destination);var res=await fetch('/audio',{signal:audioAbort.signal}),rd=res.body.getReader(),left=new Uint8Array(0);while(audioRunning){var r=await rd.read();if(r.done)break;var buf=new Uint8Array(left.length+r.value.length);buf.set(left);buf.set(r.value,left.length);var u=buf.length-(buf.length%4);left=buf.slice(u);if(u===0)continue;var n=u/4,i16=new Int16Array(buf.buffer,0,u/2),ab=ctx.createBuffer(2,n,48000),L=ab.getChannelData(0),R=ab.getChannelData(1);for(var i=0;i<n;i++){L[i]=i16[2*i]/32768.0;R[i]=i16[2*i+1]/32768.0}var now=ctx.currentTime;if(nextTime<now+0.05)nextTime=now+0.15;if(nextTime>now+0.8)continue;var src=ctx.createBufferSource();src.buffer=ab;src.connect(gainNode);src.start(nextTime);nextTime+=ab.duration}}catch(e){if(audioRunning){audioRunning=false;ico.innerHTML=icoMute}}}",
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

            // Rileva automaticamente l'orientamento reale del video (es. rotazione telefono)
            if let orientationAttachment = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
               let orientation = CGImagePropertyOrientation(rawValue: orientationAttachment.uint32Value) {
                ciImage = ciImage.oriented(orientation)
            }

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
