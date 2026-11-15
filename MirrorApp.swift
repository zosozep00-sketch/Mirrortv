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

// MARK: - Orientamento e finestra del telecomando

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Rotazione automatica in tutte le modalità: segue il sensore del telefono
    // e rispetta il blocco rotazione del Centro di Controllo.
    static var supportedMask: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.supportedMask
    }
}

// Finestra trasparente sopra a tutto: lascia passare i tocchi dove non c'è la barra
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === rootViewController?.view { return nil }
        return hit
    }
}

final class OverlayHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return AppDelegate.supportedMask
    }
}

final class RemoteOverlayManager {
    static let shared = RemoteOverlayManager()
    private var window: PassthroughWindow?

    func install(remote: RemoteControlManager) {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }

        let host = OverlayHostingController(rootView: RemoteOverlayView(remote: remote))
        host.view.backgroundColor = .clear

        let w = PassthroughWindow(windowScene: scene)
        w.rootViewController = host
        w.backgroundColor = .clear
        w.windowLevel = UIWindow.Level.alert + 1
        w.isHidden = false
        window = w
    }
}

struct RemoteOverlayView: View {
    @ObservedObject var remote: RemoteControlManager
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero

    private var addressText: String {
        if let ip = localIPAddress() { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let maxX = max(size.width / 2 - 40, 0)
                let newX = min(max(dragStart.width + value.translation.width, -maxX), maxX)
                let newY = min(max(dragStart.height + value.translation.height, -(size.height - 160)), 40)
                offset = CGSize(width: newX, height: newY)
            }
            .onEnded { _ in dragStart = offset }
    }

    private var handleButton: some View {
        Button {
            withAnimation { remote.barHidden = false }
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.red.opacity(0.85))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if remote.isBroadcasting {
                    if !remote.isMinimized {
                        RemoteControlView(remote: remote, ipAddress: addressText)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else if remote.barHidden {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                handleButton
                            }
                            .padding(.trailing, 12)
                            .padding(.bottom, 120)
                        }
                    } else {
                        VStack {
                            Spacer()
                            MiniRemoteBar(remote: remote)
                                .offset(offset)
                                .gesture(dragGesture(in: geo.size))
                                .padding(.bottom, 60)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Telecomando

class RemoteControlManager: ObservableObject {
    @Published var isBroadcasting = false
    @Published var isMinimized = true
    @Published var isConnected = false
    @Published var resolution = "1280"
    @Published var fps = "30"
    @Published var speed = "1.0"
    @Published var fitMode = "contain"
    @Published var rotation = 0
    @Published var audioActive = false
    @Published var isPaused = false
    @Published var isFullscreen = false
    @Published var barHidden = false

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
                self.isMinimized = true
                self.barHidden = false
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
                if let full = json["full"] as? Bool { self?.isFullscreen = full }
            }
        }.resume()
    }
}

struct MiniRemoteBar: View {
    @ObservedObject var remote: RemoteControlManager

    private func circleButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(active ? Color.blue.opacity(0.35) : Color(.systemGray5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    remote.isMinimized = false
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(remote.isConnected ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                    Text("LIVE")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            circleButton(remote.isPaused ? "play.fill" : "pause.fill", active: remote.isPaused) {
                remote.isPaused.toggle()
                remote.sendCommand("paused=\(remote.isPaused ? 1 : 0)")
            }

            circleButton(remote.audioActive ? "speaker.wave.2.fill" : "speaker.slash.fill", active: remote.audioActive) {
                remote.audioActive.toggle()
                remote.sendCommand("audio=\(remote.audioActive ? 1 : 0)")
            }

            circleButton("rotate.right.fill") {
                remote.rotation = (remote.rotation + 90) % 360
                remote.sendCommand("rot=\(remote.rotation)")
            }

            circleButton(remote.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         active: remote.isFullscreen) {
                remote.isFullscreen.toggle()
                remote.sendCommand("full=\(remote.isFullscreen ? 1 : 0)")
            }

            circleButton("eye.slash.fill") {
                withAnimation { remote.barHidden = true }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
        .padding(.horizontal, 10)
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
                    fullscreenButton
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
                    BilingualLabel(it: remote.fitMode == "zoom" ? "Zoom 118%" : "Adatta",
                                   en: remote.fitMode == "zoom" ? "Zoomed" : "Fit",
                                   font: .callout.bold())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(remote.fitMode == "zoom" ? Color.purple.opacity(0.25) : Color(.systemGray6)).cornerRadius(14)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var fullscreenButton: some View {
        Button {
            remote.isFullscreen.toggle()
            remote.sendCommand("full=\(remote.isFullscreen ? 1 : 0)")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: remote.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                BilingualLabel(it: remote.isFullscreen ? "Esci da Schermo Intero" : "Schermo Intero",
                               en: remote.isFullscreen ? "Exit Fullscreen" : "Fullscreen",
                               font: .callout.bold())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(remote.isFullscreen ? Color.green.opacity(0.25) : Color(.systemGray6))
            .cornerRadius(14)
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

// MARK: - Dati salvati (elementi recenti)

enum RecentKind: String, Codable {
    case music
    case video
    case image
    case link
    case playlist
}

struct RecentItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: RecentKind
    var title: String
    var fileName: String?
    var urlString: String?
    var date = Date()
}

// File copiati dentro l'app: restano anche dopo aver chiuso e riaperto l'app
enum AppStorageFiles {
    static var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importFile(_ source: URL) -> String? {
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        let prefix = String(UUID().uuidString.prefix(8))
        let name = prefix + "-" + base + (ext.isEmpty ? "" : "." + ext)
        do {
            try FileManager.default.copyItem(at: source, to: mediaDirectory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func saveImage(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        let name = String(UUID().uuidString.prefix(8)) + "-foto.jpg"
        do {
            try data.write(to: mediaDirectory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func url(for fileName: String) -> URL {
        return mediaDirectory.appendingPathComponent(fileName)
    }

    static func exists(_ fileName: String) -> Bool {
        return FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

final class RecentsStore: ObservableObject {
    @Published private(set) var items: [RecentItem] = []
    private let key: String
    private let limit: Int

    init(key: String, limit: Int = 50) {
        self.key = key
        self.limit = limit
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([RecentItem].self, from: data) else { return }
        // Tolgo le voci il cui file non esiste più
        items = saved.filter { item in
            if let f = item.fileName { return AppStorageFiles.exists(f) }
            return true
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ item: RecentItem, atFront: Bool = true) {
        if let link = item.urlString {
            items.removeAll { $0.urlString == link }
        }
        if atFront {
            items.insert(item, at: 0)
        } else {
            items.append(item)
        }
        while items.count > limit {
            let removed = atFront ? items.removeLast() : items.removeFirst()
            if let f = removed.fileName { AppStorageFiles.delete(f) }
        }
        save()
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
        if let f = item.fileName { AppStorageFiles.delete(f) }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where items.indices.contains(index) {
            let removed = items.remove(at: index)
            if let f = removed.fileName { AppStorageFiles.delete(f) }
        }
        save()
    }

    func clear() {
        for item in items {
            if let f = item.fileName { AppStorageFiles.delete(f) }
        }
        items = []
        save()
    }
}

// MARK: - Browser

struct SafariWebView: UIViewRepresentable {
    let urlString: String
    @Binding var detectedVideoURL: String?
    var onPageLoaded: (String, String) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Su iPhone i video del sito si aprono nel player a schermo intero, che ruota da solo
        config.allowsInlineMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.lastLoaded = urlString
        load(urlString, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
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
            if let url = webView.url?.absoluteString, url.hasPrefix("http") {
                parent.onPageLoaded(url, webView.title ?? "")
            }
            let js = "Array.from(document.querySelectorAll('video, source')).map(v => v.src || v.currentSrc).find(s => s && s.startsWith('http'))"
            webView.evaluateJavaScript(js) { res, _ in
                if let videoSrc = res as? String, !videoSrc.isEmpty {
                    DispatchQueue.main.async { self.parent.detectedVideoURL = videoSrc }
                }
            }
        }
    }
}

struct BrowserHistorySheet: View {
    @ObservedObject var store: RecentsStore
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if store.items.isEmpty {
                    Text("Nessuna pagina recente / No recent pages")
                        .foregroundColor(.secondary)
                }
                ForEach(store.items) { item in
                    Button {
                        if let u = item.urlString { onSelect(u) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1).foregroundColor(.primary)
                            Text(item.urlString ?? "").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in store.remove(atOffsets: offsets) }
            }
            .listStyle(.plain)
            .navigationTitle("Cronologia / History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Svuota") { store.clear() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct WebBrowserCastView: View {
    @StateObject private var history = RecentsStore(key: "recents.web", limit: 100)
    @State private var inputURL: String = UserDefaults.standard.string(forKey: "browser.lastURL") ?? "youtube.com"
    @State private var activeURL: String = UserDefaults.standard.string(forKey: "browser.lastURL") ?? "youtube.com"
    @State private var detectedVideoURL: String? = nil
    @State private var showFullPlayer = false
    @State private var showHistory = false

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
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.title2)
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

            SafariWebView(urlString: activeURL, detectedVideoURL: $detectedVideoURL, onPageLoaded: { url, title in
                UserDefaults.standard.set(url, forKey: "browser.lastURL")
                history.add(RecentItem(kind: .link,
                                       title: title.isEmpty ? url : title,
                                       fileName: nil,
                                       urlString: url))
            })
        }
        .sheet(isPresented: $showHistory) {
            BrowserHistorySheet(store: history, onSelect: { url in
                inputURL = url
                activeURL = url
                showHistory = false
            })
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            if let vid = detectedVideoURL, let u = URL(string: vid) {
                UniversalVideoPlayerSheet(url: u, title: "Web Video Cast")
            }
        }
    }
}

// MARK: - Selettore file

// Apre il selettore di iOS e fa COPIARE il file dentro l'app: così non servono
// permessi speciali e funziona anche con app installate fuori dall'App Store.
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    var allowsMultiple: Bool = false
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

// MARK: - Musica

final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.onFinish() }
    }
}

struct MusicPlayerView: View {
    @StateObject private var store = RecentsStore(key: "recents.music", limit: 300)
    @State private var currentIndex: Int = 0
    @State private var player: AVAudioPlayer?
    @State private var playerDelegate = PlayerDelegate()
    @State private var isPlaying = false
    @State private var showFileImporter = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var tracks: [RecentItem] { store.items }

    var currentTrackName: String {
        guard tracks.indices.contains(currentIndex) else { return "Nessun brano selezionato" }
        return tracks[currentIndex].title
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
                        HStack {
                            BilingualLabel(it: "Playlist salvata", en: "Saved tracklist", font: .subheadline.bold(), alignment: .leading)
                            Spacer()
                            Button(role: .destructive) { clearAll() } label: {
                                Text("Svuota / Clear").font(.caption.bold())
                            }
                        }
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, item in
                            HStack(spacing: 8) {
                                Button {
                                    currentIndex = idx
                                    playTrack(at: idx)
                                } label: {
                                    HStack {
                                        Image(systemName: idx == currentIndex && isPlaying ? "speaker.wave.2.fill" : "music.note")
                                            .foregroundColor(.green)
                                        Text(item.title).lineLimit(1).font(.subheadline)
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button { removeTrack(at: idx) } label: {
                                    Image(systemName: "trash").foregroundColor(.red).padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showFileImporter) {
            DocumentPicker(contentTypes: [.audio], allowsMultiple: true,
                           onPick: { urls in
                               showFileImporter = false
                               addTracks(urls)
                           },
                           onCancel: { showFileImporter = false })
        }
        .onReceive(timer) { _ in
            if let p = player, p.isPlaying {
                progress = p.currentTime
                duration = max(p.duration, 1)
            }
        }
    }

    func addTracks(_ urls: [URL]) {
        let wasEmpty = tracks.isEmpty
        for u in urls {
            if let name = AppStorageFiles.importFile(u) {
                store.add(RecentItem(kind: .music,
                                     title: u.deletingPathExtension().lastPathComponent,
                                     fileName: name,
                                     urlString: nil),
                          atFront: false)
            }
        }
        if wasEmpty && !tracks.isEmpty {
            currentIndex = 0
            playTrack(at: 0)
        }
    }

    func removeTrack(at idx: Int) {
        guard tracks.indices.contains(idx) else { return }
        let item = tracks[idx]
        if idx == currentIndex {
            player?.stop()
            player = nil
            isPlaying = false
            progress = 0
        }
        store.remove(item)
        if idx < currentIndex { currentIndex -= 1 }
        if currentIndex >= tracks.count { currentIndex = max(0, tracks.count - 1) }
    }

    func clearAll() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        currentIndex = 0
        store.clear()
    }

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index), let file = tracks[index].fileName else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: AppStorageFiles.url(for: file))
            playerDelegate.onFinish = {
                if tracks.count > 1 { nextTrack() } else { isPlaying = false }
            }
            p.delegate = playerDelegate
            player = p
            p.play()
            isPlaying = true
            duration = max(p.duration, 1)
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

enum GalleryPicker: Identifiable {
    case photos
    case files

    var id: Int {
        switch self {
        case .photos: return 0
        case .files: return 1
        }
    }
}

struct GalleryMediaCastView: View {
    @StateObject private var store = RecentsStore(key: "recents.gallery", limit: 40)
    @State private var selectedVideoURL: URL?
    @State private var selectedImage: UIImage?
    @State private var picker: GalleryPicker?
    @State private var showPlayer = false

    // Aspetta che il selettore si sia chiuso prima di aprire il player
    private func presentPlayerSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showPlayer = true
        }
    }

    // Salva una copia nell'app (resta nei recenti) e prepara la riproduzione
    private func handlePicked(videoURL: URL?, image: UIImage?, title: String) {
        if let img = image, let name = AppStorageFiles.saveImage(img) {
            store.add(RecentItem(kind: .image, title: title, fileName: name, urlString: nil))
            selectedImage = img
            selectedVideoURL = nil
        } else if let v = videoURL, let name = AppStorageFiles.importFile(v) {
            store.add(RecentItem(kind: .video, title: title, fileName: name, urlString: nil))
            selectedVideoURL = AppStorageFiles.url(for: name)
            selectedImage = nil
        } else {
            return
        }
        presentPlayerSoon()
    }

    private func open(_ item: RecentItem) {
        guard let file = item.fileName, AppStorageFiles.exists(file) else { return }
        let url = AppStorageFiles.url(for: file)
        if item.kind == .image, let img = UIImage(contentsOfFile: url.path) {
            selectedImage = img
            selectedVideoURL = nil
        } else {
            selectedVideoURL = url
            selectedImage = nil
        }
        showPlayer = true
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
                    Button { picker = .photos } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled").font(.title)
                            BilingualLabel(it: "Apri Galleria", en: "Open Gallery", font: .subheadline.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.red).foregroundColor(.white).cornerRadius(16)
                    }
                    Button { picker = .files } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.fill").font(.title)
                            BilingualLabel(it: "Apri da File", en: "Open Files", font: .subheadline.bold(), color: .white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(16)
                    }
                }
                .padding(.horizontal)

                if !store.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            BilingualLabel(it: "Recenti", en: "Recent", font: .subheadline.bold(), alignment: .leading)
                            Spacer()
                            Button(role: .destructive) { store.clear() } label: {
                                Text("Svuota / Clear").font(.caption.bold())
                            }
                        }
                        ForEach(store.items) { item in
                            HStack(spacing: 8) {
                                Button { open(item) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.kind == .image ? "photo.fill" : "play.rectangle.fill")
                                            .foregroundColor(item.kind == .image ? Color.orange : Color.red)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).font(.subheadline).lineLimit(1)
                                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button { store.remove(item) } label: {
                                    Image(systemName: "trash").foregroundColor(.red).padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .sheet(item: $picker) { kind in
            switch kind {
            case .photos:
                PhotoLibraryPicker(onPicked: { videoURL, image in
                    picker = nil
                    let title = videoURL?.deletingPathExtension().lastPathComponent ?? "Foto"
                    handlePicked(videoURL: videoURL, image: image, title: title)
                })
            case .files:
                DocumentPicker(contentTypes: [.movie, .video, .image],
                               onPick: { urls in
                                   picker = nil
                                   guard let url = urls.first else { return }
                                   let title = url.deletingPathExtension().lastPathComponent
                                   if let img = UIImage(contentsOfFile: url.path) {
                                       handlePicked(videoURL: nil, image: img, title: title)
                                   } else {
                                       handlePicked(videoURL: url, image: nil, title: title)
                                   }
                               },
                               onCancel: { picker = nil })
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let vid = selectedVideoURL {
                UniversalVideoPlayerSheet(url: vid, title: vid.lastPathComponent)
            } else if let img = selectedImage {
                FullscreenImageSheet(image: img)
            }
        }
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPicked: (URL?, UIImage?) -> Void

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
                    DispatchQueue.main.async { self.parent.onPicked(temp, nil) }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.onPicked(nil, img) }
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
    @StateObject private var store = RecentsStore(key: "recents.iptv", limit: 60)
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
                    Button { openLink(iptvLink) } label: {
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

            List {
                if !channels.isEmpty {
                    Section(header: Text("Canali / Channels")) {
                        ForEach(channels) { ch in
                            Button { selectedChannel = ch } label: {
                                HStack {
                                    Image(systemName: "tv.fill").foregroundColor(.purple)
                                    Text(ch.name).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "play.circle").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Recenti / Recent")) {
                    if store.items.isEmpty {
                        Text("Nessun elemento recente / No recent items")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.items) { item in
                        Button { openRecent(item) } label: {
                            HStack {
                                Image(systemName: item.kind == .playlist ? "doc.text.fill" : "link")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline).lineLimit(1)
                                    if let u = item.urlString {
                                        Text(u).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .onDelete { offsets in store.remove(atOffsets: offsets) }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showFileImporter) {
            DocumentPicker(contentTypes: [.data, .text],
                           onPick: { urls in
                               showFileImporter = false
                               guard let u = urls.first,
                                     let text = try? String(contentsOf: u, encoding: .utf8) else { return }
                               if let name = AppStorageFiles.importFile(u) {
                                   store.add(RecentItem(kind: .playlist,
                                                        title: u.lastPathComponent,
                                                        fileName: name,
                                                        urlString: nil))
                               }
                               parseM3U(text)
                           },
                           onCancel: { showFileImporter = false })
        }
        .fullScreenCover(item: $selectedChannel) { ch in
            if let url = URL(string: ch.url) {
                UniversalVideoPlayerSheet(url: url, title: ch.name)
            }
        }
    }

    func remember(link: String, title: String) {
        store.add(RecentItem(kind: .link, title: title, fileName: nil, urlString: link))
    }

    func openRecent(_ item: RecentItem) {
        if item.kind == .playlist, let file = item.fileName,
           let text = try? String(contentsOf: AppStorageFiles.url(for: file), encoding: .utf8) {
            parseM3U(text)
        } else if let link = item.urlString {
            iptvLink = link
            openLink(link)
        }
    }

    func openLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
        let host = url.host ?? "IPTV"
        let lower = trimmed.lowercased()
        if lower.contains(".m3u8") || lower.contains(".ts") || lower.contains(".mp4") {
            remember(link: trimmed, title: "Stream " + host)
            selectedChannel = IPTVChannel(name: "Diretta IPTV / Live Stream", url: trimmed)
            return
        }
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data, let content = String(data: data, encoding: .utf8), content.contains("#EXTINF") {
                    remember(link: trimmed, title: "Playlist " + host)
                    parseM3U(content)
                } else {
                    remember(link: trimmed, title: "Stream " + host)
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

    private var header: some View {
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
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !landscape { header }

                    if let p = player {
                        VideoPlayer(player: p)
                            .ignoresSafeArea(edges: landscape ? Edge.Set.all : Edge.Set.bottom)
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Spacer()
                    }
                }

                // In orizzontale resta solo il video, con un piccolo tasto per chiudere
                if landscape {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(14)
                    }
                }
            }
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
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
    @State private var selectedTab = 0
    @State private var visited: Set<Int> = [0]
    @StateObject private var networkTrigger = LocalNetworkTrigger()
    @StateObject private var remote = RemoteControlManager()

    private let tabs: [(title: String, icon: String)] = [
        ("Schermo", "tv.and.mediabox"),
        ("Browser", "safari.fill"),
        ("Musica", "music.note"),
        ("Galleria", "photo.on.rectangle"),
        ("IPTV", "antenna.radiowaves.left.and.right")
    ]

    private func select(_ index: Int) {
        selectedTab = index
        visited.insert(index)
    }

    @ViewBuilder
    private func tabView(_ index: Int) -> some View {
        switch index {
        case 0: HomeMirrorView(ip: $ip)
        case 1: WebBrowserCastView()
        case 2: MusicPlayerView()
        case 3: GalleryMediaCastView()
        default: IPTVCastView()
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(0..<5, id: \.self) { i in
                Button { select(i) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tabs[i].icon).font(.system(size: 20))
                        Text(tabs[i].title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(selectedTab == i ? Color.blue : Color.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
        .overlay(Divider(), alignment: .top)
    }

    // In orizzontale la barra sparisce e resta un piccolo menu per cambiare modalità
    private var landscapeMenu: some View {
        Menu {
            ForEach(0..<5, id: \.self) { i in
                Button { select(i) } label: {
                    Label(tabs[i].title, systemImage: tabs[i].icon)
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .padding(.leading, 8)
        .padding(.top, 8)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ZStack {
                        ForEach(0..<5, id: \.self) { i in
                            if visited.contains(i) {
                                tabView(i)
                                    .opacity(selectedTab == i ? 1 : 0)
                                    .allowsHitTesting(selectedTab == i)
                                    .zIndex(selectedTab == i ? 1 : 0)
                            }
                        }
                    }
                    if !landscape { tabBar }
                }
                if landscape { landscapeMenu }
            }
        }
        .onAppear {
            ip = localIPAddress()
            networkTrigger.trigger()
            remote.startMonitoring()
            // Il telecomando vive in una finestra sopra a tutto, anche sopra ai player
            RemoteOverlayManager.shared.install(remote: remote)
        }
        .onDisappear {
            remote.stopMonitoring()
        }
    }
}

@main
struct MirrorTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
