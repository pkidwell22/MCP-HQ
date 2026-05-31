import Foundation

public struct DashboardState: Equatable, Sendable {
    public let summary: DashboardSummary
    public let serverRows: [DashboardServerRow]
    public let serverSections: [DashboardServerSection]
    public let serverDetails: [DashboardServerDetail]
    public let sourceRows: [DashboardSourceRow]
    public let processRows: [DashboardProcessRow]
    public let issueRows: [DashboardIssueRow]
    public let keychainRecoveryRows: [DashboardKeychainRecoveryRow]

    public init(
        summary: DashboardSummary,
        serverRows: [DashboardServerRow],
        serverSections: [DashboardServerSection] = [],
        serverDetails: [DashboardServerDetail] = [],
        sourceRows: [DashboardSourceRow] = [],
        processRows: [DashboardProcessRow],
        issueRows: [DashboardIssueRow],
        keychainRecoveryRows: [DashboardKeychainRecoveryRow] = []
    ) {
        self.summary = summary
        self.serverRows = serverRows
        self.serverSections = serverSections
        self.serverDetails = serverDetails
        self.sourceRows = sourceRows
        self.processRows = processRows
        self.issueRows = issueRows
        self.keychainRecoveryRows = keychainRecoveryRows
    }
}

public struct DashboardSummary: Equatable, Sendable {
    public let serverCount: Int
    public let processCount: Int
    public let sourceCount: Int
    public let issueCount: Int
    public let warningCount: Int
    public let errorCount: Int
    public let keychainRecoveryCount: Int
    public let statusText: String

    public init(
        serverCount: Int,
        processCount: Int,
        sourceCount: Int,
        issueCount: Int,
        warningCount: Int,
        errorCount: Int,
        keychainRecoveryCount: Int = 0,
        statusText: String
    ) {
        self.serverCount = serverCount
        self.processCount = processCount
        self.sourceCount = sourceCount
        self.issueCount = issueCount
        self.warningCount = warningCount
        self.errorCount = errorCount
        self.keychainRecoveryCount = keychainRecoveryCount
        self.statusText = statusText
    }
}

public struct DashboardServerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let agentName: String
    public let transport: MCPTransport
    public let connectionSummary: String
    public let processSummary: String
    public let toolSummary: String
    public let healthSummary: String
    public let envSummary: String
    public let redactedEnvBindings: [String: String]
    public let sourceID: String
    public let sourcePath: String

    public init(
        id: String,
        displayName: String,
        agentName: String = "Unknown",
        transport: MCPTransport,
        connectionSummary: String,
        processSummary: String = "No running process matched",
        toolSummary: String = "Probe not run",
        healthSummary: String = "MCP ping not checked",
        envSummary: String,
        redactedEnvBindings: [String: String],
        sourceID: String = "",
        sourcePath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.agentName = agentName
        self.transport = transport
        self.connectionSummary = connectionSummary
        self.processSummary = processSummary
        self.toolSummary = toolSummary
        self.healthSummary = healthSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourceID = sourceID
        self.sourcePath = sourcePath
    }
}

public struct DashboardServerSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let agentName: String
    public let sourcePath: String
    public let serverRows: [DashboardServerRow]

    public init(id: String, agentName: String, sourcePath: String, serverRows: [DashboardServerRow]) {
        self.id = id
        self.agentName = agentName
        self.sourcePath = sourcePath
        self.serverRows = serverRows
    }
}

public struct DashboardServerDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let agentName: String
    public let transport: MCPTransport
    public let connectionSummary: String
    public let processSummary: String
    public let toolSummary: String
    public let healthSummary: String
    public let envSummary: String
    public let redactedEnvBindings: [String: String]
    public let sourceID: String
    public let sourcePath: String
    public let toolNames: [String]
    public let toolDetails: [MCPToolDetail]
    public let resourceSummary: String
    public let resourceNames: [String]
    public let resourceDetails: [MCPResourceDetail]
    public let promptSummary: String
    public let promptNames: [String]
    public let promptDetails: [MCPPromptDetail]
    public let secretRows: [DashboardSecretRow]
    public let processRows: [DashboardProcessRow]
    public let issueRows: [DashboardIssueRow]

    public init(
        id: String,
        displayName: String,
        agentName: String = "Unknown",
        transport: MCPTransport,
        connectionSummary: String,
        processSummary: String,
        toolSummary: String,
        healthSummary: String = "MCP ping not checked",
        envSummary: String,
        redactedEnvBindings: [String: String],
        sourceID: String = "",
        sourcePath: String,
        toolNames: [String] = [],
        toolDetails: [MCPToolDetail] = [],
        resourceSummary: String = "Resources not probed",
        resourceNames: [String] = [],
        resourceDetails: [MCPResourceDetail] = [],
        promptSummary: String = "Prompts not probed",
        promptNames: [String] = [],
        promptDetails: [MCPPromptDetail] = [],
        secretRows: [DashboardSecretRow] = [],
        processRows: [DashboardProcessRow],
        issueRows: [DashboardIssueRow]
    ) {
        self.id = id
        self.displayName = displayName
        self.agentName = agentName
        self.transport = transport
        self.connectionSummary = connectionSummary
        self.processSummary = processSummary
        self.toolSummary = toolSummary
        self.healthSummary = healthSummary
        self.envSummary = envSummary
        self.redactedEnvBindings = redactedEnvBindings
        self.sourceID = sourceID
        self.sourcePath = sourcePath
        self.toolNames = toolNames
        self.toolDetails = toolDetails
        self.resourceSummary = resourceSummary
        self.resourceNames = resourceNames
        self.resourceDetails = resourceDetails
        self.promptSummary = promptSummary
        self.promptNames = promptNames
        self.promptDetails = promptDetails
        self.secretRows = secretRows
        self.processRows = processRows
        self.issueRows = issueRows
    }
}

public struct DashboardSecretRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let fieldLabel: String
    public let name: String
    public let statusLabel: String
    public let redactedValue: String
    public let replacementValue: String

    public init(id: String, fieldLabel: String, name: String, statusLabel: String, redactedValue: String, replacementValue: String) {
        self.id = id
        self.fieldLabel = fieldLabel
        self.name = name
        self.statusLabel = statusLabel
        self.redactedValue = redactedValue
        self.replacementValue = replacementValue
    }
}

public struct DashboardSourceRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let agentName: String
    public let stateLabel: String
    public let serverCount: Int
    public let message: String
    public let sourcePath: String

    public init(id: String, agentName: String, stateLabel: String, serverCount: Int, message: String, sourcePath: String) {
        self.id = id
        self.agentName = agentName
        self.stateLabel = stateLabel
        self.serverCount = serverCount
        self.message = message
        self.sourcePath = sourcePath
    }
}

public struct DashboardProcessRow: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let pid: Int32
    public let executableName: String
    public let commandLine: String
    public let matchReason: String
    public let ownership: RuntimeOwnership
    public let cpuPercent: Double?
    public let memoryBytes: UInt64?

    public var ownershipLabel: String { ownership.displayLabel }

    public var resourceSummary: String {
        var parts: [String] = []
        if let cpuPercent {
            parts.append(String(format: "CPU %.1f%%", cpuPercent))
        }
        if let memoryBytes {
            parts.append("Memory \(Self.memoryText(bytes: memoryBytes))")
        }
        return parts.isEmpty ? "CPU/memory unavailable" : parts.joined(separator: " • ")
    }

    public init(
        id: Int32,
        pid: Int32,
        executableName: String,
        commandLine: String,
        matchReason: String,
        ownership: RuntimeOwnership = .unknown,
        cpuPercent: Double? = nil,
        memoryBytes: UInt64? = nil
    ) {
        self.id = id
        self.pid = pid
        self.executableName = executableName
        self.commandLine = commandLine
        self.matchReason = matchReason
        self.ownership = ownership
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    private static func memoryText(bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
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

public struct DashboardKeychainRecoveryRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let serverName: String
    public let fieldLabel: String
    public let fieldName: String
    public let statusLabel: String
    public let summary: String
    public let guidance: String
    public let sourcePath: String
    public let referenceLabel: String
    public let previousStatus: String?
    public let validatedAt: Date?
    public let primaryActionTitle: String
    public let secondaryActionTitle: String
    public let reviewActionTitle: String
    public let supportsMigrationCleanup: Bool

    public init(
        id: String,
        serverName: String,
        fieldLabel: String,
        fieldName: String,
        statusLabel: String,
        summary: String,
        guidance: String,
        sourcePath: String,
        referenceLabel: String,
        previousStatus: String?,
        validatedAt: Date?,
        primaryActionTitle: String = "Review Config",
        secondaryActionTitle: String = "Rerun Validation",
        reviewActionTitle: String = "Open Migration Review",
        supportsMigrationCleanup: Bool = false
    ) {
        self.id = id
        self.serverName = SecretRedactor.redactText(serverName)
        self.fieldLabel = fieldLabel
        self.fieldName = SecretRedactor.redactText(fieldName)
        self.statusLabel = statusLabel
        self.summary = SecretRedactor.redactText(summary)
        self.guidance = SecretRedactor.redactText(guidance)
        self.sourcePath = SecretRedactor.redactText(sourcePath)
        self.referenceLabel = SecretRedactor.redactText(referenceLabel)
        self.previousStatus = previousStatus.map(SecretRedactor.redactText)
        self.validatedAt = validatedAt
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.reviewActionTitle = reviewActionTitle
        self.supportsMigrationCleanup = supportsMigrationCleanup
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
        if summary.keychainRecoveryCount > 0 {
            details.append(Self.countText(summary.keychainRecoveryCount, singular: "Keychain issue", plural: "Keychain issues"))
        }
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

    public func build(from result: ScanResult, secretRecoveryReport: SecretRecoveryReport? = nil) -> DashboardState {
        let keychainRecoveryRows = makeKeychainRecoveryRows(from: secretRecoveryReport)
        let keychainRecoveryIssueCount = keychainRecoveryRows.count
        let probeWarningCount = result.probeResults.filter { $0.status == .warning }.count
        let probeErrorCount = result.probeResults.filter { $0.status == .error }.count
        let warningCount = result.issues.filter { $0.severity == .warning }.count + probeWarningCount + keychainRecoveryIssueCount
        let errorCount = result.issues.filter { $0.severity == .error }.count + probeErrorCount
        let issueCount = result.issues.count + probeWarningCount + probeErrorCount + keychainRecoveryIssueCount
        let sourceCount = result.sourceHealth.isEmpty ? result.sources.count : result.sourceHealth.count
        let summary = DashboardSummary(
            serverCount: result.servers.count,
            processCount: result.processes.count,
            sourceCount: sourceCount,
            issueCount: issueCount,
            warningCount: warningCount,
            errorCount: errorCount,
            keychainRecoveryCount: keychainRecoveryIssueCount,
            statusText: statusText(
                serverCount: result.servers.count,
                processCount: result.processes.count,
                sourceCount: sourceCount,
                warningCount: warningCount,
                errorCount: errorCount
            )
        )

        let matchesByServer = Dictionary(grouping: result.processMatches, by: \.serverID)
        let probesByServer = Dictionary(result.probeResults.map { ($0.serverID, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceLookup = sourceLookup(from: result)
        let serverRows = result.servers
            .map { makeServerRow($0, sourceLookup: sourceLookup, matches: matchesByServer[$0.id] ?? [], probe: probesByServer[$0.id]) }
            .sorted { lhs, rhs in
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        let serverSections = makeServerSections(from: serverRows)

        let ownershipByPID = ownershipLookup(from: result.processMatches)
        let processRows = result.processes
            .map { makeProcessRow($0, ownership: ownershipByPID[$0.pid] ?? .unknown) }
            .sorted { $0.pid < $1.pid }

        let issueRows = result.issues.map(makeIssueRow)
        let sourceRows = makeSourceRows(from: result)

        let processesByPID = Dictionary(uniqueKeysWithValues: result.processes.map { ($0.pid, $0) })
        let issuesBySourcePath = Dictionary(grouping: issueRows, by: \.sourcePath)
        let sourceServerCounts = Dictionary(grouping: result.servers, by: \.sourcePath).mapValues(\.count)
        let serverDetails = result.servers
            .map { server in
                makeServerDetail(
                    server,
                    sourceLookup: sourceLookup,
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
            serverSections: serverSections,
            serverDetails: serverDetails,
            sourceRows: sourceRows,
            processRows: processRows,
            issueRows: issueRows,
            keychainRecoveryRows: keychainRecoveryRows
        )
    }

    private func makeKeychainRecoveryRows(from report: SecretRecoveryReport?) -> [DashboardKeychainRecoveryRow] {
        guard let report else { return [] }
        return report.recoverableStates.map { state in
            let actionTitles = keychainRecoveryActionTitles(for: state.recoveryStatus)
            return DashboardKeychainRecoveryRow(
                id: state.id,
                serverName: state.serverName ?? "Unknown server",
                fieldLabel: state.fieldKind == .environment ? "Environment" : "Header",
                fieldName: state.fieldName,
                statusLabel: keychainRecoveryStatusLabel(for: state.recoveryStatus),
                summary: state.summary,
                guidance: keychainRecoveryGuidance(for: state),
                sourcePath: state.sourcePath,
                referenceLabel: "keychain://\(state.reference.service)/\(state.reference.account)",
                previousStatus: state.previousStatus,
                validatedAt: state.validatedAt,
                primaryActionTitle: actionTitles.primary,
                secondaryActionTitle: actionTitles.secondary,
                reviewActionTitle: actionTitles.review,
                supportsMigrationCleanup: state.recoveryStatus == .migrationWriteFailed
            )
        }
        .sorted { lhs, rhs in
            if lhs.statusLabel != rhs.statusLabel { return lhs.statusLabel < rhs.statusLabel }
            if lhs.serverName != rhs.serverName {
                return lhs.serverName.localizedCaseInsensitiveCompare(rhs.serverName) == .orderedAscending
            }
            return lhs.fieldName.localizedCaseInsensitiveCompare(rhs.fieldName) == .orderedAscending
        }
    }

    private func keychainRecoveryStatusLabel(for status: SecretRecoveryStatus) -> String {
        switch status {
        case .present:
            return "Present"
        case .missing:
            return "Missing"
        case .inaccessible:
            return "Inaccessible"
        case .migrationWriteFailed:
            return "Migration write failed"
        }
    }

    private func keychainRecoveryActionTitles(for status: SecretRecoveryStatus) -> (primary: String, secondary: String, review: String) {
        switch status {
        case .present:
            return ("Review Config", "Rerun Validation", "Open Migration Review")
        case .missing:
            return ("Review Config", "Rerun Validation", "Open Migration Review")
        case .inaccessible:
            return ("Review Access", "Rerun Validation", "Open Migration Review")
        case .migrationWriteFailed:
            return ("Review Failed Migration", "Rerun After Fix", "Open Secret Review")
        }
    }

    private func keychainRecoveryGuidance(for state: SecretRecoveryState) -> String {
        switch state.recoveryStatus {
        case .present:
            return "No recovery action is needed."
        case .missing:
            return "Review the config or open migration review before changing anything. MCP-HQ can confirm the Keychain item is missing, but it cannot recover an unknown secret value; re-enter the credential and migrate or store it back to Keychain only if the server still needs it."
        case .inaccessible:
            return "Review the config, unlock Keychain and grant access, then rerun validation. MCP-HQ only checks presence and never reads or displays the secret value; if access cannot be restored, re-enter the credential and migrate or store it back to Keychain."
        case .migrationWriteFailed:
            return "A guarded migration could not finish writing to Keychain. MCP-HQ should have left or restored config files and removed partial Keychain writes; rerun migration only after fixing Keychain access, and do not paste plaintext secrets into config."
        }
    }

    private struct SourceDisplay {
        let id: String
        let agentName: String
    }

    private func sourceLookup(from result: ScanResult) -> [String: SourceDisplay] {
        var lookup: [String: SourceDisplay] = [:]
        for health in result.sourceHealth {
            lookup[health.source.path] = SourceDisplay(
                id: health.source.id,
                agentName: AgentRegistry.displayName(for: health.source.agent)
            )
        }
        for source in result.sources where lookup[source.path] == nil {
            lookup[source.path] = SourceDisplay(
                id: source.id,
                agentName: AgentRegistry.displayName(for: source.agent)
            )
        }
        return lookup
    }

    private func makeServerSections(from rows: [DashboardServerRow]) -> [DashboardServerSection] {
        let groups = Dictionary(grouping: rows) { row in
            row.sourceID.isEmpty ? row.sourcePath : row.sourceID
        }
        return groups.keys.sorted { lhs, rhs in
            let left = groups[lhs]?.first
            let right = groups[rhs]?.first
            if left?.agentName != right?.agentName {
                return (left?.agentName ?? "").localizedCaseInsensitiveCompare(right?.agentName ?? "") == .orderedAscending
            }
            return (left?.sourcePath ?? "").localizedCaseInsensitiveCompare(right?.sourcePath ?? "") == .orderedAscending
        }.compactMap { id in
            guard let rows = groups[id], let first = rows.first else { return nil }
            return DashboardServerSection(
                id: id,
                agentName: first.agentName,
                sourcePath: first.sourcePath,
                serverRows: rows
            )
        }
    }

    private func makeSourceRows(from result: ScanResult) -> [DashboardSourceRow] {
        if !result.sourceHealth.isEmpty {
            return result.sourceHealth.map { health in
                DashboardSourceRow(
                    id: health.id,
                    agentName: AgentRegistry.displayName(for: health.source.agent),
                    stateLabel: sourceStateLabel(health.state),
                    serverCount: health.serverCount,
                    message: health.message,
                    sourcePath: health.source.path
                )
            }
        }

        let sourceServerCounts = Dictionary(grouping: result.servers, by: \.sourcePath).mapValues(\.count)
        return result.sources.map { source in
            let count = sourceServerCounts[source.path] ?? 0
            return DashboardSourceRow(
                id: source.id,
                agentName: AgentRegistry.displayName(for: source.agent),
                stateLabel: count == 0 ? "Found" : "Parsed",
                serverCount: count,
                message: count == 0 ? "Found config" : "Found config • parsed \(count) \(count == 1 ? "server" : "servers")",
                sourcePath: source.path
            )
        }
    }

    private func sourceStateLabel(_ state: ConfigSourceState) -> String {
        switch state {
        case .missing:
            return "Missing"
        case .found:
            return "Found"
        case .parsed:
            return "Parsed"
        case .unsupported:
            return "Unsupported"
        case .malformed:
            return "Malformed"
        case .noServers:
            return "No servers"
        }
    }

    private func makeServerRow(
        _ server: ServerDefinition,
        sourceLookup: [String: SourceDisplay],
        matches: [ServerProcessMatch],
        probe: MCPProbeResult?
    ) -> DashboardServerRow {
        let source = sourceLookup[server.sourcePath]
        return DashboardServerRow(
            id: server.id,
            displayName: server.displayName,
            agentName: source?.agentName ?? "Unknown",
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            processSummary: processSummary(for: matches),
            toolSummary: toolSummary(for: probe),
            healthSummary: healthSummary(for: probe),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourceID: source?.id ?? server.sourcePath,
            sourcePath: server.sourcePath
        )
    }

    private func makeServerDetail(
        _ server: ServerDefinition,
        sourceLookup: [String: SourceDisplay],
        matches: [ServerProcessMatch],
        processesByPID: [Int32: MCPProcessSnapshot],
        probe: MCPProbeResult?,
        issueRows: [DashboardIssueRow]
    ) -> DashboardServerDetail {
        let source = sourceLookup[server.sourcePath]
        let matchedProcessRows = matches
            .compactMap { match -> DashboardProcessRow? in
                guard let process = processesByPID[match.processID] else { return nil }
                return makeProcessRow(process, ownership: match.ownership)
            }
            .sorted { $0.pid < $1.pid }

        return DashboardServerDetail(
            id: server.id,
            displayName: server.displayName,
            agentName: source?.agentName ?? "Unknown",
            transport: server.transport,
            connectionSummary: connectionSummary(for: server),
            processSummary: processSummary(for: matches),
            toolSummary: toolSummary(for: probe),
            healthSummary: healthSummary(for: probe),
            envSummary: envSummary(for: server.envBindings),
            redactedEnvBindings: server.redactedEnvBindings,
            sourceID: source?.id ?? server.sourcePath,
            sourcePath: server.sourcePath,
            toolNames: probe?.toolNames ?? [],
            toolDetails: probe?.toolDetails ?? [],
            resourceSummary: resourceSummary(for: probe),
            resourceNames: probe?.resourceNames ?? [],
            resourceDetails: probe?.resourceDetails ?? [],
            promptSummary: promptSummary(for: probe),
            promptNames: probe?.promptNames ?? [],
            promptDetails: probe?.promptDetails ?? [],
            secretRows: secretRows(for: server),
            processRows: matchedProcessRows,
            issueRows: issueRows
        )
    }

    private func secretRows(for server: ServerDefinition) -> [DashboardSecretRow] {
        let detectedRows = SecretDetector().detect(in: server).map { detected in
            DashboardSecretRow(
                id: detected.id,
                fieldLabel: detected.location.field == .environment ? "Environment" : "Header",
                name: detected.location.name,
                statusLabel: "Literal secret",
                redactedValue: detected.redactedValue,
                replacementValue: detected.replacementValue
            )
        }

        let envReferenceRows = server.envBindings.keys.sorted().compactMap { key -> DashboardSecretRow? in
            guard let value = server.envBindings[key],
                  let reference = KeychainSecretReference.parse(from: value) else { return nil }
            return DashboardSecretRow(
                id: "\(server.id):env-reference:\(key)",
                fieldLabel: "Environment",
                name: key,
                statusLabel: "Keychain reference",
                redactedValue: "keychain://\(reference.service)/\(reference.account)",
                replacementValue: reference.configValue
            )
        }

        let headerReferenceRows = server.headers.keys.sorted().compactMap { key -> DashboardSecretRow? in
            guard let value = server.headers[key],
                  let reference = KeychainSecretReference.parse(from: value) else { return nil }
            return DashboardSecretRow(
                id: "\(server.id):header-reference:\(key)",
                fieldLabel: "Header",
                name: key,
                statusLabel: "Keychain reference",
                redactedValue: "keychain://\(reference.service)/\(reference.account)",
                replacementValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("bearer ") ? "Bearer \(reference.configValue)" : reference.configValue
            )
        }

        return (detectedRows + envReferenceRows + headerReferenceRows).sorted { lhs, rhs in
            if lhs.fieldLabel != rhs.fieldLabel { return lhs.fieldLabel < rhs.fieldLabel }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func ownershipLookup(from matches: [ServerProcessMatch]) -> [Int32: RuntimeOwnership] {
        matches.reduce(into: [:]) { lookup, match in
            let existing = lookup[match.processID] ?? .unknown
            lookup[match.processID] = strongestOwnership(existing, match.ownership)
        }
    }

    private func strongestOwnership(_ lhs: RuntimeOwnership, _ rhs: RuntimeOwnership) -> RuntimeOwnership {
        if lhs == .hubOwned || rhs == .hubOwned { return .hubOwned }
        if lhs == .agentOwned || rhs == .agentOwned { return .agentOwned }
        return .unknown
    }

    private func makeProcessRow(_ process: MCPProcessSnapshot, ownership: RuntimeOwnership = .unknown) -> DashboardProcessRow {
        DashboardProcessRow(
            id: process.id,
            pid: process.pid,
            executableName: process.executableName,
            commandLine: process.commandLine,
            matchReason: process.matchReason,
            ownership: ownership,
            cpuPercent: process.cpuPercent,
            memoryBytes: process.memoryBytes
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
            return "\(server.transport.rawValue) • \(SecretRedactor.redactText(url))"
        }

        let commandParts = ([server.command].compactMap { $0 } + server.args).filter { !$0.isEmpty }
        if commandParts.isEmpty {
            return server.transport.rawValue
        }
        return "\(server.transport.rawValue) • \(SecretRedactor.redactCommandArguments(commandParts).joined(separator: " "))"
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
