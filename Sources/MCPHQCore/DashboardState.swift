import Foundation

public struct DashboardState: Equatable, Sendable {
    public let summary: DashboardSummary
    public let serverRows: [DashboardServerRow]
    public let serverDetails: [DashboardServerDetail]
    public let processRows: [DashboardProcessRow]
    public let issueRows: [DashboardIssueRow]

    public init(
        summary: DashboardSummary,
        serverRows: [DashboardServerRow],
        serverDetails: [DashboardServerDetail] = [],
        processRows: [DashboardProcessRow],
        issueRows: [DashboardIssueRow]
    ) {
        self.summary = summary
        self.serverRows = serverRows
        self.serverDetails = serverDetails
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
    public let healthSummary: String
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
        healthSummary: String = "MCP ping not checked",
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
        self.healthSummary = healthSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourcePath = sourcePath
    }
}

public struct DashboardServerDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let transport: MCPTransport
    public let connectionSummary: String
    public let processSummary: String
    public let toolSummary: String
    public let healthSummary: String
    public let envSummary: String
    public let redactedEnvBindings: [String: String]
    public let sourcePath: String
    public let toolNames: [String]
    public let toolDetails: [MCPToolDetail]
    public let resourceSummary: String
    public let resourceNames: [String]
    public let resourceDetails: [MCPResourceDetail]
    public let promptSummary: String
    public let promptNames: [String]
    public let promptDetails: [MCPPromptDetail]
    public let processRows: [DashboardProcessRow]
    public let issueRows: [DashboardIssueRow]

    public init(
        id: String,
        displayName: String,
        transport: MCPTransport,
        connectionSummary: String,
        processSummary: String,
        toolSummary: String,
        healthSummary: String = "MCP ping not checked",
        envSummary: String,
        redactedEnvBindings: [String: String],
        sourcePath: String,
        toolNames: [String] = [],
        toolDetails: [MCPToolDetail] = [],
        resourceSummary: String = "Resources not probed",
        resourceNames: [String] = [],
        resourceDetails: [MCPResourceDetail] = [],
        promptSummary: String = "Prompts not probed",
        promptNames: [String] = [],
        promptDetails: [MCPPromptDetail] = [],
        processRows: [DashboardProcessRow],
        issueRows: [DashboardIssueRow]
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.connectionSummary = connectionSummary
        self.processSummary = processSummary
        self.toolSummary = toolSummary
        self.healthSummary = healthSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourcePath = sourcePath
        self.toolNames = toolNames
        self.toolDetails = toolDetails
        self.resourceSummary = resourceSummary
        self.resourceNames = resourceNames
        self.resourceDetails = resourceDetails
        self.promptSummary = promptSummary
        self.promptNames = promptNames
        self.promptDetails = promptDetails
        self.processRows = processRows
        self.issueRows = issueRows
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

public struct StatusMenuSnapshot: Equatable, Sendable {
    public let title: String
    public let summaryText: String
    public let detailText: String
    public let systemImage: String
    public let probeActionTitle: String
    public let canRunProbes: Bool

    public init(state: DashboardState, isProbing: Bool) {
        let summary = state.summary
        self.title = "MCP-HQ"
        self.summaryText = [
            Self.countText(summary.serverCount, singular: "server", plural: "servers"),
            Self.countText(summary.processCount, singular: "process", plural: "processes"),
        ].joined(separator: " • ")

        var details = [Self.countText(summary.sourceCount, singular: "source", plural: "sources")]
        if summary.errorCount > 0 {
            details.append(Self.countText(summary.errorCount, singular: "error", plural: "errors"))
        }
        if summary.warningCount > 0 {
            details.append(Self.countText(summary.warningCount, singular: "warning", plural: "warnings"))
        }
        if summary.errorCount == 0, summary.warningCount == 0 {
            details.append("No issues")
        }
        self.detailText = details.joined(separator: " • ")

        if summary.errorCount > 0 {
            self.systemImage = "exclamationmark.octagon.fill"
        } else if summary.warningCount > 0 {
            self.systemImage = "exclamationmark.triangle.fill"
        } else {
            self.systemImage = "network"
        }

        self.probeActionTitle = isProbing ? "Probing…" : "Run Probes"
        self.canRunProbes = !isProbing
    }

    private static func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
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

        let issueRows = result.issues.map(makeIssueRow)

        let processesByPID = Dictionary(uniqueKeysWithValues: result.processes.map { ($0.pid, $0) })
        let issuesBySourcePath = Dictionary(grouping: issueRows, by: \.sourcePath)
        let sourceServerCounts = Dictionary(grouping: result.servers, by: \.sourcePath).mapValues(\.count)
        let serverDetails = result.servers
            .map { server in
                makeServerDetail(
                    server,
                    matches: matchesByServer[server.id] ?? [],
                    processesByPID: processesByPID,
                    probe: probesByServer[server.id],
                    issueRows: filteredIssueRows(
                        for: server,
                        sourceServerCount: sourceServerCounts[server.sourcePath] ?? 0,
                        issueRows: issuesBySourcePath[server.sourcePath] ?? []
                    )
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        return DashboardState(
            summary: summary,
            serverRows: serverRows,
            serverDetails: serverDetails,
            processRows: processRows,
            issueRows: issueRows
        )
    }

    private func makeServerRow(_ server: ServerDefinition, matches: [ServerProcessMatch], probe: MCPProbeResult?) -> DashboardServerRow {
        DashboardServerRow(
            id: server.id,
            displayName: server.displayName,
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            processSummary: processSummary(for: matches),
            toolSummary: toolSummary(for: probe),
            healthSummary: healthSummary(for: probe),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourcePath: server.sourcePath
        )
    }

    private func makeServerDetail(
        _ server: ServerDefinition,
        matches: [ServerProcessMatch],
        processesByPID: [Int32: MCPProcessSnapshot],
        probe: MCPProbeResult?,
        issueRows: [DashboardIssueRow]
    ) -> DashboardServerDetail {
        let matchedProcessRows = matches
            .compactMap { processesByPID[$0.processID] }
            .map(makeProcessRow)
            .sorted { $0.pid < $1.pid }

        return DashboardServerDetail(
            id: server.id,
            displayName: server.displayName,
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            processSummary: processSummary(for: matches),
            toolSummary: toolSummary(for: probe),
            healthSummary: healthSummary(for: probe),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourcePath: server.sourcePath,
            toolNames: probe?.toolNames ?? [],
            toolDetails: probe?.toolDetails ?? [],
            resourceSummary: resourceSummary(for: probe),
            resourceNames: probe?.resourceNames ?? [],
            resourceDetails: probe?.resourceDetails ?? [],
            promptSummary: promptSummary(for: probe),
            promptNames: probe?.promptNames ?? [],
            promptDetails: probe?.promptDetails ?? [],
            processRows: matchedProcessRows,
            issueRows: issueRows
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

    private func makeIssueRow(_ issue: ScanIssue) -> DashboardIssueRow {
        DashboardIssueRow(
            id: issue.id,
            agentName: issue.source.agent.rawValue,
            severityLabel: issue.severity.rawValue,
            message: issue.message,
            sourcePath: issue.source.path
        )
    }

    private func filteredIssueRows(for server: ServerDefinition, sourceServerCount: Int, issueRows: [DashboardIssueRow]) -> [DashboardIssueRow] {
        if sourceServerCount <= 1 { return issueRows }
        let id = server.id.lowercased()
        let displayName = server.displayName.lowercased()
        return issueRows.filter { issue in
            let message = issue.message.lowercased()
            return message.contains(id) || message.contains(displayName)
        }
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

    private func healthSummary(for probe: MCPProbeResult?) -> String {
        guard let probe else { return "MCP ping not checked" }
        guard let pingSucceeded = probe.pingSucceeded else { return "MCP ping not checked" }
        return pingSucceeded ? "MCP ping ok" : "MCP ping failed"
    }

    private func resourceSummary(for probe: MCPProbeResult?) -> String {
        guard let probe else { return "Resources not probed" }
        guard let resourceCount = probe.resourceCount else { return "Resources not probed" }
        return "\(resourceCount) \(resourceCount == 1 ? "resource" : "resources")"
    }

    private func promptSummary(for probe: MCPProbeResult?) -> String {
        guard let probe else { return "Prompts not probed" }
        guard let promptCount = probe.promptCount else { return "Prompts not probed" }
        return "\(promptCount) \(promptCount == 1 ? "prompt" : "prompts")"
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
