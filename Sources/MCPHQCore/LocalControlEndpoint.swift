import Darwin
import Foundation
import Security

public struct LocalControlEndpoint: Codable, Equatable, Sendable {
    public let baseURL: String
    public let controlPath: String
    public let token: String?
    public let pid: Int32
    public let startedAt: Date

    public var controlURL: URL {
        controlPath
            .split(separator: "/")
            .reduce(URL(string: baseURL)!) { url, component in
                url.appendingPathComponent(String(component))
            }
    }

    public init(
        baseURL: String,
        controlPath: String = LocalControlHTTPAdapter.controlPath,
        token: String?,
        pid: Int32 = getpid(),
        startedAt: Date = Date()
    ) {
        self.baseURL = baseURL
        self.controlPath = controlPath
        self.token = token
        self.pid = pid
        self.startedAt = startedAt
    }
}

public struct LocalControlEndpointStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func defaultStore(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> LocalControlEndpointStore {
        LocalControlEndpointStore(fileURL: homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MCP-HQ", isDirectory: true)
            .appendingPathComponent("control-endpoint.json"))
    }

    public func save(_ endpoint: LocalControlEndpoint) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(endpoint)
        try data.write(to: fileURL, options: [.atomic])
        chmod(fileURL.path, S_IRUSR | S_IWUSR)
    }

    public func load() throws -> LocalControlEndpoint {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LocalControlEndpoint.self, from: data)
    }

    public func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

public struct LocalControlTokenGenerator: Sendable {
    public init() {}

    public func generate(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: max(16, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

public final class LocalControlServerRuntime: @unchecked Sendable {
    public let server: LocalControlLoopbackHTTPServer
    public let endpoint: LocalControlEndpoint
    private let endpointStore: LocalControlEndpointStore

    init(server: LocalControlLoopbackHTTPServer, endpoint: LocalControlEndpoint, endpointStore: LocalControlEndpointStore) {
        self.server = server
        self.endpoint = endpoint
        self.endpointStore = endpointStore
    }

    public func stop() {
        server.stop()
        try? endpointStore.remove()
    }
}

public struct LocalControlServerLauncher: Sendable {
    private let endpointStore: LocalControlEndpointStore
    private let tokenGenerator: LocalControlTokenGenerator
    private let clientFactory: @Sendable () -> LocalControlInProcessClient
    private let now: @Sendable () -> Date

    public init(
        endpointStore: LocalControlEndpointStore = .defaultStore(),
        tokenGenerator: LocalControlTokenGenerator = LocalControlTokenGenerator(),
        clientFactory: @escaping @Sendable () -> LocalControlInProcessClient = {
            let store = try? SQLiteScanHistoryStore.applicationSupport()
            let healthCacheStore = try? JSONHealthCacheStore.applicationSupport()
            let supervisor = HubRuntimeSupervisor(controlPlaneStore: store)
            return LocalControlInProcessClient(router: LocalControlRouter(
                runtimeSupervisor: supervisor,
                controlPlaneStore: store,
                healthCacheStore: healthCacheStore
            ))
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.endpointStore = endpointStore
        self.tokenGenerator = tokenGenerator
        self.clientFactory = clientFactory
        self.now = now
    }

    public func start(port: UInt16 = 0, token: String? = nil, requiresToken: Bool = true) throws -> LocalControlServerRuntime {
        let effectiveToken = requiresToken ? (token ?? tokenGenerator.generate()) : nil
        let adapter = LocalControlHTTPAdapter(client: clientFactory(), authToken: effectiveToken)
        let server = LocalControlLoopbackHTTPServer(adapter: adapter, preferredPort: port)
        try server.start()
        let endpoint = LocalControlEndpoint(
            baseURL: server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: effectiveToken,
            pid: getpid(),
            startedAt: now()
        )
        try endpointStore.save(endpoint)
        return LocalControlServerRuntime(server: server, endpoint: endpoint, endpointStore: endpointStore)
    }
}
