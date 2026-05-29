import Foundation

public struct DashboardState: Equatable, Sendable {
    public let summary: DashboardSummary
    public let serverRows: [DashboardServerRow]
    public let processRows: [DashboardProcessRow]
    public let issueRows: [DashboardIssueRow]

    public init(summary: DashboardSummary, serverRows: [DashboardServerRow], processRows: [DashboardProcessRow], issueRows: [DashboardIssueRow]) {
        self.summary = summary
        self.serverRows = serverRows
        self.processRows = processRows
        self.issueRows = issueRows
    }
}

public struct DashboardSummary: Equatable, Sendable {
    public let serverCount: Int
    public let processCount: Int
    public let sourceCount: Int
    public let issueCount: Int
    public let warningCount: Int
    public let errorCount: Int
    public let statusText: String

    public init(serverCount: Int, processCount: Int, sourceCount: Int, issueCount: Int, warningCount: Int, errorCount: Int, statusText: String) {
        self.serverCount = serverCount
        self.processCount = processCount
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
    public let processSummary: String
    public let toolSummary: String
    public let envSummary: String
    public let redactedEnvBindings: [String: String]
    public let sourcePath: String

    public init(
        id: String,
        displayName: String,
        transport: MCPTransport,
        connectionSummary: String,
        processSummary: String = "No running process matched",
        toolSummary: String = "Probe not run",
        envSummary: String,
        redactedEnvBindings: [String: String],
        sourcePath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.connectionSummary = connectionSummary
        self.processSummary = processSummary
        self.toolSummary = toolSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourcePath = sourcePath
    }
}

public struct DashboardProcessRow: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let pid: Int32
    public let executableName: String
    public let commandLine: String
    public let matchReason: String

    public init(id: Int32, pid: Int32, executableName: String, commandLine: String, matchReason: String) {
        self.id = id
        self.pid = pid
        self.executableName = executableName
        self.commandLine = commandLine
        self.matchReason = matchReason
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
            processCount: result.processes.count,
            sourceCount: result.sources.count,
            issueCount: result.issues.count,
            warningCount: warningCount,
            errorCount: errorCount,
            statusText: statusText(
                serverCount: result.servers.count,
                processCount: result.processes.count,
                sourceCount: result.sources.count,
                warningCount: warningCount,
                errorCount: errorCount
            )
        )

        let matchesByServer = Dictionary(grouping: result.processMatches, by: \.serverID)
        let probesByServer = Dictionary(uniqueKeysWithValues: result.probeResults.map { ($0.serverID, $0) })
        let serverRows = result.servers
            .map { makeServerRow($0, matches: matchesByServer[$0.id] ?? [], probe: probesByServer[$0.id]) }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let processRows = result.processes
            .map(makeProcessRow)
            .sorted { $0.pid < $1.pid }

        let issueRows = result.issues.map { issue in
            DashboardIssueRow(
                id: issue.id,
                agentName: issue.source.agent.rawValue,
                severityLabel: issue.severity.rawValue,
                message: issue.message,
                sourcePath: issue.source.path
            )
        }

        return DashboardState(summary: summary, serverRows: serverRows, processRows: processRows, issueRows: issueRows)
    }

    private func makeServerRow(_ server: ServerDefinition, matches: [ServerProcessMatch], probe: MCPProbeResult?) -> DashboardServerRow {
        DashboardServerRow(
            id: server.id,
            displayName: server.displayName,
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            processSummary: processSummary(for: matches),
            toolSummary: toolSummary(for: probe),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourcePath: server.sourcePath
        )
    }

    private func makeProcessRow(_ process: MCPProcessSnapshot) -> DashboardProcessRow {
        DashboardProcessRow(
            id: process.id,
            pid: process.pid,
            executableName: process.executableName,
            commandLine: process.commandLine,
            matchReason: process.matchReason
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

    private func processSummary(for matches: [ServerProcessMatch]) -> String {
        let sortedMatches = matches.sorted { lhs, rhs in
            if lhs.confidence.rawValue != rhs.confidence.rawValue { return lhs.confidence.rawValue < rhs.confidence.rawValue }
            return lhs.processID < rhs.processID
        }
        switch sortedMatches.count {
        case 0:
            return "No running process matched"
        case 1:
            let match = sortedMatches[0]
            return "Matched pid \(match.processID) • \(match.confidence.rawValue)"
        default:
            let pids = sortedMatches.map { String($0.processID) }.joined(separator: ", ")
            return "Matched pids \(pids)"
        }
    }

    private func toolSummary(for probe: MCPProbeResult?) -> String {
        guard let probe else { return "Probe not run" }
        let status = probe.status.rawValue.capitalized
        guard let toolCount = probe.toolCount else { return "\(status) • tool count unknown" }
        return "\(status) • \(toolCount) \(toolCount == 1 ? "tool" : "tools")"
    }

    private func statusText(serverCount: Int, processCount: Int, sourceCount: Int, warningCount: Int, errorCount: Int) -> String {
        if serverCount == 0, processCount == 0, sourceCount == 0, warningCount == 0, errorCount == 0 {
            return "No MCP configs found"
        }

        var parts = [
            "\(serverCount) \(serverCount == 1 ? "server" : "servers")",
            "\(processCount) \(processCount == 1 ? "process" : "processes")",
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
