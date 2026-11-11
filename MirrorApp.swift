import SwiftUI
import ReplayKit

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

struct ContentView: View {
    @State private var ip: String? = localIPAddress()
    @State private var copied = false

    var urlString: String {
        if let ip { return "http://\(ip):8080" }
        return "Nessun Wi-Fi trovato"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 56))
                .foregroundColor(.blue)

            Text("Mirror TV")
                .font(.largeTitle).bold()

            VStack(spacing: 8) {
                Text("1. Tocca l'icona qui sotto")
                Text("2. Scegli \"Mirror TV\" e premi \"Avvia trasmissione\"")
                Text("3. Sulla TV apri questo indirizzo nel browser:")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            BroadcastPicker()
                .frame(width: 90, height: 90)
                .background(Color(.systemGray6))
                .cornerRadius(20)

            Text(urlString)
                .font(.system(.title3, design: .monospaced))
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)

            HStack(spacing: 16) {
                Button(copied ? "Copiato" : "Copia indirizzo") {
                    UIPasteboard.general.string = urlString
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.bordered)

                Button("Aggiorna IP") {
                    ip = localIPAddress()
                }
                .buttonStyle(.bordered)
            }

            Text("La TV e l'iPhone devono essere sulla stessa rete Wi-Fi.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear { ip = localIPAddress() }
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
