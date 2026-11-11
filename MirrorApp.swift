import SwiftUI
import ReplayKit
import Network
import Combine

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            browser.cancel()
        }
    }
}

struct BilingualLabel: View {
    let it: String
    let en: String
    var itFont: Font = .body
    var enFont: Font = .caption2
    var itColor: Color = .primary
    var enColor: Color = .secondary

    var body: some View {
        VStack(spacing: 2) {
            Text(it)
                .font(itFont)
                .foregroundColor(itColor)
            Text(en)
                .font(enFont)
                .foregroundColor(enColor)
        }
        .multilineTextAlignment(.center)
    }
}

// Logo vettoriale identico all'icona dell'app (Neon TV + Play + Onde)
struct MirrorTVLogoView: View {
    var size: CGFloat = 110

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [Color.cyan.opacity(0.6), Color.orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color.cyan.opacity(0.35), radius: 12, x: -4, y: -4)
                    .shadow(color: Color.red.opacity(0.35), radius: 12, x: 4, y: 4)

                // Cornice TV Neon
                RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan, Color(red: 1.0, green: 0.28, blue: 0.34), Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.045
                    )
                    .frame(width: size * 0.56, height: size * 0.40)

                // Base TV
                Capsule()
                    .fill(
                        LinearGradient(colors: [Color.pink, Color.orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: size * 0.28, height: size * 0.04)
                    .offset(y: size * 0.26)

                // Triangolo Play centrale
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .offset(x: size * 0.015)

                // Onde Wi-Fi in alto a destra
                Image(systemName: "wifi")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan, Color.orange], startPoint: .top, endPoint: .bottom)
                    )
                    .rotationEffect(.degrees(45))
                    .offset(x: size * 0.26, y: -size * 0.24)
            }

            VStack(spacing: 1) {
                Text("MirrorTV")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("by Zoso")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan, Color.orange], startPoint: .leading, endPoint: .trailing)
                    )
            }
        }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
        picker.preferredExtension = "com.example.mirrortvb.ext"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// Controller remoto sincronizzato in tempo reale con il player proiettato
class RemoteController: ObservableObject {
    @Published var isBroadcasting = false
    @Published var resolution = "1280"
    @Published var fps = "30"
    @Published var speed = "1.0"
    @Published var fitMode = "contain"
    @Published var rotation = 0
    @Published var audioMuted = false
    @Published var remoteCommandSeq = 0
    @Published var lastAction = ""

    private var timer: Timer?

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchState()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func fetchState() {
        guard let url = URL(string: "http://127.0.0.1:8080/state") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.7
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data, err == nil,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.isBroadcasting = true
                    if let r = json["res"] as? String { self.resolution = r }
                    if let f = json["fps"] as? String { self.fps = f }
                    if let s = json["speed"] as? String { self.speed = s }
                    if let m = json["fit"] as? String { self.fitMode = m }
                    if let rot = json["rot"] as? Int { self.rotation = rot }
                    if let am = json["audioMuted"] as? Bool { self.audioMuted = am }
                } else {
                    self.isBroadcasting = false
                }
            }
        }.resume()
    }

    func sendCommand(_ query: String) {
        guard let url = URL(string: "http://127.0.0.1:8080/config?\(query)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.fetchState()
            }
        }.resume()
    }
}

struct RemoteControlView: View {
    @ObservedObject var remote: RemoteController
    let urlString: String

    let resolutions: [(label: String, val: String)] = [
        ("4K Ultra HD (2160p)", "3840"),
        ("2K Quad HD (1440p)", "2560"),
        ("Full HD (1080p)", "1920"),
        ("HD (720p)", "1280"),
        ("SD (480p)", "854"),
        ("Bassa (360p)", "640"),
        ("Ultra Leggera (240p)", "426")
    ]

    let fpsOptions = ["60", "50", "30", "24", "15", "10"]
    let speedOptions = ["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "2.0"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    BilingualLabel(
                        it: "TRASMISSIONE IN CORSO",
                        en: "LIVE BROADCASTING",
                        itFont: .headline.bold(),
                        enFont: .caption2,
                        itColor: .red,
                        enColor: .secondary
                    )
                }
                .padding(.top, 8)

                Text(urlString)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                // Controllo Audio & Rotazione
                HStack(spacing: 12) {
                    Button {
                        let nextMute = !remote.audioMuted
                        remote.audioMuted = nextMute
                        remote.sendCommand("mute=\(nextMute ? 1 : 0)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: remote.audioMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                                .font(.title2)
                            BilingualLabel(
                                it: remote.audioMuted ? "Riattiva Audio" : "Silenzia Audio",
                                en: remote.audioMuted ? "Unmute Audio" : "Mute Audio",
                                itFont: .caption.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .white.opacity(0.8)
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(remote.audioMuted ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }

                    Button {
                        let nextRot = (remote.rotation + 90) % 360
                        remote.rotation = nextRot
                        remote.sendCommand("rot=\(nextRot)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "rotate.right.fill")
                                .font(.title2)
                            BilingualLabel(
                                it: "Ruota Schermo (\(remote.rotation)°)",
                                en: "Rotate Screen (\(remote.rotation)°)",
                                itFont: .caption.bold(),
                                enFont: .caption2,
                                itColor: .primary,
                                enColor: .secondary
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(14)
                    }
                }

                // Formato / Zoom e Schermo Intero
                HStack(spacing: 12) {
                    Button {
                        let nextFit = (remote.fitMode == "contain") ? "zoom" : "contain"
                        remote.fitMode = nextFit
                        remote.sendCommand("fit=\(nextFit)")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: remote.fitMode == "zoom" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                            BilingualLabel(
                                it: remote.fitMode == "zoom" ? "Adatta Schermo" : "Zoom Riempi",
                                en: remote.fitMode == "zoom" ? "Fit Screen" : "Zoom Fill",
                                itFont: .caption.bold(),
                                enFont: .caption2
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(14)
                    }

                    Button {
                        remote.sendCommand("action=fullscreen")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "viewfinder")
                                .font(.title3)
                            BilingualLabel(
                                it: "Schermo Intero TV",
                                en: "Toggle TV Fullscreen",
                                itFont: .caption.bold(),
                                enFont: .caption2
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(14)
                    }
                }

                // Selettore Risoluzione
                VStack(alignment: .leading, spacing: 6) {
                    BilingualLabel(
                        it: "Risoluzione Video",
                        en: "Video Resolution",
                        itFont: .subheadline.bold(),
                        enFont: .caption2
                    )
                    Picker("Risoluzione", selection: $remote.resolution) {
                        ForEach(resolutions, id: \.val) { item in
                            Text(item.label).tag(item.val)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .onChange(of: remote.resolution) { newVal in
                        remote.sendCommand("res=\(newVal)")
                    }
                }

                // Selettore Fluidità (FPS) e Velocità
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        BilingualLabel(
                            it: "Fluidità (FPS)",
                            en: "Frame Rate (FPS)",
                            itFont: .subheadline.bold(),
                            enFont: .caption2
                        )
                        Picker("FPS", selection: $remote.fps) {
                            ForEach(fpsOptions, id: \.self) { f in
                                Text("\(f) FPS").tag(f)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .onChange(of: remote.fps) { newVal in
                            remote.sendCommand("fps=\(newVal)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        BilingualLabel(
                            it: "Velocità Flusso",
                            en: "Playback Speed",
                            itFont: .subheadline.bold(),
                            enFont: .caption2
                        )
                        Picker("Velocità", selection: $remote.speed) {
                            ForEach(speedOptions, id: \.self) { s in
                                Text("\(s)x").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .onChange(of: remote.speed) { newVal in
                            remote.sendCommand("speed=\(newVal)")
                        }
                    }
                }

                // Pulsante per fermare la trasmissione
                VStack(spacing: 6) {
                    BroadcastPicker()
                        .frame(width: 70, height: 70)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    BilingualLabel(
                        it: "Tocca per interrompere la trasmissione",
                        en: "Tap to stop broadcasting",
                        itFont: .caption,
                        enFont: .caption2
                    )
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
}

struct ContentView: View {
    @State private var ip: String? = localIPAddress()
    @State private var copied = false
    @StateObject private var networkTrigger = LocalNetworkTrigger()
    @StateObject private var remote = RemoteController()

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    var body: some View {
        Group {
            if remote.isBroadcasting {
                RemoteControlView(remote: remote, urlString: urlString)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        MirrorTVLogoView(size: 110)
                            .padding(.top, 16)

                        VStack(spacing: 10) {
                            BilingualLabel(
                                it: "1. Tocca l'icona qui sotto",
                                en: "1. Tap the icon below",
                                itFont: .subheadline.bold(),
                                enFont: .caption2
                            )
                            BilingualLabel(
                                it: "2. Scegli "Mirror TV" e premi "Avvia trasmissione"",
                                en: "2. Select "Mirror TV" and tap "Start Broadcast"",
                                itFont: .subheadline.bold(),
                                enFont: .caption2
                            )
                            BilingualLabel(
                                it: "3. Sulla TV o PC apri questo indirizzo nel browser:",
                                en: "3. Open this address in your TV or PC browser:",
                                itFont: .subheadline.bold(),
                                enFont: .caption2
                            )
                        }
                        .padding(.horizontal)

                        BroadcastPicker()
                            .frame(width: 90, height: 90)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)

                        Text(urlString)
                            .font(.system(.title3, design: .monospaced).bold())
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = urlString
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            } label: {
                                BilingualLabel(
                                    it: copied ? "Copiato!" : "Copia indirizzo",
                                    en: copied ? "Copied!" : "Copy address",
                                    itFont: .subheadline.bold(),
                                    enFont: .caption2
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                ip = localIPAddress()
                            } label: {
                                BilingualLabel(
                                    it: "Aggiorna IP",
                                    en: "Refresh IP",
                                    itFont: .subheadline.bold(),
                                    enFont: .caption2
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }

                        BilingualLabel(
                            it: "La TV e l'iPhone devono essere sulla stessa rete Wi-Fi.",
                            en: "TV and iPhone must be connected to the same Wi-Fi network.",
                            itFont: .footnote,
                            enFont: .caption2
                        )
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            ip = localIPAddress()
            networkTrigger.trigger()
            remote.startPolling()
        }
        .onDisappear {
            remote.stopPolling()
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
