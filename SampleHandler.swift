import ReplayKit
import CoreImage
import ImageIO
import Darwin

// Piccolo server HTTP che trasmette lo schermo come flusso MJPEG
final class MJPEGServer {
    private var listenFD: Int32 = -1
    private var clients: [Int32] = []
    private var busy = false
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "mirrortv.send")

    var hasClients: Bool {
        lock.lock(); defer { lock.unlock() }
        return !clients.isEmpty
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
        let all = clients
        clients.removeAll()
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
        } else {
            let html = "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Mirror TV</title></head><body style=\"margin:0;background:#000\"><img src=\"/stream\" style=\"width:100vw;height:100vh;object-fit:contain\"></body></html>"
            let body = Data(html.utf8)
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

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        server.start(port: 8080)
    }

    override func broadcastFinished() {
        server.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, server.hasClients else { return }

        // Circa 12 fotogrammi al secondo
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame >= 0.08 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now

        var image = CIImage(cvPixelBuffer: pixelBuffer)

        if let number = CMGetAttachment(sampleBuffer,
                                        key: RPVideoSampleOrientationKey as CFString,
                                        attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) {
            image = image.oriented(orientation)
        }

        let longest = max(image.extent.width, image.extent.height)
        let scale = min(1.0, 1280.0 / longest)
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
}
