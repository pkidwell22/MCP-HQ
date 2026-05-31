import Darwin
import Foundation

public enum LocalControlLoopbackHTTPServerError: Error, CustomStringConvertible, Sendable {
    case socketFailed(String)
    case bindFailed(String)
    case listenFailed(String)
    case portLookupFailed(String)
    case alreadyRunning
    case notRunning

    public var description: String {
        switch self {
        case .socketFailed(let message):
            return "Could not create local control socket: \(message)"
        case .bindFailed(let message):
            return "Could not bind local control socket: \(message)"
        case .listenFailed(let message):
            return "Could not listen on local control socket: \(message)"
        case .portLookupFailed(let message):
            return "Could not read local control socket port: \(message)"
        case .alreadyRunning:
            return "Local control server is already running"
        case .notRunning:
            return "Local control server is not running"
        }
    }
}

public final class LocalControlLoopbackHTTPServer: @unchecked Sendable {
    private let adapter: LocalControlHTTPAdapter
    private let preferredPort: UInt16
    private let lock = NSLock()
    private var listenSocket: Int32 = -1
    private var thread: Thread?

    public private(set) var port: UInt16 = 0

    public var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    public init(adapter: LocalControlHTTPAdapter = LocalControlHTTPAdapter(), preferredPort: UInt16 = 0) {
        self.adapter = adapter
        self.preferredPort = preferredPort
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenSocket < 0 else { throw LocalControlLoopbackHTTPServerError.alreadyRunning }

        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw LocalControlLoopbackHTTPServerError.socketFailed(Self.errnoText()) }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(preferredPort).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = Self.errnoText()
            close(socketFD)
            throw LocalControlLoopbackHTTPServerError.bindFailed(message)
        }

        guard listen(socketFD, SOMAXCONN) == 0 else {
            let message = Self.errnoText()
            close(socketFD)
            throw LocalControlLoopbackHTTPServerError.listenFailed(message)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(socketFD, sockaddrPointer, &boundLength)
            }
        }
        guard nameResult == 0 else {
            let message = Self.errnoText()
            close(socketFD)
            throw LocalControlLoopbackHTTPServerError.portLookupFailed(message)
        }

        listenSocket = socketFD
        port = UInt16(bigEndian: boundAddress.sin_port)
        let worker = Thread { [weak self] in
            self?.acceptLoop(socketFD: socketFD)
        }
        worker.name = "MCP-HQ Local Control HTTP"
        thread = worker
        worker.start()
    }

    public func stop() {
        lock.lock()
        let socketFD = listenSocket
        listenSocket = -1
        port = 0
        let worker = thread
        thread = nil
        lock.unlock()

        worker?.cancel()
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
        }
    }

    private func acceptLoop(socketFD: Int32) {
        while !Thread.current.isCancelled {
            let clientFD = accept(socketFD, nil, nil)
            if clientFD < 0 {
                if errno == EBADF || errno == EINVAL { break }
                continue
            }
            handle(clientFD: clientFD)
            close(clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        let response: LocalControlHTTPResponse
        do {
            let request = try readRequest(clientFD: clientFD)
            response = adapter.handle(request)
        } catch {
            response = LocalControlHTTPResponse(
                statusCode: 400,
                headers: ["Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store"],
                body: Data("Bad Request".utf8)
            )
        }
        write(response: response, clientFD: clientFD)
    }

    private func readRequest(clientFD: Int32) throws -> LocalControlHTTPRequest {
        var buffer = Data()
        let headerSeparator = Data("\r\n\r\n".utf8)

        while buffer.range(of: headerSeparator) == nil {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = recv(clientFD, &chunk, chunk.count, 0)
            guard count > 0 else { throw LocalControlLoopbackHTTPServerError.notRunning }
            buffer.append(contentsOf: chunk.prefix(count))
            if buffer.count > 1_048_576 {
                throw LocalControlLoopbackHTTPServerError.bindFailed("request headers too large")
            }
        }

        guard let headerRange = buffer.range(of: headerSeparator),
              let headerText = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) else {
            throw LocalControlLoopbackHTTPServerError.bindFailed("invalid request headers")
        }

        let parsed = parseHeaders(headerText)
        let contentLength = parsed.headers.first { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }
            .flatMap { Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let bodyStart = headerRange.upperBound
        while buffer.count - bodyStart < contentLength {
            var chunk = [UInt8](repeating: 0, count: min(4096, contentLength - (buffer.count - bodyStart)))
            let count = recv(clientFD, &chunk, chunk.count, 0)
            guard count > 0 else { throw LocalControlLoopbackHTTPServerError.notRunning }
            buffer.append(contentsOf: chunk.prefix(count))
        }

        let bodyEnd = bodyStart + contentLength
        return LocalControlHTTPRequest(
            method: parsed.method,
            path: parsed.path,
            headers: parsed.headers,
            body: Data(buffer[bodyStart..<bodyEnd])
        )
    }

    private func parseHeaders(_ text: String) -> (method: String, path: String, headers: [String: String]) {
        let lines = text.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ", maxSplits: 2).map(String.init)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: separator)
            headers[name] = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rawPath = requestParts.count > 1 ? requestParts[1] : "/"
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return (method: requestParts.first ?? "", path: path, headers: headers)
    }

    private func write(response: LocalControlHTTPResponse, clientFD: Int32) {
        let reason = Self.reasonPhrase(for: response.statusCode)
        var headerLines = [
            "HTTP/1.1 \(response.statusCode) \(reason)",
            "Content-Length: \(response.body.count)",
            "Connection: close",
        ]
        headerLines.append(contentsOf: response.headers.map { "\($0.key): \($0.value)" }.sorted())
        var payload = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        payload.append(response.body)
        payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let count = send(clientFD, baseAddress.advanced(by: sent), payload.count - sent, 0)
                if count <= 0 { break }
                sent += count
            }
        }
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized"
        case 404:
            return "Not Found"
        case 405:
            return "Method Not Allowed"
        default:
            return "HTTP"
        }
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
