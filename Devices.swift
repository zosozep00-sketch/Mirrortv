import SwiftUI
import ReplayKit
import UIKit

// MARK: - Modello dei dispositivi (salvato in UserDefaults)

enum DeviceKind: String, Codable {
    case samsung
    case roku
    case chromecast
    case unknown

    var title: String {
        switch self {
        case .samsung: return "Samsung TV"
        case .roku: return "Roku"
        case .chromecast: return "Chromecast"
        case .unknown: return "Dispositivo"
        }
    }

    var icon: String {
        switch self {
        case .samsung: return "tv"
        case .roku: return "tv.and.mediabox"
        case .chromecast: return "wifi"
        case .unknown: return "tv"
        }
    }

    // Per ora solo le Samsung (Tizen) si comandano da qui
    var canAutoConnect: Bool { return self == .samsung }
}

struct SavedDevice: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var ip: String
    var kind: DeviceKind
    var lastSeen = Date()
    var lastConnected: Date?
    var token: String?
}

struct FoundDevice {
    let ip: String
    let name: String
    let kind: DeviceKind
}

struct InfoMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Collegamento alla TV Samsung (WebSocket Tizen)

enum LaunchResult {
    case ok(token: String?)
    case failed(String)
}

final class SamsungLauncher: NSObject, URLSessionDelegate {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var done = false
    private var sent = false
    private var triedPlain = false
    private var completion: ((LaunchResult) -> Void)?
    private var token: String?
    private var ip = ""
    private var pageURL = ""

    func launch(ip: String, token: String?, pageURL: String, completion: @escaping (LaunchResult) -> Void) {
        self.ip = ip
        self.token = token
        self.pageURL = pageURL
        self.completion = completion
        connect(secure: true)
        // La prima volta la TV chiede il consenso: lascio tempo per rispondere
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.finish(.failed("La TV non ha risposto in tempo. Controlla che sia accesa e, se compare una richiesta, scegli «Consenti»."))
        }
    }

    private func connect(secure: Bool) {
        let name = Data("MirrorTV".utf8).base64EncodedString()
        var s = secure ? "wss://\(ip):8002" : "ws://\(ip):8001"
        s += "/api/v2/channels/samsung.remote.control?name=\(name)"
        if let t = token, !t.isEmpty { s += "&token=\(t)" }
        guard let url = URL(string: s) else {
            finish(.failed("Indirizzo della TV non valido."))
            return
        }
        session?.invalidateAndCancel()
        let sess = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: OperationQueue.main)
        session = sess
        let t = sess.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t, secure: secure)
    }

    private func receive(_ t: URLSessionWebSocketTask, secure: Bool) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !self.done, t === self.task else { return }
                switch result {
                case .failure(let error):
                    if secure && !self.triedPlain && !self.sent {
                        self.triedPlain = true
                        self.connect(secure: false)
                    } else {
                        self.finish(.failed("Non riesco a collegarmi alla TV (\(error.localizedDescription))."))
                    }
                case .success(let message):
                    var text: String?
                    switch message {
                    case .string(let s): text = s
                    case .data(let d): text = String(data: d, encoding: .utf8)
                    @unknown default: break
                    }
                    self.handle(text)
                    if !self.done { self.receive(t, secure: secure) }
                }
            }
        }
    }

    private func handle(_ text: String?) {
        guard let text = text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }

        switch event {
        case "ms.channel.connect":
            if let d = json["data"] as? [String: Any], let tk = d["token"] {
                token = "\(tk)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self, !self.sent else { return }
                self.sendLaunch()
            }
        case "ms.channel.ready":
            if !sent { sendLaunch() }
        case "ms.channel.unauthorized":
            finish(.failed("La TV ha rifiutato la richiesta. Sulla TV scegli «Consenti» quando compare il messaggio."))
        case "ms.channel.timeOut":
            finish(.failed("Nessuna risposta dalla TV alla richiesta di consenso."))
        default:
            break
        }
    }

    private func sendLaunch() {
        sent = true
        let payload: [String: Any] = [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": [
                    "action_type": "NATIVE_LAUNCH",
                    "appId": "org.tizen.browser",
                    "metaTag": pageURL
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else {
            finish(.failed("Errore nel comando per la TV."))
            return
        }
        task?.send(.string(str)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.finish(.failed("Invio del comando alla TV non riuscito (\(error.localizedDescription))."))
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.finish(.ok(token: self.token))
                    }
                }
            }
        }
    }

    private func finish(_ result: LaunchResult) {
        guard !done else { return }
        done = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        let c = completion
        completion = nil
        c?(result)
    }

    // La TV usa un certificato proprio: lo accetto solo per questo collegamento
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Gestione elenco, ricerca e collegamento

final class DeviceManager: ObservableObject {
    @Published private(set) var devices: [SavedDevice] = []
    @Published private(set) var live: Set<String> = []
    @Published private(set) var scanning = false
    @Published private(set) var triggerCount = 0
    @Published private(set) var connectedID: UUID?
    @Published var status: String?
    @Published var info: InfoMessage?

    private let storeKey = "devices.v1"
    private var pendingID: UUID?
    private var attempt = 0
    private var launcher: SamsungLauncher?

    init() {
        load()
        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.captureChanged()
        }
    }

    // MARK: Elenchi per la schermata

    // Il dispositivo collegato in questo momento
    var current: SavedDevice? {
        guard let id = connectedID else { return nil }
        return devices.first(where: { $0.id == id })
    }

    // Cronologia: dispositivi collegati in passato, l'ultimo in alto
    var history: [SavedDevice] {
        return devices
            .filter { $0.lastConnected != nil && $0.id != connectedID }
            .sorted { ($0.lastConnected ?? Date.distantPast) > ($1.lastConnected ?? Date.distantPast) }
    }

    var nearby: [SavedDevice] {
        return devices
            .filter { $0.lastConnected == nil && live.contains($0.ip) }
            .sorted { $0.name < $1.name }
    }

    var saved: [SavedDevice] {
        return devices
            .filter { $0.lastConnected == nil && !live.contains($0.ip) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Salvataggio

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([SavedDevice].self, from: data) else { return }
        devices = list
        prune()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    // Dispositivi mai usati e non visti da 14 giorni spariscono da soli
    private func prune() {
        let now = Date()
        devices.removeAll { $0.lastConnected == nil && now.timeIntervalSince($0.lastSeen) > 14 * 86400 }
    }

    func remove(_ d: SavedDevice) {
        devices.removeAll { $0.id == d.id }
        if connectedID == d.id { connectedID = nil }
        save()
    }

    // Svuota la cronologia: i dispositivi restano salvati, ma senza data di collegamento
    func clearHistory() {
        for i in devices.indices where devices[i].id != connectedID {
            devices[i].lastConnected = nil
        }
        prune()
        save()
    }

    private func markConnected(_ id: UUID, token: String? = nil) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[i].lastConnected = Date()
        devices[i].lastSeen = Date()
        if let t = token, !t.isEmpty { devices[i].token = t }
        save()
    }

    // MARK: Ricerca in rete

    func scan() {
        if scanning { return }
        guard let ip = localIPAddress() else {
            status = "Nessun Wi-Fi / No Wi-Fi"
            return
        }
        let parts = ip.split(separator: ".")
        guard parts.count == 4, let own = Int(parts[3]) else { return }
        let prefix = parts[0...2].joined(separator: ".")

        scanning = true
        Task {
            let found = await DeviceManager.scanSubnet(prefix: prefix, own: own)
            await MainActor.run {
                self.merge(found, fullScan: true)
                self.scanning = false
            }
        }
    }

    private func merge(_ found: [FoundDevice], fullScan: Bool) {
        let now = Date()
        let foundIPs = Set(found.map { $0.ip })
        if fullScan { live = foundIPs } else { live.formUnion(foundIPs) }

        for f in found {
            // Prima per indirizzo; se il router ha cambiato indirizzo, riconosco la TV dal nome
            let index = devices.firstIndex(where: { $0.ip == f.ip })
                ?? devices.firstIndex(where: { $0.kind == f.kind && $0.name == f.name && !foundIPs.contains($0.ip) })
            if let i = index {
                devices[i].ip = f.ip
                devices[i].name = f.name
                devices[i].kind = f.kind
                devices[i].lastSeen = now
            } else {
                devices.append(SavedDevice(name: f.name, ip: f.ip, kind: f.kind, lastSeen: now))
            }
        }
        prune()
        save()
    }

    func addManual(_ raw: String) {
        let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = ip.split(separator: ".")
        let valid = parts.count == 4 && parts.allSatisfy { p in
            if let n = Int(p) { return n >= 0 && n <= 255 }
            return false
        }
        guard valid else {
            info = InfoMessage(title: "Indirizzo non valido",
                               message: "Scrivi un indirizzo come 192.168.1.20")
            return
        }
        Task {
            let found = await DeviceManager.probeHost(ip)
            await MainActor.run {
                if let f = found {
                    self.merge([f], fullScan: false)
                } else if !self.devices.contains(where: { $0.ip == ip }) {
                    self.devices.append(SavedDevice(name: "Dispositivo \(ip)", ip: ip, kind: .unknown))
                    self.save()
                }
            }
        }
    }

    // MARK: Collegamento

    private func pageAddress() -> String {
        if let ip = localIPAddress() { return "http://\(ip):8080" }
        return "(nessun Wi-Fi)"
    }

    func tap(_ d: SavedDevice) {
        attempt += 1
        let mine = attempt

        if !d.kind.canAutoConnect {
            let address = pageAddress()
            UIPasteboard.general.string = address
            markConnected(d.id)
            info = InfoMessage(
                title: d.name,
                message: "Questo tipo di dispositivo non si comanda da qui. Avvia la trasmissione con il pulsante qui sopra e apri sul dispositivo questo indirizzo (l'ho copiato):\n\n\(address)")
            return
        }

        pendingID = d.id
        if UIScreen.main.isCaptured {
            scheduleLaunch(d.id, mine)
        } else {
            status = "Tocca «Avvia trasmissione» nella finestra che si apre…"
            triggerCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                guard let self = self, self.attempt == mine, self.pendingID != nil else { return }
                self.pendingID = nil
                self.status = nil
            }
        }
    }

    private func captureChanged() {
        // Se la trasmissione si ferma, il dispositivo non è più collegato
        if !UIScreen.main.isCaptured {
            connectedID = nil
            return
        }
        guard let id = pendingID else { return }
        pendingID = nil
        scheduleLaunch(id, attempt)
    }

    private func scheduleLaunch(_ id: UUID, _ mine: Int) {
        status = "Trasmissione avviata. Apro la pagina sulla TV…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.attempt == mine,
                  let d = self.devices.first(where: { $0.id == id }) else { return }
            self.launchBrowser(on: d)
        }
    }

    private func launchBrowser(on d: SavedDevice) {
        guard let myIP = localIPAddress() else {
            status = nil
            info = InfoMessage(title: "Nessun Wi-Fi", message: "Collega il telefono alla stessa rete della TV.")
            return
        }
        let address = "http://\(myIP):8080"
        connectedID = nil
        status = "Sto collegando \(d.name)… Se sulla TV compare una richiesta, scegli «Consenti»."

        let l = SamsungLauncher()
        launcher = l
        l.launch(ip: d.ip, token: d.token, pageURL: address) { [weak self] result in
            guard let self = self else { return }
            self.launcher = nil
            switch result {
            case .ok(let token):
                self.markConnected(d.id, token: token)
                self.connectedID = d.id
                self.status = "Collegato a \(d.name)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    self?.status = nil
                }
            case .failed(let reason):
                self.status = nil
                UIPasteboard.general.string = address
                self.info = InfoMessage(
                    title: "Collegamento non riuscito",
                    message: "\(reason)\n\nPuoi aprire a mano sulla TV questo indirizzo (l'ho copiato):\n\(address)")
            }
        }
    }

    // MARK: Ricerca: sonde sulla rete

    private static let probeSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 1.5
        c.timeoutIntervalForResource = 3
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func scanSubnet(prefix: String, own: Int) async -> [FoundDevice] {
        let hosts = (1...254).filter { $0 != own }.map { "\(prefix).\($0)" }
        var results: [FoundDevice] = []
        var start = 0
        while start < hosts.count {
            let chunk = Array(hosts[start..<min(start + 64, hosts.count)])
            start += 64
            let part = await withTaskGroup(of: FoundDevice?.self) { group -> [FoundDevice] in
                for h in chunk {
                    group.addTask { await DeviceManager.probeHost(h) }
                }
                var out: [FoundDevice] = []
                for await r in group {
                    if let r = r { out.append(r) }
                }
                return out
            }
            results.append(contentsOf: part)
        }
        return results
    }

    static func probeHost(_ ip: String) async -> FoundDevice? {
        async let samsung = probeSamsung(ip)
        async let roku = probeRoku(ip)
        async let cast = probeChromecast(ip)
        let s = await samsung
        let r = await roku
        let c = await cast
        return s ?? r ?? c
    }

    private static func fetch(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await probeSession.data(from: url)
            if (resp as? HTTPURLResponse)?.statusCode == 200 { return data }
        } catch {}
        return nil
    }

    private static func probeSamsung(_ ip: String) async -> FoundDevice? {
        guard let data = await fetch("http://\(ip):8001/api/v2/"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dev = json["device"] as? [String: Any] else { return nil }
        var name = "Samsung TV"
        if let n = dev["name"] as? String, !n.isEmpty { name = n }
        return FoundDevice(ip: ip, name: name, kind: .samsung)
    }

    private static func probeRoku(_ ip: String) async -> FoundDevice? {
        guard let data = await fetch("http://\(ip):8060/query/device-info"),
              let text = String(data: data, encoding: .utf8),
              text.contains("device-info") else { return nil }
        var name = "Roku"
        if let a = text.range(of: "<friendly-device-name>"),
           let b = text.range(of: "</friendly-device-name>"),
           a.upperBound <= b.lowerBound {
            let n = String(text[a.upperBound..<b.lowerBound])
            if !n.isEmpty { name = n }
        }
        return FoundDevice(ip: ip, name: name, kind: .roku)
    }

    private static func probeChromecast(_ ip: String) async -> FoundDevice? {
        guard let data = await fetch("http://\(ip):8008/setup/eureka_info?params=name"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty else { return nil }
        return FoundDevice(ip: ip, name: name, kind: .chromecast)
    }
}

// MARK: - Pulsante di trasmissione "premuto" da codice

struct HiddenBroadcastTrigger: UIViewRepresentable {
    var count: Int

    final class Coordinator { var last = 0 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.example.mirrortvb.ext"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        guard context.coordinator.last != count else { return }
        context.coordinator.last = count
        guard count > 0 else { return }
        DispatchQueue.main.async {
            if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
                button.sendActions(for: .touchUpInside)
            }
        }
    }
}

// MARK: - Schermata: sezione Dispositivi

struct DevicesSection: View {
    @StateObject private var manager = DeviceManager()
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                BilingualLabel(it: "Dispositivi", en: "Devices", font: .headline, alignment: .leading)
                Spacer()
                if manager.scanning { ProgressView() }
                Button { manager.scan() } label: {
                    Image(systemName: "arrow.clockwise").font(.title3)
                }
                .disabled(manager.scanning)
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle").font(.title3)
                }
            }

            if let s = manager.status {
                Text(s)
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
            }

            if let c = manager.current {
                group(it: "Connesso ora", en: "Connected now", list: [c], connected: true)
            }
            group(it: "Cronologia", en: "History", list: manager.history, canClear: true)
            group(it: "Nella rete", en: "On the network", list: manager.nearby)
            group(it: "Salvati", en: "Saved", list: manager.saved)

            if manager.devices.isEmpty && !manager.scanning {
                Text("Nessun dispositivo trovato. Premi ↻ per cercare di nuovo o + per aggiungerlo con l'indirizzo IP.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HiddenBroadcastTrigger(count: manager.triggerCount)
                .frame(width: 44, height: 44)
                .opacity(0.01)
                .allowsHitTesting(false)
        )
        .onAppear { manager.scan() }
        .sheet(isPresented: $showAdd) {
            AddDeviceSheet(onAdd: { ip in
                showAdd = false
                manager.addManual(ip)
            }, onCancel: { showAdd = false })
        }
        .alert(item: $manager.info) { m in
            Alert(title: Text(m.title), message: Text(m.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func group(it: String, en: String, list: [SavedDevice],
                       connected: Bool = false, canClear: Bool = false) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    BilingualLabel(it: it, en: en, font: .caption.bold(), color: .secondary, alignment: .leading)
                    Spacer()
                    if canClear {
                        Button(role: .destructive) { manager.clearHistory() } label: {
                            Text("Svuota / Clear").font(.caption.bold())
                        }
                    }
                }
                ForEach(list) { d in
                    row(d, connected: connected)
                }
            }
        }
    }

    private func row(_ d: SavedDevice, connected: Bool = false) -> some View {
        Button { manager.tap(d) } label: {
            HStack(spacing: 10) {
                Image(systemName: d.kind.icon)
                    .foregroundColor(.blue)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.subheadline.bold()).lineLimit(1)
                    Text("\(d.kind.title) · \(d.ip)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if connected {
                        Text("Connesso / Connected")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    } else if let last = d.lastConnected {
                        Text("Ultimo collegamento: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if connected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Circle()
                        .fill(manager.live.contains(d.ip) ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(10)
            .background(connected ? Color.green.opacity(0.15) : Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { manager.remove(d) } label: {
                Label("Rimuovi / Remove", systemImage: "trash")
            }
        }
    }
}

struct AddDeviceSheet: View {
    var onAdd: (String) -> Void
    var onCancel: () -> Void
    @State private var text = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Indirizzo IP del dispositivo / Device IP address")) {
                    TextField("192.168.1.20", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Aggiungi / Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Aggiungi") { onAdd(text) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
