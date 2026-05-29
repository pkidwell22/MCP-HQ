import Foundation

public enum AgentID: String, Codable, Equatable, Sendable {
    case claude
    case gemini
    case hermes
    case unknown
}

public struct ConfigSource: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(agent.rawValue):\(path)" }
    public let agent: AgentID
    public let path: String

    public init(agent: AgentID, path: String) {
        self.agent = agent
        self.path = path
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let servers: [ServerDefinition]
    public let sources: [ConfigSource]

    public init(servers: [ServerDefinition], sources: [ConfigSource]) {
        self.servers = servers
        self.sources = sources
    }
}

public struct ConfigScanner: Sendable {
    private let configSources: [ConfigSource]

    public init(configSources: [ConfigSource]) {
        self.configSources = configSources
    }

    public func scan() throws -> ScanResult {
        var servers: [ServerDefinition] = []
        var seenSources: [ConfigSource] = []

        for source in configSources {
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
            let parsed: [ServerDefinition]
            switch source.agent {
            case .claude:
                parsed = try ClaudeConfigParser().parse(data: data, sourcePath: source.path)
            case .gemini, .hermes, .unknown:
                parsed = []
            }
            servers.append(contentsOf: parsed)
            seenSources.append(source)
        }

        return ScanResult(servers: servers, sources: seenSources)
    }
}
