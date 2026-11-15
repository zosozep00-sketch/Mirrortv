import ReplayKit
import CoreImage
import ImageIO
import AVFoundation
import Darwin

// Pagina mostrata dalla TV: video (MJPEG) + audio (PCM riprodotto con Web Audio)
private let pageHTML = #"""
<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Mirror TV</title>
<style>
html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden;font-family:Arial,Helvetica,sans-serif;-webkit-tap-highlight-color:transparent}
#v{position:absolute;left:50%;top:50%;width:100vw;height:100vh;object-fit:contain;display:block;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%)}
#msg{position:fixed;left:16px;top:16px;z-index:6;color:#fff;background:rgba(0,0,0,.65);padding:10px 16px;border-radius:10px;font-size:18px;display:none}
#bar{position:fixed;left:0;right:0;bottom:0;z-index:5;padding:10px 8px 14px;text-align:center;background:rgba(0,0,0,.65)}
.hidden{display:none !important}
.btn{display:inline-block;vertical-align:top;margin:4px;padding:10px 16px;min-width:96px;font-size:18px;line-height:1.15;color:#fff;background:#3a3a3c;border:3px solid #3a3a3c;border-radius:12px;cursor:pointer;outline:none;font-family:inherit}
.btn small{display:block;font-size:12px;opacity:.75}
.btn:hover,.btn:focus{border-color:#35a7ff;background:#14436b}
.btn.on{background:#2d7cff;border-color:#2d7cff}
.btn.on:hover,.btn.on:focus{border-color:#fff}
#show{position:fixed;left:12px;bottom:12px;z-index:5}
</style>
</head>
<body>
<img id="v" alt="">
<div id="msg"></div>
<div id="bar">
  <button type="button" class="btn" id="bPause" tabindex="0"></button>
  <button type="button" class="btn" id="bAudio" tabindex="0"></button>
  <button type="button" class="btn" id="bRot" tabindex="0"></button>
  <button type="button" class="btn" id="bFull" tabindex="0"></button>
  <button type="button" class="btn" id="bFit" tabindex="0"></button>
  <button type="button" class="btn" id="bQ1" tabindex="0"></button>
  <button type="button" class="btn" id="bQ2" tabindex="0"></button>
  <button type="button" class="btn" id="bQ3" tabindex="0"></button>
  <button type="button" class="btn" id="bMode" tabindex="0"></button>
  <button type="button" class="btn" id="bHide" tabindex="0"></button>
</div>
<button type="button" class="btn hidden" id="show" tabindex="0"></button>
<script>
(function () {
  function $(id) { return document.getElementById(id); }
  var img = $('v'), bar = $('bar'), msgEl = $('msg'), showBtn = $('show');
  var bPause = $('bPause'), bAudio = $('bAudio'), bRot = $('bRot'), bFull = $('bFull'), bFit = $('bFit');
  var bQ1 = $('bQ1'), bQ2 = $('bQ2'), bQ3 = $('bQ3'), bMode = $('bMode'), bHide = $('bHide');
  var btns = [bPause, bAudio, bRot, bFull, bFit, bQ1, bQ2, bQ3, bMode, bHide];

  var st = { fit: 'contain', rot: 0, full: false, land: false, paused: false, res: '1280' };
  var ctx = null, nextTime = 0, audioStarted = false, muted = false;
  var pollMode = false, hideTimer = null, barShown = true, msgTimer = null;

  function now() { return new Date().getTime(); }

  function hasClass(el, c) { return (' ' + el.className + ' ').indexOf(' ' + c + ' ') >= 0; }
  function toggleClass(el, c, on) {
    var has = hasClass(el, c);
    if (on && !has) { el.className = el.className + ' ' + c; }
    if (!on && has) { el.className = (' ' + el.className + ' ').replace(' ' + c + ' ', ' ').replace(/^\s+|\s+$/g, ''); }
  }
  function setLabel(btn, it, en) { btn.innerHTML = it + '<small>' + en + '</small>'; }

  function toast(text, ms) {
    msgEl.textContent = text;
    msgEl.style.display = 'block';
    if (msgTimer) { clearTimeout(msgTimer); }
    msgTimer = setTimeout(function () { msgEl.style.display = 'none'; }, ms || 4000);
  }

  function control(q) {
    try {
      var x = new XMLHttpRequest();
      x.open('GET', '/control?' + q + '&t=' + now(), true);
      x.send(null);
    } catch (e) {}
  }

  // ---------- Aspetto: rotazione, adatta/zoom, riempi schermo ----------
  function layout() {
    var swap = (st.rot === 90 || st.rot === 270);
    img.style.width = swap ? '100vh' : '100vw';
    img.style.height = swap ? '100vw' : '100vh';
    img.style.objectFit = (st.full || st.land) ? 'cover' : 'contain';
    var zoom = (st.fit === 'zoom') ? 1.18 : 1;
    var t = 'translate(-50%,-50%) rotate(' + st.rot + 'deg) scale(' + zoom + ')';
    img.style.webkitTransform = t;
    img.style.msTransform = t;
    img.style.transform = t;
  }

  function refreshLabels() {
    var audioOn = audioStarted && !muted;
    setLabel(bPause, st.paused ? 'Riprendi' : 'Pausa', st.paused ? 'Resume' : 'Pause');
    setLabel(bAudio, audioOn ? 'Audio attivo' : 'Attiva audio', audioOn ? 'Audio on' : 'Enable audio');
    setLabel(bRot, 'Ruota ' + st.rot + '&deg;', 'Rotate');
    setLabel(bFull, st.full ? 'Esci da intero' : 'Schermo intero', st.full ? 'Exit full' : 'Fullscreen');
    setLabel(bFit, st.fit === 'zoom' ? 'Adatta' : 'Zoom', st.fit === 'zoom' ? 'Fit' : 'Zoom');
    setLabel(bQ1, 'Veloce', 'Fast');
    setLabel(bQ2, 'Normale', 'Normal');
    setLabel(bQ3, 'Alta', 'High');
    setLabel(bMode, pollMode ? 'Flusso video' : 'Compatibile', pollMode ? 'Video stream' : 'Compatible');
    setLabel(bHide, 'Nascondi', 'Hide');
    setLabel(showBtn, 'Comandi', 'Controls');
    toggleClass(bPause, 'on', st.paused);
    toggleClass(bAudio, 'on', audioOn);
    toggleClass(bFull, 'on', st.full);
    toggleClass(bFit, 'on', st.fit === 'zoom');
    toggleClass(bQ1, 'on', st.res === '640');
    toggleClass(bQ2, 'on', st.res === '1280');
    toggleClass(bQ3, 'on', st.res === '1920');
    toggleClass(bMode, 'on', pollMode);
  }

  // ---------- Schermo intero del browser ----------
  function inFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement ||
              document.mozFullScreenElement || document.msFullscreenElement);
  }
  function tryFullscreen() {
    try {
      if (inFullscreen()) { return; }
      var e = document.documentElement;
      var f = e.requestFullscreen || e.webkitRequestFullscreen || e.mozRequestFullScreen || e.msRequestFullscreen;
      if (f) {
        var p = f.call(e);
        if (p && p['catch']) { p['catch'](function () {}); }
      }
    } catch (err) {}
  }
  function exitFullscreen() {
    try {
      var f = document.exitFullscreen || document.webkitExitFullscreen || document.mozCancelFullScreen || document.msExitFullscreen;
      if (f && inFullscreen()) { f.call(document); }
    } catch (err) {}
  }

  // ---------- Audio (solo se il browser lo supporta) ----------
  function playChunk(buf, usable) {
    var n = usable / 4;
    var i16 = new Int16Array(buf.buffer, buf.byteOffset, usable / 2);
    var ab = ctx.createBuffer(2, n, 48000);
    var L = ab.getChannelData(0), R = ab.getChannelData(1);
    for (var i = 0; i < n; i++) {
      L[i] = i16[2 * i] / 32768;
      R[i] = i16[2 * i + 1] / 32768;
    }
    var t = ctx.currentTime;
    if (nextTime < t + 0.05) { nextTime = t + 0.15; }
    if (nextTime > t + 0.8) { return; }
    var src = ctx.createBufferSource();
    src.buffer = ab;
    src.connect(ctx.destination);
    if (src.start) { src.start(nextTime); } else { src.noteOn(nextTime); }
    nextTime += ab.duration;
  }

  function startAudio() {
    if (audioStarted) { return; }
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC || !window.fetch || typeof Uint8Array === 'undefined' || typeof Int16Array === 'undefined') {
      toast('Audio non supportato da questo browser / Audio not supported', 6000);
      return;
    }
    try {
      ctx = new AC();
      if (ctx.resume) { ctx.resume(); }
    } catch (e) {
      toast('Audio non disponibile / Audio unavailable', 5000);
      return;
    }
    audioStarted = true;
    muted = false;
    nextTime = 0;
    control('audio=1');
    var left = new Uint8Array(0);
    fetch('/audio').then(function (res) {
      if (!res.body || !res.body.getReader) { throw new Error('nostream'); }
      var reader = res.body.getReader();
      function pump() {
        return reader.read().then(function (r) {
          if (r.done) { audioStarted = false; refreshLabels(); return; }
          var chunk = r.value;
          var buf = new Uint8Array(left.length + chunk.length);
          buf.set(left, 0);
          buf.set(chunk, left.length);
          var usable = buf.length - (buf.length % 4);
          left = buf.subarray(usable);
          if (usable > 0 && !muted) { playChunk(buf, usable); }
          return pump();
        });
      }
      return pump();
    })['catch'](function () {
      audioStarted = false;
      refreshLabels();
      toast('Audio non supportato da questo browser / Audio not supported', 6000);
    });
    refreshLabels();
  }

  function toggleAudio() {
    if (!audioStarted) { startAudio(); return; }
    muted = !muted;
    control('audio=' + (muted ? 0 : 1));
    refreshLabels();
  }

  // ---------- Video: flusso continuo oppure modalità compatibile ----------
  function startStream() {
    pollMode = false;
    img.onload = null;
    img.onerror = null;
    img.src = '/stream?t=' + now();
    setTimeout(function () {
      if (!pollMode && !img.naturalWidth) {
        toast('Passo alla modalità compatibile / Switching to compatible mode', 4000);
        startPolling();
      }
    }, 8000);
  }
  function pollOnce() {
    if (!pollMode) { return; }
    img.onload = function () { if (pollMode) { setTimeout(pollOnce, 60); } };
    img.onerror = function () { if (pollMode) { setTimeout(pollOnce, 500); } };
    img.src = '/frame.jpg?t=' + now();
  }
  function startPolling() {
    pollMode = true;
    refreshLabels();
    pollOnce();
  }

  // ---------- Barra dei comandi ----------
  function armHide() {
    if (hideTimer) { clearTimeout(hideTimer); }
    hideTimer = setTimeout(hideBar, 10000);
  }
  function showBar() {
    barShown = true;
    bar.className = '';
    showBtn.className = 'btn hidden';
    armHide();
  }
  function hideBar() {
    barShown = false;
    bar.className = 'hidden';
    showBtn.className = 'btn';
    if (hideTimer) { clearTimeout(hideTimer); }
    try { showBtn.focus(); } catch (e) {}
  }
  function focusFirst() { try { btns[0].focus(); } catch (e) {} }
  function moveFocus(k) {
    var cur = -1, i, next;
    for (i = 0; i < btns.length; i++) {
      if (btns[i] === document.activeElement) { cur = i; break; }
    }
    if (cur < 0) { next = 0; }
    else if (k === 37 || k === 38) { next = (cur - 1 + btns.length) % btns.length; }
    else { next = (cur + 1) % btns.length; }
    try { btns[next].focus(); } catch (e) {}
  }
  function activity() {
    if (!barShown) { showBar(); } else { armHide(); }
  }

  // ---------- Azioni dei pulsanti ----------
  function doPause() {
    st.paused = !st.paused;
    control('paused=' + (st.paused ? 1 : 0));
    refreshLabels();
  }
  function doRotate() {
    st.rot = (st.rot + 90) % 360;
    layout();
    refreshLabels();
    control('rot=' + st.rot);
  }
  function doFull() {
    st.full = !st.full;
    layout();
    refreshLabels();
    control('full=' + (st.full ? 1 : 0));
    if (st.full) { tryFullscreen(); } else { exitFullscreen(); }
  }
  function doFit() {
    st.fit = (st.fit === 'zoom') ? 'contain' : 'zoom';
    layout();
    refreshLabels();
    control('fit=' + st.fit);
  }
  function doQuality(res, fps) {
    st.res = String(res);
    refreshLabels();
    control('res=' + res + '&fps=' + fps);
  }
  function doMode() {
    if (pollMode) { startStream(); refreshLabels(); } else { startPolling(); }
  }

  bPause.addEventListener('click', doPause, false);
  bAudio.addEventListener('click', toggleAudio, false);
  bRot.addEventListener('click', doRotate, false);
  bFull.addEventListener('click', doFull, false);
  bFit.addEventListener('click', doFit, false);
  bQ1.addEventListener('click', function () { doQuality(640, 25); }, false);
  bQ2.addEventListener('click', function () { doQuality(1280, 15); }, false);
  bQ3.addEventListener('click', function () { doQuality(1920, 12); }, false);
  bMode.addEventListener('click', doMode, false);
  bHide.addEventListener('click', hideBar, false);
  showBtn.addEventListener('click', function () { showBar(); focusFirst(); }, false);
  img.addEventListener('click', function () { if (!audioStarted) { startAudio(); } activity(); }, false);
  document.addEventListener('mousemove', activity, false);
  document.addEventListener('touchstart', activity, false);

  // Telecomando della TV: frecce per spostarsi, OK per premere, Indietro per nascondere
  document.addEventListener('keydown', function (e) {
    var k = e.keyCode || e.which;
    if (!barShown) {
      showBar();
      focusFirst();
      if (e.preventDefault) { e.preventDefault(); }
      return;
    }
    armHide();
    if (k === 37 || k === 38 || k === 39 || k === 40) {
      moveFocus(k);
      if (e.preventDefault) { e.preventDefault(); }
    } else if (k === 13 || k === 32) {
      var onButton = false, i;
      for (i = 0; i < btns.length; i++) { if (btns[i] === document.activeElement) { onButton = true; } }
      if (!onButton) { focusFirst(); if (e.preventDefault) { e.preventDefault(); } }
    } else if (k === 415 || k === 19 || k === 10252 || k === 179) {
      doPause();
    } else if (k === 10009 || k === 27 || k === 461) {
      hideBar();
    }
  }, false);

  // ---------- Stato dal telefono ----------
  function applyState(s) {
    var wasBig = st.full || st.land;
    var changed = (s.fit !== st.fit) || (s.rot !== st.rot) || (s.full !== st.full) ||
                  (s.land !== st.land) || (s.paused !== st.paused) || (String(s.res) !== st.res);
    st.fit = s.fit; st.rot = s.rot; st.full = s.full; st.land = s.land;
    st.paused = s.paused; st.res = String(s.res);
    if (changed) { layout(); refreshLabels(); }
    if ((st.full || st.land) && !wasBig) { tryFullscreen(); }
  }
  function poll() {
    try {
      var x = new XMLHttpRequest();
      x.open('GET', '/state?t=' + now(), true);
      x.onreadystatechange = function () {
        if (x.readyState !== 4 || x.status !== 200) { return; }
        try { applyState(JSON.parse(x.responseText)); } catch (err) {}
      };
      x.send(null);
    } catch (e) {}
  }

  layout();
  refreshLabels();
  startStream();
  showBar();
  poll();
  setInterval(poll, 1000);
  toast('Premi OK per i comandi / Press OK for controls', 5000);
})();
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
    private let audioQueue = DispatchQueue(label: "mirrortv.audio")

    // Ultimo fotogramma (per la modalità compatibile) e ultima richiesta di un browser in modalità compatibile
    private var latestJPEG: Data?
    private var lastPoll: CFAbsoluteTime = 0

    // Stato del telecomando (protetto da un blocco separato)
    private let stateLock = NSLock()
    private var resValue = "1280"
    private var fpsValue = "15"
    private var speedValue = "1.0"
    private var fitValue = "contain"
    private var rotValue = 0
    private var audioOn = true
    private var pausedValue = false
    private var fullValue = false
    private var landValue = false

    func setLandscape(_ value: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        landValue = value
    }

    var maxSide: CGFloat {
        stateLock.lock(); defer { stateLock.unlock() }
        return CGFloat(min(Int(resValue) ?? 1280, 1920))
    }

    var minInterval: Double {
        stateLock.lock(); defer { stateLock.unlock() }
        let f = Double(Int(fpsValue) ?? 15)
        return 1.0 / max(1.0, min(f, 30.0))
    }

    var isPaused: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return pausedValue
    }

    var isAudioOn: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return audioOn
    }

    private func applyControl(_ path: String) {
        guard let query = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return }
        stateLock.lock()
        defer { stateLock.unlock() }
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let key = kv[0]
            let value = kv[1]
            switch key {
            case "res": if Int(value) != nil { resValue = value }
            case "fps": if Int(value) != nil { fpsValue = value }
            case "speed": if Double(value) != nil { speedValue = value }
            case "fit": if value == "contain" || value == "zoom" { fitValue = value }
            case "rot": if let r = Int(value) { rotValue = ((r % 360) + 360) % 360 }
            case "audio": audioOn = (value == "1")
            case "paused": pausedValue = (value == "1")
            case "full": fullValue = (value == "1")
            default: break
            }
        }
    }

    private func stateJSON() -> String {
        stateLock.lock(); defer { stateLock.unlock() }
        return "{\"res\":\"\(resValue)\",\"fps\":\"\(fpsValue)\",\"speed\":\"\(speedValue)\",\"fit\":\"\(fitValue)\",\"rot\":\(rotValue),\"audio\":\(audioOn),\"paused\":\(pausedValue),\"full\":\(fullValue),\"land\":\(landValue)}"
    }

    private func respond(_ client: Int32, contentType: String, body: String) {
        let data = Data(body.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        _ = sendAll(client, Data(head.utf8) + data)
        close(client)
    }

    var hasClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty
    }

    // Vero se qualcuno guarda il flusso, oppure un browser in modalità compatibile ha chiesto un fotogramma da poco
    var wantsFrames: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty || (CFAbsoluteTimeGetCurrent() - lastPoll) < 3.0
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
                // Mando subito l'ultimo fotogramma, così lo schermo non resta nero se l'immagine è ferma
                lock.lock(); let first = latestJPEG; lock.unlock()
                if let first = first {
                    var packet = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(first.count)\r\n\r\n".utf8)
                    packet.append(first)
                    packet.append(Data("\r\n".utf8))
                    _ = sendAll(client, packet)
                }
                lock.lock(); clients.append(client); lock.unlock()
            } else {
                close(client)
            }
        } else if path.hasPrefix("/state") {
            respond(client, contentType: "application/json", body: stateJSON())
        } else if path.hasPrefix("/control") {
            applyControl(path)
            respond(client, contentType: "text/plain", body: "ok")
        } else if path.hasPrefix("/frame") {
            lock.lock()
            lastPoll = CFAbsoluteTimeGetCurrent()
            let jpeg = latestJPEG
            lock.unlock()
            respondData(client, contentType: "image/jpeg", data: jpeg)
        } else if path.hasPrefix("/favicon") {
            respondData(client, contentType: "image/x-icon", data: nil)
        } else if path.hasPrefix("/audio") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            if sendAll(client, Data(head.utf8)) {
                lock.lock(); audioClients.append(client); lock.unlock()
            } else {
                close(client)
            }
        } else {
            let body = Data(pageHTML.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8) + body)
            close(client)
        }
    }

    private func respondData(_ client: Int32, contentType: String, data: Data?) {
        guard let data = data, !data.isEmpty else {
            let head = "HTTP/1.1 204 No Content\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            _ = sendAll(client, Data(head.utf8))
            close(client)
            return
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        _ = sendAll(client, Data(head.utf8) + data)
        close(client)
    }

    func broadcast(_ jpeg: Data) {
        lock.lock()
        latestJPEG = jpeg
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
    private let ciContext = CIContext()
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
        guard server.wantsFrames, !server.isPaused else { return }

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

        // Se il telefono è in orizzontale, la TV riempie lo schermo da sola
        server.setLandscape(image.extent.width > image.extent.height)

        let longest = max(image.extent.width, image.extent.height)
        let scale = min(1.0, server.maxSide / longest)
        if scale < 1.0 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5
        ]
        if let jpeg = ciContext.jpegRepresentation(of: image,
                                                   colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                   options: options) {
            server.broadcast(jpeg)
        }
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard server.hasAudioClients, server.isAudioOn,
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
