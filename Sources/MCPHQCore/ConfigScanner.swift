import Foundation

public enum AgentID: String, Codable, Equatable, Sendable {
    case claude
    case gemini
    case hermes
    case cursor
    case windsurf
    case `continue`
    case goose
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

public enum MCPProbeStatus: String, Codable, Equatable, Sendable {
    case healthy
    case warning
    case error
    case skipped
}

public struct MCPToolDetail: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchemaSummary: String

    public init(name: String, description: String = "", inputSchemaSummary: String = "") {
        self.name = SecretRedactor.redactText(name.trimmingCharacters(in: .whitespacesAndNewlines))
        self.description = SecretRedactor.redactText(description.trimmingCharacters(in: .whitespacesAndNewlines))
        self.inputSchemaSummary = SecretRedactor.redactText(inputSchemaSummary.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct MCPProbeResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { serverID }
    public let serverID: String
    public let status: MCPProbeStatus
    public let toolCount: Int?
    public let toolNames: [String]
    public let toolDetails: [MCPToolDetail]
    public let message: String

    public init(serverID: String, status: MCPProbeStatus, toolCount: Int? = nil, toolNames: [String] = [], toolDetails: [MCPToolDetail] = [], message: String) {
        self.serverID = serverID
        self.status = status
        self.toolCount = toolCount
        self.toolNames = toolNames
            .map { SecretRedactor.redactText($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        self.toolDetails = toolDetails.filter { !$0.name.isEmpty }
        self.message = message
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let servers: [ServerDefinition]
    public let sources: [ConfigSource]
    public let issues: [ScanIssue]
    public let processes: [MCPProcessSnapshot]
    public let processMatches: [ServerProcessMatch]
    public let probeResults: [MCPProbeResult]

    public init(
        servers: [ServerDefinition],
        sources: [ConfigSource],
        issues: [ScanIssue] = [],
        processes: [MCPProcessSnapshot] = [],
        processMatches: [ServerProcessMatch] = [],
        probeResults: [MCPProbeResult] = []
    ) {
        self.servers = servers
        self.sources = sources
        self.issues = issues
        self.processes = processes
        self.processMatches = processMatches
        self.probeResults = probeResults
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
                try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
                let parsed: [ServerDefinition]
                switch source.agent {
                case .claude:
                    parsed = try ClaudeConfigParser().parse(data: data, sourcePath: source.path)
                case .gemini:
                    parsed = try GeminiConfigParser().parse(data: data, sourcePath: source.path)
                case .hermes:
                    parsed = try HermesConfigParser().parse(data: data, sourcePath: source.path)
                case .cursor, .windsurf, .continue, .goose, .unknown:
                    parsed = []
                    issues.append(ScanIssue(
                        source: source,
                        severity: .warning,
                        message: "Unsupported agent config parser: \(source.agent.rawValue)"
                    ))
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
