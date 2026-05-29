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

public enum ScanIssueSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public struct ScanIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: ConfigSource
    public let severity: ScanIssueSeverity
    public let message: String

    public init(source: ConfigSource, severity: ScanIssueSeverity, message: String) {
        self.source = source
        self.severity = severity
        self.message = message
        self.id = "\(source.id):\(severity.rawValue):\(message)"
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let servers: [ServerDefinition]
    public let sources: [ConfigSource]
    public let issues: [ScanIssue]

    public init(servers: [ServerDefinition], sources: [ConfigSource], issues: [ScanIssue] = []) {
        self.servers = servers
        self.sources = sources
        self.issues = issues
    }
}

public struct ConfigScanner: Sendable {
    private let configSources: [ConfigSource]

    public init(configSources: [ConfigSource]) {
        self.configSources = configSources
    }

    public func scan() -> ScanResult {
        var servers: [ServerDefinition] = []
        var seenSources: [ConfigSource] = []
        var issues: [ScanIssue] = []

        for source in configSources {
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            do {
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
            } catch {
                issues.append(ScanIssue(
                    source: source,
                    severity: .error,
                    message: String(describing: error)
                ))
            }
        }

        return ScanResult(servers: servers, sources: seenSources, issues: issues)
    }
}
