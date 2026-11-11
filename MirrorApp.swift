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

// Modello stato sincronizzato con il player web
class RemoteState: ObservableObject {
    @Published var isBroadcasting = false
    @Published var resolution = "1280"
    @Published var fps = "30"
    @Published var fitMode = "contain"
    @Published var rotation = 0
    @Published var speed = "1.0"
    @Published var audioActive = false
    @Published var fullscreenTrigger = 0

    private var timer: Timer?

    func startMonitoring() {
        checkBroadcast()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBroadcast()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkBroadcast() {
        let captured = UIScreen.main.isCaptured
        DispatchQueue.main.async {
            if self.isBroadcasting != captured {
                self.isBroadcasting = captured
            }
            if captured {
                self.fetchStateFromServer()
            }
        }
    }

    func fetchStateFromServer() {
        guard let url = URL(string: "http://127.0.0.1:8080/state") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let res = json["res"] as? String { self.resolution = res }
                if let fps = json["fps"] as? String { self.fps = fps }
                if let fit = json["fit"] as? String { self.fitMode = fit }
                if let rot = json["rot"] as? Int { self.rotation = rot }
                if let spd = json["spd"] as? String { self.speed = spd }
                if let aud = json["aud"] as? Bool { self.audioActive = aud }
            }
        }.resume()
    }

    func sendCommand(_ query: String) {
        guard let url = URL(string: "http://127.0.0.1:8080/config?\(query)") else { return }
        URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
    }
}

// Vista Testo Bilingue (Italiano + Inglese più piccolo)
struct BilingualText: View {
    let it: String
    let en: String
    var itFont: Font = .subheadline
    var enFont: Font = .caption2
    var itColor: Color = .primary
    var enColor: Color = .secondary
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(it)
                .font(itFont)
                .foregroundColor(itColor)
            Text(en)
                .font(enFont)
                .foregroundColor(enColor)
        }
    }
}

// Logo Neon MirrorTV by Zoso
struct BrandLogoView: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 12 : 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.29, blue: 0.17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 42 : 64, height: compact ? 42 : 64)
                    .shadow(color: Color.cyan.opacity(0.5), radius: 10, x: -2, y: -2)
                    .shadow(color: Color.red.opacity(0.5), radius: 10, x: 2, y: 2)

                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 18 : 28, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MirrorTV")
                    .font(compact ? .title3.bold() : .system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text("by Zoso")
                    .font(compact ? .caption.bold() : .subheadline.bold())
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

// Pulsante di sistema per avviare la trasmissione dello schermo
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
        picker.preferredExtension = "com.example.mirrortvb.ext"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// Schermata Telecomando Live sincronizzata quando la trasmissione è attiva
struct LiveRemoteView: View {
    @ObservedObject var state: RemoteState
    let ipAddress: String

    let resolutions = [
        ("2160", "4K (2160p)"),
        ("1440", "2K (1440p)"),
        ("1920", "1080p Full HD"),
        ("1280", "720p HD"),
        ("854", "480p SD"),
        ("640", "360p"),
        ("426", "240p")
    ]

    let fpsOptions = ["60", "50", "30", "24", "15", "10"]
    let speedOptions = ["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "2.0"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    BrandLogoView(compact: true)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.25))
                    .cornerRadius(8)
                }
                .padding(.top, 8)

                // Indirizzo attivo
                VStack(spacing: 4) {
                    BilingualText(
                        it: "Proiezione attiva su:",
                        en: "Casting live at:",
                        itFont: .caption.bold(),
                        enFont: .caption2,
                        itColor: .gray,
                        enColor: .gray.opacity(0.7)
                    )
                    Text(ipAddress)
                        .font(.system(.callout, design: .monospaced).bold())
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.white.opacity(0.07))
                .cornerRadius(14)

                // Controlli rapidi principali (Audio, Ruota, Zoom, Schermo Intero)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button {
                        state.audioActive.toggle()
                        state.sendCommand("aud=\(state.audioActive ? "1" : "0")")
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: state.audioActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.title2)
                            BilingualText(
                                it: state.audioActive ? "Audio Attivo" : "Attiva Audio",
                                en: state.audioActive ? "Audio On" : "Enable Audio",
                                itFont: .footnote.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .white.opacity(0.75)
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(state.audioActive ? Color.blue : Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }

                    Button {
                        state.rotation = (state.rotation + 90) % 360
                        state.sendCommand("rot=\(state.rotation)")
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "rotate.right.fill")
                                .font(.title2)
                            BilingualText(
                                it: "Ruota (\(state.rotation)°)",
                                en: "Rotate Screen",
                                itFont: .footnote.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .white.opacity(0.75)
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }

                    Button {
                        state.fitMode = (state.fitMode == "contain") ? "zoom" : "contain"
                        state.sendCommand("fit=\(state.fitMode)")
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: state.fitMode == "zoom" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.title2)
                            BilingualText(
                                it: state.fitMode == "zoom" ? "Zoom Attivo" : "Adatta Schermo",
                                en: state.fitMode == "zoom" ? "Zoomed (118%)" : "Fit Screen",
                                itFont: .footnote.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .white.opacity(0.75)
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(state.fitMode == "zoom" ? Color.purple : Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }

                    Button {
                        state.fullscreenTrigger += 1
                        state.sendCommand("fs=\(state.fullscreenTrigger)")
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                                .font(.title2)
                            BilingualText(
                                it: "Schermo Intero",
                                en: "Toggle Fullscreen",
                                itFont: .footnote.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .white.opacity(0.75)
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                }

                // Selettori Risoluzione, FPS e Velocità
                VStack(spacing: 14) {
                    // Risoluzione
                    HStack {
                        BilingualText(
                            it: "Risoluzione Video",
                            en: "Video Resolution",
                            itFont: .subheadline.bold(),
                            enFont: .caption2,
                            itColor: .white,
                            enColor: .gray,
                            alignment: .leading
                        )
                        Spacer()
                        Picker("", selection: $state.resolution) {
                            ForEach(resolutions, id: \.0) { item in
                                Text(item.1).tag(item.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                        .onChange(of: state.resolution) { newVal in
                            state.sendCommand("res=\(newVal)")
                        }
                    }

                    Divider().background(Color.white.opacity(0.15))

                    // Fluidità FPS
                    HStack {
                        BilingualText(
                            it: "Fluidità (FPS)",
                            en: "Frame Rate",
                            itFont: .subheadline.bold(),
                            enFont: .caption2,
                            itColor: .white,
                            enColor: .gray,
                            alignment: .leading
                        )
                        Spacer()
                        Picker("", selection: $state.fps) {
                            ForEach(fpsOptions, id: \.self) { f in
                                Text("\(f) FPS").tag(f)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                        .onChange(of: state.fps) { newVal in
                            state.sendCommand("fps=\(newVal)")
                        }
                    }

                    Divider().background(Color.white.opacity(0.15))

                    // Velocità
                    HStack {
                        BilingualText(
                            it: "Velocità Flusso",
                            en: "Playback Speed",
                            itFont: .subheadline.bold(),
                            enFont: .caption2,
                            itColor: .white,
                            enColor: .gray,
                            alignment: .leading
                        )
                        Spacer()
                        Picker("", selection: $state.speed) {
                            ForEach(speedOptions, id: \.self) { s in
                                Text("\(s)x").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                        .onChange(of: state.speed) { newVal in
                            state.sendCommand("spd=\(newVal)")
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.07))
                .cornerRadius(16)

                // Pulsante per fermare la trasmissione
                VStack(spacing: 6) {
                    BroadcastPicker()
                        .frame(width: 70, height: 70)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(18)
                    BilingualText(
                        it: "Tocca per interrompere",
                        en: "Tap to stop broadcast",
                        itFont: .caption.bold(),
                        enFont: .caption2,
                        itColor: .red,
                        enColor: .gray
                    )
                }
                .padding(.top, 6)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

struct ContentView: View {
    @State private var ip: String? = localIPAddress()
    @State private var copied = false
    @StateObject private var networkTrigger = LocalNetworkTrigger()
    @StateObject private var remoteState = RemoteState()

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi / No Wi-Fi"
    }

    var body: some View {
        Group {
            if remoteState.isBroadcasting {
                LiveRemoteView(state: remoteState, ipAddress: urlString)
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 16)

                        // Nuovo Logo al posto della scritta
                        BrandLogoView(compact: false)
                            .padding(.bottom, 4)

                        VStack(spacing: 10) {
                            BilingualText(
                                it: "1. Tocca l'icona qui sotto",
                                en: "1. Tap the icon below",
                                itFont: .subheadline.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .gray
                            )
                            BilingualText(
                                it: "2. Scegli "Mirror TV" e premi "Avvia trasmissione"",
                                en: "2. Select "Mirror TV" and tap "Start Broadcast"",
                                itFont: .subheadline.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .gray
                            )
                            BilingualText(
                                it: "3. Sulla TV o PC apri questo indirizzo nel browser:",
                                en: "3. Open this address in your TV or PC browser:",
                                itFont: .subheadline.bold(),
                                enFont: .caption2,
                                itColor: .white,
                                enColor: .gray
                            )
                        }
                        .multilineTextAlignment(.center)

                        BroadcastPicker()
                            .frame(width: 90, height: 90)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(LinearGradient(colors: [.cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                            )

                        Text(urlString)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.cyan)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(14)

                        HStack(spacing: 14) {
                            Button {
                                UIPasteboard.general.string = urlString
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            } label: {
                                BilingualText(
                                    it: copied ? "Copiato!" : "Copia indirizzo",
                                    en: copied ? "Copied!" : "Copy address",
                                    itFont: .footnote.bold(),
                                    enFont: .caption2,
                                    itColor: .white,
                                    enColor: .white.opacity(0.75)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }

                            Button {
                                ip = localIPAddress()
                            } label: {
                                BilingualText(
                                    it: "Aggiorna IP",
                                    en: "Refresh IP",
                                    itFont: .footnote.bold(),
                                    enFont: .caption2,
                                    itColor: .white,
                                    enColor: .white.opacity(0.75)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(10)
                            }
                        }

                        BilingualText(
                            it: "La TV e l'iPhone devono essere sulla stessa rete Wi-Fi.",
                            en: "TV and iPhone must be connected to the same Wi-Fi network.",
                            itFont: .footnote,
                            enFont: .caption2,
                            itColor: .gray,
                            enColor: .gray.opacity(0.7)
                        )
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                        Spacer(minLength: 16)
                    }
                    .padding()
                }
                .background(Color.black.ignoresSafeArea())
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ip = localIPAddress()
            networkTrigger.trigger()
            remoteState.startMonitoring()
        }
        .onDisappear {
            remoteState.stopMonitoring()
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
