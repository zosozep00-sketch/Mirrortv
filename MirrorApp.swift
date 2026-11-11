import SwiftUI
import ReplayKit
import Network

// Indirizzo IP dell'iPhone sul Wi-Fi (o sull'hotspot)
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

// Forza iOS a mostrare il popup "Consenti rete locale" all'apertura dell'app
class LocalNetworkTrigger: ObservableObject {
    private var browser: NWBrowser?

    func trigger() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
        self.browser = browser
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            browser.cancel()
        }
    }
}

// Logo Neon MirrorTV by Zoso (identico all'icona dell'app)
struct NeonLogoView: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                    .frame(width: compact ? 54 : 86, height: compact ? 54 : 86)
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
                    .shadow(color: Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.45), radius: compact ? 6 : 12)

                Image(systemName: "play.tv.fill")
                    .font(.system(size: compact ? 26 : 42, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.29, blue: 0.17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            if !compact {
                VStack(spacing: 2) {
                    Text("MirrorTV")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text("by Zoso")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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

// Etichetta bilingue IT / EN
struct BilingualLabel: View {
    let it: String
    let en: String
    var font: Font = .subheadline
    var color: Color = .primary
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(it)
                .font(font)
                .foregroundColor(color)
            Text(en)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// Pulsante di sistema per avviare la trasmissione dello schermo
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 84, height: 84))
        picker.preferredExtension = "com.example.mirrortvb.ext"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// Telecomando sincronizzato con il player web
class RemoteControlManager: ObservableObject {
    @Published var isBroadcasting = false
    @Published var resolution = "1280"
    @Published var fps = "30"
    @Published var speed = "1.0"
    @Published var fitMode = "contain"
    @Published var rotation = 0
    @Published var audioActive = false
    @Published var isPaused = false

    private var timer: Timer?

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
            }
        }
        if active {
            fetchState()
        }
    }

    func sendCommand(_ query: String) {
        guard let url = URL(string: "http://127.0.0.1:8080/control?\(query)") else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    func fetchState() {
        guard let url = URL(string: "http://127.0.0.1:8080/state") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
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

struct RemoteControlView: View {
    @ObservedObject var remote: RemoteControlManager
    let ipAddress: String

    let resolutions: [(label: String, val: String)] = [
        ("4K (2160p)", "3840"),
        ("2K (1440p)", "2560"),
        ("1080p Full HD", "1920"),
        ("720p HD", "1280"),
        ("480p SD", "854"),
        ("360p", "640"),
        ("240p", "426")
    ]

    let fpsOptions = ["60", "50", "30", "25", "15", "10"]
    let speedOptions = ["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "2.0"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    NeonLogoView(compact: true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("TRASMISSIONE LIVE")
                                .font(.headline).bold()
                        }
                        Text("LIVE BROADCASTING • \(ipAddress)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Comandi Rapidi Principali
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button {
                        remote.isPaused.toggle()
                        remote.sendCommand("paused=\(remote.isPaused ? 1 : 0)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: remote.isPaused ? "play.fill" : "pause.fill")
                                .font(.title2)
                            BilingualLabel(
                                it: remote.isPaused ? "Riprendi" : "Pausa",
                                en: remote.isPaused ? "Resume" : "Pause",
                                font: .callout.bold()
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(remote.isPaused ? Color.orange.opacity(0.25) : Color(.systemGray6))
                        .cornerRadius(14)
                    }

                    Button {
                        remote.audioActive.toggle()
                        remote.sendCommand("audio=\(remote.audioActive ? 1 : 0)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: remote.audioActive ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                .font(.title2)
                            BilingualLabel(
                                it: remote.audioActive ? "Audio Attivo" : "Attiva Audio",
                                en: remote.audioActive ? "Audio On" : "Enable Audio",
                                font: .callout.bold()
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(remote.audioActive ? Color.blue.opacity(0.25) : Color(.systemGray6))
                        .cornerRadius(14)
                    }

                    Button {
                        remote.rotation = (remote.rotation + 90) % 360
                        remote.sendCommand("rot=\(remote.rotation)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "rotate.right.fill")
                                .font(.title2)
                            BilingualLabel(
                                it: "Ruota (\(remote.rotation)°)",
                                en: "Rotate Screen",
                                font: .callout.bold()
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                    }

                    Button {
                        remote.fitMode = (remote.fitMode == "contain") ? "zoom" : "contain"
                        remote.sendCommand("fit=\(remote.fitMode)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: remote.fitMode == "zoom" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.title2)
                            BilingualLabel(
                                it: remote.fitMode == "zoom" ? "Zoom 118%" : "Adatta Intero",
                                en: remote.fitMode == "zoom" ? "Zoomed" : "Fit Screen",
                                font: .callout.bold()
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(remote.fitMode == "zoom" ? Color.purple.opacity(0.25) : Color(.systemGray6))
                        .cornerRadius(14)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // Selettori Risoluzione, FPS e Velocità
                VStack(spacing: 14) {
                    HStack {
                        BilingualLabel(it: "Risoluzione Video", en: "Video Resolution", font: .subheadline.bold(), alignment: .leading)
                        Spacer()
                        Picker("Risoluzione", selection: $remote.resolution) {
                            ForEach(resolutions, id: \.val) { item in
                                Text(item.label).tag(item.val)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: remote.resolution) { newVal in
                            remote.sendCommand("res=\(newVal)")
                        }
                    }

                    Divider()

                    HStack {
                        BilingualLabel(it: "Fluidità (FPS)", en: "Frame Rate", font: .subheadline.bold(), alignment: .leading)
                        Spacer()
                        Picker("FPS", selection: $remote.fps) {
                            ForEach(fpsOptions, id: \.self) { val in
                                Text("\(val) FPS").tag(val)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: remote.fps) { newVal in
                            remote.sendCommand("fps=\(newVal)")
                        }
                    }

                    Divider()

                    HStack {
                        BilingualLabel(it: "Velocità Flusso", en: "Playback Speed", font: .subheadline.bold(), alignment: .leading)
                        Spacer()
                        Picker("Velocità", selection: $remote.speed) {
                            ForEach(speedOptions, id: \.self) { val in
                                Text("\(val)x").tag(val)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: remote.speed) { newVal in
                            remote.sendCommand("speed=\(newVal)")
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)

                // Pulsante per interrompere la trasmissione
                VStack(spacing: 6) {
                    BroadcastPicker()
                        .frame(width: 72, height: 72)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(18)
                    BilingualLabel(
                        it: "Tocca per interrompere la trasmissione",
                        en: "Tap to stop broadcasting",
                        font: .caption,
                        color: .secondary
                    )
                }
                .padding(.top, 6)
            }
            .padding(.vertical)
        }
    }
}

struct ContentView: View {
    @State private var ip: String? = localIPAddress()
    @State private var copied = false
    @StateObject private var networkTrigger = LocalNetworkTrigger()
    @StateObject private var remote = RemoteControlManager()

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    var body: some View {
        Group {
            if remote.isBroadcasting {
                RemoteControlView(remote: remote, ipAddress: urlString)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        NeonLogoView(compact: false)
                            .padding(.top, 12)

                        VStack(spacing: 10) {
                            BilingualLabel(
                                it: "1. Tocca l'icona di trasmissione qui sotto",
                                en: "1. Tap the broadcast icon below"
                            )
                            BilingualLabel(
                                it: "2. Scegli 'Mirror TV' e premi 'Avvia trasmissione'",
                                en: "2. Choose 'Mirror TV' and tap 'Start Broadcast'"
                            )
                            BilingualLabel(
                                it: "3. Sulla TV o PC apri questo indirizzo nel browser:",
                                en: "3. Open this address in your TV or PC browser:"
                            )
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                        BroadcastPicker()
                            .frame(width: 84, height: 84)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)

                        Text(urlString)
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        HStack(spacing: 14) {
                            Button {
                                UIPasteboard.general.string = urlString
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            } label: {
                                BilingualLabel(
                                    it: copied ? "Copiato!" : "Copia indirizzo",
                                    en: copied ? "Copied!" : "Copy address",
                                    font: .subheadline.bold()
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                ip = localIPAddress()
                            } label: {
                                BilingualLabel(
                                    it: "Aggiorna IP",
                                    en: "Refresh IP",
                                    font: .subheadline.bold()
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }

                        BilingualLabel(
                            it: "La TV e l'iPhone devono essere sulla stessa rete Wi-Fi.",
                            en: "TV and iPhone must be connected to the same Wi-Fi network.",
                            font: .footnote,
                            color: .secondary
                        )
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                    }
                    .padding()
                }
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
