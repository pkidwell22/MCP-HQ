import Foundation

public struct DashboardState: Equatable, Sendable {
    public let summary: DashboardSummary
    public let serverRows: [DashboardServerRow]
    public let issueRows: [DashboardIssueRow]

    public init(summary: DashboardSummary, serverRows: [DashboardServerRow], issueRows: [DashboardIssueRow]) {
        self.summary = summary
        self.serverRows = serverRows
        self.issueRows = issueRows
    }
}

public struct DashboardSummary: Equatable, Sendable {
    public let serverCount: Int
    public let sourceCount: Int
    public let issueCount: Int
    public let warningCount: Int
    public let errorCount: Int
    public let statusText: String

    public init(serverCount: Int, sourceCount: Int, issueCount: Int, warningCount: Int, errorCount: Int, statusText: String) {
        self.serverCount = serverCount
        self.sourceCount = sourceCount
        self.issueCount = issueCount
        self.warningCount = warningCount
        self.errorCount = errorCount
        self.statusText = statusText
    }
}

public struct DashboardServerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let transport: MCPTransport
    public let connectionSummary: String
    public let envSummary: String
    public let redactedEnvBindings: [String: String]
    public let sourcePath: String

    public init(
        id: String,
        displayName: String,
        transport: MCPTransport,
        connectionSummary: String,
        envSummary: String,
        redactedEnvBindings: [String: String],
        sourcePath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.connectionSummary = connectionSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourcePath = sourcePath
    }
}

public struct DashboardIssueRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let agentName: String
    public let severityLabel: String
    public let message: String
    public let sourcePath: String

    public init(id: String, agentName: String, severityLabel: String, message: String, sourcePath: String) {
        self.id = id
        self.agentName = agentName
        self.severityLabel = severityLabel
        self.message = message
        self.sourcePath = sourcePath
    }
}

public struct DashboardStateBuilder: Sendable {
    public init() {}

    public func build(from result: ScanResult) -> DashboardState {
        let warningCount = result.issues.filter { $0.severity == .warning }.count
        let errorCount = result.issues.filter { $0.severity == .error }.count
        let summary = DashboardSummary(
            serverCount: result.servers.count,
            sourceCount: result.sources.count,
            issueCount: result.issues.count,
            warningCount: warningCount,
            errorCount: errorCount,
            statusText: statusText(serverCount: result.servers.count, sourceCount: result.sources.count, warningCount: warningCount, errorCount: errorCount)
        )

        let serverRows = result.servers
            .map(makeServerRow)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let issueRows = result.issues.map { issue in
            DashboardIssueRow(
                id: issue.id,
                agentName: issue.source.agent.rawValue,
                severityLabel: issue.severity.rawValue,
                message: issue.message,
                sourcePath: issue.source.path
            )
        }

        return DashboardState(summary: summary, serverRows: serverRows, issueRows: issueRows)
    }

    private func makeServerRow(_ server: ServerDefinition) -> DashboardServerRow {
        DashboardServerRow(
            id: server.id,
            displayName: server.displayName,
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourcePath: server.sourcePath
        )
    }

    private func connectionSummary(for server: ServerDefinition) -> String {
        if let url = server.url, !url.isEmpty {
            return "\(server.transport.rawValue) • \(url)"
        }

        let commandParts = ([server.command].compactMap { $0 } + server.args).filter { !$0.isEmpty }
        if commandParts.isEmpty {
            return server.transport.rawValue
        }
        return "\(server.transport.rawValue) • \(commandParts.joined(separator: " "))"
    }

    private func envSummary(for envBindings: [String: String]) -> String {
        switch envBindings.count {
        case 0:
            return "No env vars"
        case 1:
            return "1 env var"
        default:
            return "\(envBindings.count) env vars"
        }
    }

    private func statusText(serverCount: Int, sourceCount: Int, warningCount: Int, errorCount: Int) -> String {
        if serverCount == 0, sourceCount == 0, warningCount == 0, errorCount == 0 {
            return "No MCP configs found"
        }

        var parts = [
            "\(serverCount) \(serverCount == 1 ? "server" : "servers")",
            "\(sourceCount) \(sourceCount == 1 ? "source" : "sources")",
        ]
        if errorCount > 0 {
            parts.append("\(errorCount) \(errorCount == 1 ? "error" : "errors")")
        }
        if warningCount > 0 {
            parts.append("\(warningCount) \(warningCount == 1 ? "warning" : "warnings")")
        }
        return parts.joined(separator: " • ")
    }
}
