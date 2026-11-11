import SwiftUI
import ReplayKit
import Network
import WebKit
import AVKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Rete

func localIPAddress() -> String? {
    var found: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let iface = p.pointee
        if let sa = iface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: iface.ifa_name)
            if name == "en0" || name == "bridge100" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(iface.ifa_addr, socklen_t(sa.pointee.sa_len),
                            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                found = String(cString: host)
                if name == "en0" { break }
            }
        }
        ptr = iface.ifa_next
    }
    return found
}

class LocalNetworkTrigger: ObservableObject {
    private var browser: NWBrowser?

    func trigger() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
        self.browser = browser
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { browser.cancel() }
    }
}

// MARK: - Componenti grafici

struct NeonLogoView: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                    .frame(width: compact ? 48 : 76, height: compact ? 48 : 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.29, blue: 0.17)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: compact ? 2 : 3
                            )
                    )
                    .shadow(color: Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.45), radius: compact ? 6 : 10)

                Image(systemName: "play.tv.fill")
                    .font(.system(size: compact ? 22 : 36, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.29, blue: 0.17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            if !compact {
                VStack(spacing: 1) {
                    Text("MirrorTV")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("by Zoso")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.85, blue: 0.95), Color(red: 1.0, green: 0.29, blue: 0.17)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
    }
}

struct BilingualLabel: View {
    let it: String
    let en: String
    var font: Font = .subheadline
    var color: Color = .primary
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(it).font(font).foregroundColor(color)
            Text(en).font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    var size: CGFloat = 78

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        picker.preferredExtension = "com.example.mirrortvb.ext"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - Telecomando

class RemoteControlManager: ObservableObject {
    @Published var isBroadcasting = false
    @Published var isMinimized = false
    @Published var isConnected = false
    @Published var resolution = "1280"
    @Published var fps = "30"
    @Published var speed = "1.0"
    @Published var fitMode = "contain"
    @Published var rotation = 0
    @Published var audioActive = false
    @Published var isPaused = false

    private var timer: Timer?

    private var baseURL: String {
        let host = localIPAddress() ?? "127.0.0.1"
        return "http://\(host):8080"
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBroadcastStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkBroadcastStatus() {
        let active = UIScreen.main.isCaptured
        DispatchQueue.main.async {
            if self.isBroadcasting != active {
                self.isBroadcasting = active
                if !active { self.isMinimized = false }
            }
        }
        if active { fetchState() }
    }

    func sendCommand(_ query: String) {
        guard let url = URL(string: "\(baseURL)/control?\(query)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            DispatchQueue.main.async {
                self?.isConnected = (resp as? HTTPURLResponse)?.statusCode == 200
            }
        }.resume()
    }

    func fetchState() {
        guard let url = URL(string: "\(baseURL)/state") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { self?.isConnected = ok }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let res = json["res"] as? String { self?.resolution = res }
                if let fps = json["fps"] as? String { self?.fps = fps }
                if let spd = json["speed"] as? String { self?.speed = spd }
                if let fit = json["fit"] as? String { self?.fitMode = fit }
                if let rot = json["rot"] as? Int { self?.rotation = rot }
                if let aud = json["audio"] as? Bool { self?.audioActive = aud }
                if let pau = json["paused"] as? Bool { self?.isPaused = pau }
            }
        }.resume()
    }
}

struct MiniRemoteBar: View {
    @ObservedObject var remote: RemoteControlManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    remote.isMinimized = false
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(remote.isConnected ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Telecomando Live")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Text("Tocca per ingrandire / Tap to expand")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                remote.isPaused.toggle()
                remote.sendCommand("paused=\(remote.isPaused ? 1 : 0)")
            } label: {
                Image(systemName: remote.isPaused ? "play.fill" : "pause.fill")
                    .font(.body.bold())
                    .frame(width: 34, height: 34)
                    .background(remote.isPaused ? Color.orange.opacity(0.25) : Color(.systemGray5))
                    .clipShape(Circle())
            }

            Button {
                remote.audioActive.toggle()
                remote.sendCommand("audio=\(remote.audioActive ? 1 : 0)")
            } label: {
                Image(systemName: remote.audioActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.body.bold())
                    .frame(width: 34, height: 34)
                    .background(remote.audioActive ? Color.blue.opacity(0.25) : Color(.systemGray5))
                    .clipShape(Circle())
            }

            Button {
                remote.rotation = (remote.rotation + 90) % 360
                remote.sendCommand("rot=\(remote.rotation)")
            } label: {
                Image(systemName: "rotate.right.fill")
                    .font(.body.bold())
                    .frame(width: 34, height: 34)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
}

struct ResolutionOption: Identifiable {
    let label: String
    let val: String
    var id: String { val }
}

struct RemoteControlView: View {
    @ObservedObject var remote: RemoteControlManager
    let ipAddress: String

    let resolutions: [ResolutionOption] = [
        ResolutionOption(label: "4K (2160p)", val: "3840"),
        ResolutionOption(label: "2K (1440p)", val: "2560"),
        ResolutionOption(label: "1080p Full HD", val: "1920"),
        ResolutionOption(label: "720p HD", val: "1280"),
        ResolutionOption(label: "480p SD", val: "854"),
        ResolutionOption(label: "360p", val: "640"),
        ResolutionOption(label: "240p", val: "426")
    ]
    let fpsOptions = ["60", "50", "30", "25", "15", "10"]
    let speedOptions = ["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "2.0"]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    commandGrid
                    settingsBox
                    minimizeButton
                    stopButton
                }
                .padding(.vertical)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    remote.isMinimized = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.headline.bold())
                    Text("Riduci")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.systemGray5))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            NeonLogoView(compact: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(remote.isConnected ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(remote.isConnected ? "CONNESSO" : "LIVE")
                        .font(.subheadline).bold()
                }
                Text(ipAddress)
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var commandGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button {
                remote.isPaused.toggle()
                remote.sendCommand("paused=\(remote.isPaused ? 1 : 0)")
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: remote.isPaused ? "play.fill" : "pause.fill").font(.title2)
                    BilingualLabel(it: remote.isPaused ? "Riprendi" : "Pausa",
                                   en: remote.isPaused ? "Resume" : "Pause",
                                   font: .callout.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(remote.isPaused ? Color.orange.opacity(0.25) : Color(.systemGray6)).cornerRadius(14)
            }

            Button {
                remote.audioActive.toggle()
                remote.sendCommand("audio=\(remote.audioActive ? 1 : 0)")
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: remote.audioActive ? "speaker.wave.3.fill" : "speaker.slash.fill").font(.title2)
                    BilingualLabel(it: remote.audioActive ? "Audio Attivo" : "Attiva Audio",
                                   en: remote.audioActive ? "Audio On" : "Enable Audio",
                                   font: .callout.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(remote.audioActive ? Color.blue.opacity(0.25) : Color(.systemGray6)).cornerRadius(14)
            }

            Button {
                remote.rotation = (remote.rotation + 90) % 360
                remote.sendCommand("rot=\(remote.rotation)")
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.right.fill").font(.title2)
                    BilingualLabel(it: "Ruota (\(remote.rotation)°)", en: "Rotate Screen", font: .callout.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color(.systemGray6)).cornerRadius(14)
            }

            Button {
                remote.fitMode = (remote.fitMode == "contain") ? "zoom" : "contain"
                remote.sendCommand("fit=\(remote.fitMode)")
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: remote.fitMode == "zoom" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.title2)
                    BilingualLabel(it: remote.fitMode == "zoom" ? "Zoom 118%" : "Adatta Intero",
                                   en: remote.fitMode == "zoom" ? "Zoomed" : "Fit Screen",
                                   font: .callout.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(remote.fitMode == "zoom" ? Color.purple.opacity(0.25) : Color(.systemGray6)).cornerRadius(14)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var settingsBox: some View {
        VStack(spacing: 12) {
            HStack {
                BilingualLabel(it: "Risoluzione Video", en: "Video Resolution", font: .subheadline.bold(), alignment: .leading)
                Spacer()
                Picker("Risoluzione", selection: $remote.resolution) {
                    ForEach(resolutions) { option in
                        Text(option.label).tag(option.val)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: remote.resolution) { newValue in
                    remote.sendCommand("res=\(newValue)")
                }
            }
            Divider()
            HStack {
                BilingualLabel(it: "Fluidità (FPS)", en: "Frame Rate", font: .subheadline.bold(), alignment: .leading)
                Spacer()
                Picker("FPS", selection: $remote.fps) {
                    ForEach(fpsOptions, id: \.self) { value in
                        Text("\(value) FPS").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: remote.fps) { newValue in
                    remote.sendCommand("fps=\(newValue)")
                }
            }
            Divider()
            HStack {
                BilingualLabel(it: "Velocità Flusso", en: "Playback Speed", font: .subheadline.bold(), alignment: .leading)
                Spacer()
                Picker("Velocità", selection: $remote.speed) {
                    ForEach(speedOptions, id: \.self) { value in
                        Text("\(value)x").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: remote.speed) { newValue in
                    remote.sendCommand("speed=\(newValue)")
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var minimizeButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                remote.isMinimized = true
            }
        } label: {
            HStack {
                Image(systemName: "pip.enter")
                BilingualLabel(it: "Riduci a mini-barra (Usa Browser / App)",
                               en: "Minimize to mini-bar (Use Browser / Apps)",
                               font: .subheadline.bold(), color: .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(14)
            .padding(.horizontal)
        }
    }

    private var stopButton: some View {
        VStack(spacing: 6) {
            BroadcastPicker(size: 72)
                .frame(width: 72, height: 72)
                .background(Color.red.opacity(0.15))
                .cornerRadius(18)
            BilingualLabel(it: "Tocca per interrompere la trasmissione",
                           en: "Tap to stop broadcasting",
                           font: .caption, color: .secondary)
        }
    }
}

// MARK: - Schermata principale (Schermo)

struct HomeMirrorView: View {
    @Binding var ip: String?
    @State private var copied = false

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                NeonLogoView(compact: false).padding(.top, 8)

                VStack(spacing: 8) {
                    BilingualLabel(it: "1. Tocca l'icona di trasmissione qui sotto", en: "1. Tap the broadcast icon below")
                    BilingualLabel(it: "2. Scegli 'Mirror TV' e premi 'Avvia trasmissione'", en: "2. Choose 'Mirror TV' and tap 'Start Broadcast'")
                    BilingualLabel(it: "3. Sulla TV o PC apri questo indirizzo nel browser:", en: "3. Open this address in your TV or PC browser:")
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                BroadcastPicker()
                    .frame(width: 78, height: 78)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)

                Text(urlString)
                    .font(.system(.title3, design: .monospaced)).bold()
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                HStack(spacing: 14) {
                    Button {
                        UIPasteboard.general.string = urlString
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        BilingualLabel(it: copied ? "Copiato!" : "Copia indirizzo",
                                       en: copied ? "Copied!" : "Copy address",
                                       font: .subheadline.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        ip = localIPAddress()
                    } label: {
                        BilingualLabel(it: "Aggiorna IP", en: "Refresh IP", font: .subheadline.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                }

                BilingualLabel(
                    it: "Usa le schede in basso per Browser, Musica, Galleria e IPTV.",
                    en: "Use the bottom tabs for Browser, Music, Gallery and IPTV.",
                    font: .footnote, color: .secondary
                )
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }
            .padding()
        }
    }
}

// MARK: - Browser

struct SafariWebView: UIViewRepresentable {
    let urlString: String
    @Binding var detectedVideoURL: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.lastLoaded = urlString
        load(urlString, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoaded != urlString {
            context.coordinator.lastLoaded = urlString
            load(urlString, in: webView)
        }
    }

    private func load(_ text: String, in webView: WKWebView) {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http") {
            if str.contains(".") && !str.contains(" ") {
                str = "https://" + str
            } else {
                let q = str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
                str = "https://www.google.com/search?q=" + q
            }
        }
        if let url = URL(string: str) { webView.load(URLRequest(url: url)) }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SafariWebView
        var lastLoaded = ""

        init(_ parent: SafariWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "Array.from(document.querySelectorAll('video, source')).map(v => v.src || v.currentSrc).find(s => s && s.startsWith('http'))"
            webView.evaluateJavaScript(js) { res, _ in
                if let videoSrc = res as? String, !videoSrc.isEmpty {
                    DispatchQueue.main.async { self.parent.detectedVideoURL = videoSrc }
                }
            }
        }
    }
}

struct WebBrowserCastView: View {
    @State private var inputURL = "youtube.com"
    @State private var activeURL = "youtube.com"
    @State private var detectedVideoURL: String? = nil
    @State private var showFullPlayer = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Inserisci URL o cerca video / Enter URL or search", text: $inputURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit { activeURL = inputURL }
                Button { activeURL = inputURL } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.title2)
                }
            }
            .padding(.horizontal).padding(.top, 8)

            HStack {
                BilingualLabel(it: "Naviga e guarda a schermo intero sulla TV",
                               en: "Browse and watch fullscreen on TV",
                               font: .caption, alignment: .leading)
                Spacer()
                BroadcastPicker(size: 44)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if detectedVideoURL != nil {
                Button { showFullPlayer = true } label: {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                        BilingualLabel(it: "Video rilevato! Apri nel Player",
                                       en: "Video detected! Open in Player",
                                       font: .caption.bold(), color: .white, alignment: .leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }

            SafariWebView(urlString: activeURL, detectedVideoURL: $detectedVideoURL)
        }
        .sheet(isPresented: $showFullPlayer) {
            if let vid = detectedVideoURL, let u = URL(string: vid) {
                UniversalVideoPlayerSheet(url: u, title: "Web Video Cast")
            }
        }
    }
}

// MARK: - Musica

struct MusicPlayerView: View {
    @State private var tracks: [URL] = []
    @State private var currentIndex: Int = 0
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var showFileImporter = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var currentTrackName: String {
        guard !tracks.isEmpty, tracks.indices.contains(currentIndex) else { return "Nessun brano selezionato" }
        return tracks[currentIndex].deletingPathExtension().lastPathComponent
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    BilingualLabel(it: "Musica & Audio Cast", en: "Music & Audio Player", font: .title3.bold(), alignment: .leading)
                    Spacer()
                    BroadcastPicker(size: 46)
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [Color.green.opacity(0.8), Color.black],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 210, height: 210)
                        .shadow(color: Color.green.opacity(0.35), radius: 15)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 76))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text(currentTrackName).font(.headline).lineLimit(1).padding(.horizontal)
                    Text(tracks.isEmpty ? "Carica file audio o apri Spotify / Load audio or open Spotify" : "In riproduzione / Now Playing")
                        .font(.caption).foregroundColor(.secondary)
                }

                Slider(value: $progress, in: 0...max(duration, 1), onEditingChanged: { editing in
                    if !editing { player?.currentTime = progress }
                })
                .accentColor(.green)
                .padding(.horizontal)

                HStack(spacing: 34) {
                    Button { prevTrack() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { togglePlay() } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 62))
                            .foregroundColor(.green)
                    }
                    Button { nextTrack() } label: { Image(systemName: "forward.fill").font(.title) }
                }
                .foregroundColor(.primary)

                HStack(spacing: 12) {
                    Button { showFileImporter = true } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            BilingualLabel(it: "Carica da File", en: "Load from Files", font: .caption.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(12)
                    }
                    Button {
                        if let url = URL(string: "spotify://"), UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else if let web = URL(string: "https://spotify.com") {
                            UIApplication.shared.open(web)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "waveform")
                            BilingualLabel(it: "Apri Spotify", en: "Open Spotify", font: .caption.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.green).foregroundColor(.white).cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        BilingualLabel(it: "Playlist Brani", en: "Tracklist", font: .subheadline.bold(), alignment: .leading)
                        ForEach(tracks.indices, id: \.self) { idx in
                            Button {
                                currentIndex = idx
                                playTrack(at: idx)
                            } label: {
                                HStack {
                                    Image(systemName: idx == currentIndex && isPlaying ? "speaker.wave.2.fill" : "music.note")
                                        .foregroundColor(.green)
                                    Text(tracks[idx].lastPathComponent).lineLimit(1).font(.subheadline)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let wasEmpty = tracks.isEmpty
                for u in urls { _ = u.startAccessingSecurityScopedResource() }
                tracks.append(contentsOf: urls)
                if wasEmpty {
                    currentIndex = 0
                    playTrack(at: 0)
                }
            }
        }
        .onReceive(timer) { _ in
            if let p = player, p.isPlaying {
                progress = p.currentTime
                duration = p.duration
            }
        }
    }

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: tracks[index])
            player?.play()
            isPlaying = true
            duration = player?.duration ?? 1
        } catch {
            isPlaying = false
        }
    }

    func togglePlay() {
        guard let p = player else {
            if !tracks.isEmpty { playTrack(at: currentIndex) }
            return
        }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func nextTrack() {
        guard !tracks.isEmpty else { return }
        currentIndex = (currentIndex + 1) % tracks.count
        playTrack(at: currentIndex)
    }

    func prevTrack() {
        guard !tracks.isEmpty else { return }
        currentIndex = (currentIndex - 1 + tracks.count) % tracks.count
        playTrack(at: currentIndex)
    }
}

// MARK: - Galleria

struct GalleryMediaCastView: View {
    @State private var selectedVideoURL: URL?
    @State private var selectedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showPlayerSheet = false

    // Aspetta che il selettore si sia chiuso prima di aprire il player
    private func presentPlayerSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showPlayerSheet = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    BilingualLabel(it: "Galleria & File Player", en: "Gallery & File Cast", font: .title3.bold(), alignment: .leading)
                    Spacer()
                    BroadcastPicker(size: 46)
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Image(systemName: "play.square.stack.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)

                BilingualLabel(
                    it: "Proietta foto e video in tutti i formati dalla Galleria o da File",
                    en: "Cast photos and videos in all formats from Gallery or Files",
                    font: .subheadline
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                HStack(spacing: 14) {
                    Button { showPhotoPicker = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled").font(.title)
                            BilingualLabel(it: "Apri Galleria", en: "Open Gallery", font: .subheadline.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.red).foregroundColor(.white).cornerRadius(16)
                    }
                    Button { showFileImporter = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.fill").font(.title)
                            BilingualLabel(it: "Apri da File", en: "Open Files", font: .subheadline.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(16)
                    }
                }
                .padding(.horizontal)

                if let img = selectedImage {
                    VStack(spacing: 8) {
                        BilingualLabel(it: "Anteprima Immagine (Tocca per schermo intero)",
                                       en: "Image Preview (Tap for fullscreen)", font: .caption)
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .cornerRadius(14)
                            .onTapGesture { showPlayerSheet = true }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker(videoURL: $selectedVideoURL, image: $selectedImage, onPicked: {
                presentPlayerSoon()
            })
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video, .image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                if let img = UIImage(contentsOfFile: url.path) {
                    selectedImage = img
                    selectedVideoURL = nil
                } else {
                    selectedVideoURL = url
                    selectedImage = nil
                }
                presentPlayerSoon()
            }
        }
        .sheet(isPresented: $showPlayerSheet) {
            if let vid = selectedVideoURL {
                UniversalVideoPlayerSheet(url: vid, title: vid.lastPathComponent)
            } else if let img = selectedImage {
                FullscreenImageSheet(image: img)
            }
        }
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Binding var image: UIImage?
    var onPicked: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .any(of: [.videos, .images])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    guard let url = url else { return }
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: temp)
                    try? FileManager.default.copyItem(at: url, to: temp)
                    DispatchQueue.main.async {
                        self.parent.videoURL = temp
                        self.parent.image = nil
                        self.parent.onPicked()
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.image = img
                            self.parent.videoURL = nil
                            self.parent.onPicked()
                        }
                    }
                }
            }
        }
    }
}

struct FullscreenImageSheet: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

// MARK: - IPTV

struct IPTVChannel: Identifiable {
    let id = UUID()
    let name: String
    let url: String
}

struct IPTVCastView: View {
    @State private var iptvLink = ""
    @State private var channels: [IPTVChannel] = []
    @State private var selectedChannel: IPTVChannel?
    @State private var showFileImporter = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                BilingualLabel(it: "IPTV Stream & Liste M3U", en: "IPTV Stream & M3U Lists", font: .title3.bold(), alignment: .leading)
                Spacer()
                BroadcastPicker(size: 46)
                    .frame(width: 46, height: 46)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            .padding(.horizontal).padding(.top, 8)

            VStack(spacing: 8) {
                TextField("Incolla link .m3u, .m3u8, .ts o stream / Paste IPTV URL", text: $iptvLink)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack(spacing: 10) {
                    Button { loadIPTVLink() } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            BilingualLabel(it: "Avvia / Carica Lista", en: "Play / Load Playlist", font: .caption.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.purple).foregroundColor(.white).cornerRadius(10)
                    }
                    Button { showFileImporter = true } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            BilingualLabel(it: "File .M3U", en: ".M3U File", font: .caption.bold(), color: .white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.systemGray)).foregroundColor(.white).cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)

            if isLoading { ProgressView("Caricamento canali / Loading...") }

            if channels.isEmpty {
                Spacer()
                BilingualLabel(
                    it: "Supporta link diretti (.m3u8, .ts, .mp4) e liste canali .m3u",
                    en: "Supports direct streams (.m3u8, .ts, .mp4) and .m3u playlists",
                    font: .footnote, color: .secondary
                )
                .multilineTextAlignment(.center)
                .padding()
                Spacer()
            } else {
                List(channels) { ch in
                    Button { selectedChannel = ch } label: {
                        HStack {
                            Image(systemName: "tv.fill").foregroundColor(.purple)
                            Text(ch.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Image(systemName: "play.circle").foregroundColor(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data, .text], allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first {
                _ = u.startAccessingSecurityScopedResource()
                if let text = try? String(contentsOf: u, encoding: .utf8) {
                    parseM3U(text)
                }
            }
        }
        .sheet(item: $selectedChannel) { ch in
            if let url = URL(string: ch.url) {
                UniversalVideoPlayerSheet(url: url, title: ch.name)
            }
        }
    }

    func loadIPTVLink() {
        let trimmed = iptvLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        let lower = trimmed.lowercased()
        if lower.contains(".m3u8") || lower.contains(".ts") || lower.contains(".mp4") {
            selectedChannel = IPTVChannel(name: "Diretta IPTV / Live Stream", url: trimmed)
            return
        }
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data, let content = String(data: data, encoding: .utf8), content.contains("#EXTINF") {
                    parseM3U(content)
                } else {
                    selectedChannel = IPTVChannel(name: "Stream IPTV", url: trimmed)
                }
            }
        }.resume()
    }

    func parseM3U(_ content: String) {
        var list: [IPTVChannel] = []
        var currentName = "Canale IPTV"
        for line in content.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("#EXTINF:") {
                // Il nome del canale è dopo l'ultima virgola
                if let comma = l.range(of: ",", options: .backwards) {
                    currentName = String(l[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            } else if l.hasPrefix("http") {
                list.append(IPTVChannel(name: currentName, url: l))
                currentName = "Canale IPTV"
            }
        }
        channels = list
    }
}

// MARK: - Player video

struct UniversalVideoPlayerSheet: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer?
    @State private var rate: Float = 1.0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                Menu("Velocità (\(String(format: "%.2gx", rate)))") {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button("\(String(format: "%.2gx", r))") {
                            rate = r
                            player?.rate = r
                        }
                    }
                }
                .font(.subheadline.bold())
                Button("Chiudi") { dismiss() }.padding(.leading, 8)
            }
            .padding()
            .background(Color(.systemGray6))

            if let p = player {
                VideoPlayer(player: p)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - App

struct ContentView: View {
    @State private var ip: String? = localIPAddress()
    @StateObject private var networkTrigger = LocalNetworkTrigger()
    @StateObject private var remote = RemoteControlManager()

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeMirrorView(ip: $ip)
                    .tabItem { Label("Schermo", systemImage: "tv.and.mediabox") }
                WebBrowserCastView()
                    .tabItem { Label("Browser", systemImage: "safari.fill") }
                MusicPlayerView()
                    .tabItem { Label("Musica", systemImage: "music.note") }
                GalleryMediaCastView()
                    .tabItem { Label("Galleria", systemImage: "photo.on.rectangle") }
                IPTVCastView()
                    .tabItem { Label("IPTV", systemImage: "antenna.radiowaves.left.and.right") }
            }
            .safeAreaInset(edge: .bottom) {
                if remote.isBroadcasting && remote.isMinimized {
                    MiniRemoteBar(remote: remote)
                        .padding(.bottom, 48)
                }
            }

            if remote.isBroadcasting && !remote.isMinimized {
                RemoteControlView(remote: remote, ipAddress: urlString)
                    .transition(.move(edge: .bottom))
                    .zIndex(50)
            }
        }
        .onAppear {
            ip = localIPAddress()
            networkTrigger.trigger()
            remote.startMonitoring()
        }
        .onDisappear {
            remote.stopMonitoring()
        }
    }
}

@main
struct MirrorTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
