import Foundation

public enum AgentID: String, Codable, Equatable, Sendable {
    case antigravity
    case claude
    case codex
    case gemini
    case hermes
    case opencode
    case pi
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

public enum ConfigSourceState: String, Codable, Equatable, Sendable {
    case missing
    case found
    case parsed
    case unsupported
    case malformed
    case noServers = "no_servers"
}

public struct ConfigSourceHealth: Codable, Equatable, Sendable, Identifiable {
    public var id: String { source.id }
    public let source: ConfigSource
    public let state: ConfigSourceState
    public let serverCount: Int
    public let message: String

    public init(source: ConfigSource, state: ConfigSourceState, serverCount: Int = 0, message: String) {
        self.source = source
        self.state = state
        self.serverCount = serverCount
        self.message = message
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

public struct MCPResourceDetail: Codable, Equatable, Sendable, Identifiable {
    public var id: String { uri }
    public let uri: String
    public let name: String
    public let description: String
    public let mimeType: String

    public init(uri: String, name: String = "", description: String = "", mimeType: String = "") {
        self.uri = SecretRedactor.redactText(uri.trimmingCharacters(in: .whitespacesAndNewlines))
        self.name = SecretRedactor.redactText(name.trimmingCharacters(in: .whitespacesAndNewlines))
        self.description = SecretRedactor.redactText(description.trimmingCharacters(in: .whitespacesAndNewlines))
        self.mimeType = SecretRedactor.redactText(mimeType.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct MCPPromptDetail: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let argumentSummary: String

    public init(name: String, description: String = "", argumentSummary: String = "") {
        self.name = SecretRedactor.redactText(name.trimmingCharacters(in: .whitespacesAndNewlines))
        self.description = SecretRedactor.redactText(description.trimmingCharacters(in: .whitespacesAndNewlines))
        self.argumentSummary = SecretRedactor.redactText(argumentSummary.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct MCPProbeResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { serverID }
    public let serverID: String
    public let status: MCPProbeStatus
    public let toolCount: Int?
    public let toolNames: [String]
    public let toolDetails: [MCPToolDetail]
    public let resourceCount: Int?
    public let resourceNames: [String]
    public let resourceDetails: [MCPResourceDetail]
    public let pingSucceeded: Bool?
    public let promptCount: Int?
    public let promptNames: [String]
    public let promptDetails: [MCPPromptDetail]
    public let message: String

    public init(
        serverID: String,
        status: MCPProbeStatus,
        toolCount: Int? = nil,
        toolNames: [String] = [],
        toolDetails: [MCPToolDetail] = [],
        resourceCount: Int? = nil,
        resourceNames: [String] = [],
        resourceDetails: [MCPResourceDetail] = [],
        pingSucceeded: Bool? = nil,
        promptCount: Int? = nil,
        promptNames: [String] = [],
        promptDetails: [MCPPromptDetail] = [],
        message: String
    ) {
        self.serverID = serverID
        self.status = status
        self.toolCount = toolCount
        self.toolNames = toolNames
            .map { SecretRedactor.redactText($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        self.toolDetails = toolDetails.filter { !$0.name.isEmpty }
        self.resourceCount = resourceCount
        self.resourceNames = resourceNames
            .map { SecretRedactor.redactText($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        self.resourceDetails = resourceDetails.filter { !$0.uri.isEmpty }
        self.pingSucceeded = pingSucceeded
        self.promptCount = promptCount
        self.promptNames = promptNames
            .map { SecretRedactor.redactText($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        self.promptDetails = promptDetails.filter { !$0.name.isEmpty }
        self.message = message
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let servers: [ServerDefinition]
    public let sources: [ConfigSource]
    public let sourceHealth: [ConfigSourceHealth]
    public let issues: [ScanIssue]
    public let processes: [MCPProcessSnapshot]
    public let processMatches: [ServerProcessMatch]
    public let probeResults: [MCPProbeResult]

    public init(
        servers: [ServerDefinition],
        sources: [ConfigSource],
        sourceHealth: [ConfigSourceHealth] = [],
        issues: [ScanIssue] = [],
        processes: [MCPProcessSnapshot] = [],
        processMatches: [ServerProcessMatch] = [],
        probeResults: [MCPProbeResult] = []
    ) {
        self.servers = servers
        self.sources = sources
        self.sourceHealth = sourceHealth
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
        var sourceHealth: [ConfigSourceHealth] = []
        var issues: [ScanIssue] = []

        for source in configSources {
            guard FileManager.default.fileExists(atPath: source.path) else {
                sourceHealth.append(ConfigSourceHealth(
                    source: source,
                    state: .missing,
                    message: "\(AgentRegistry.displayName(for: source.agent)) config missing"
                ))
                continue
            }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
                try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
                let parser = AgentConfigParser()
                guard parser.supports(source.agent) else {
                    issues.append(ScanIssue(
                        source: source,
                        severity: .warning,
                        message: "Unsupported agent config parser: \(source.agent.rawValue)"
                    ))
                    sourceHealth.append(ConfigSourceHealth(
                        source: source,
                        state: .unsupported,
                        message: "Found config • parser not implemented"
                    ))
                    seenSources.append(source)
                    continue
                }
                let parsed = try parser.parse(data: data, source: source)
                servers.append(contentsOf: parsed)
                seenSources.append(source)
                sourceHealth.append(ConfigSourceHealth(
                    source: source,
                    state: parsed.isEmpty ? .noServers : .parsed,
                    serverCount: parsed.count,
                    message: parsed.isEmpty ? "Found config • no MCP servers" : "Found config • parsed \(parsed.count) \(parsed.count == 1 ? "server" : "servers")"
                ))
            } catch {
                issues.append(ScanIssue(
                    source: source,
                    severity: .error,
                    message: String(describing: error)
                ))
                sourceHealth.append(ConfigSourceHealth(
                    source: source,
                    state: .malformed,
                    message: "Found config • malformed: \(String(describing: error))"
                ))
            }
        }

        return ScanResult(servers: servers, sources: seenSources, sourceHealth: sourceHealth, issues: issues)
    }
}
