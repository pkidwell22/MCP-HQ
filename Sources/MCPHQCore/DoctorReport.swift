import Foundation

public enum DoctorFindingSeverity: String, Codable, Equatable, Sendable, Comparable {
    case info
    case warning
    case error

    public static func < (lhs: DoctorFindingSeverity, rhs: DoctorFindingSeverity) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ severity: DoctorFindingSeverity) -> Int {
        switch severity {
        case .error:
            return 0
        case .warning:
            return 1
        case .info:
            return 2
        }
    }
}

public enum DoctorFindingCategory: String, Codable, Equatable, Sendable {
    case source
    case config
    case server
    case probe
}

public struct DoctorFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let severity: DoctorFindingSeverity
    public let category: DoctorFindingCategory
    public let agentName: String
    public let sourcePath: String
    public let serverID: String?
    public let serverName: String?
    public let title: String
    public let whyItMatters: String
    public let suggestedFix: String

    public init(
        severity: DoctorFindingSeverity,
        category: DoctorFindingCategory,
        agentName: String,
        sourcePath: String,
        serverID: String? = nil,
        serverName: String? = nil,
        title: String,
        whyItMatters: String,
        suggestedFix: String
    ) {
        self.severity = severity
        self.category = category
        self.agentName = agentName
        self.sourcePath = sourcePath
        self.serverID = serverID
        self.serverName = serverName
        self.title = SecretRedactor.redactText(title)
        self.whyItMatters = SecretRedactor.redactText(whyItMatters)
        self.suggestedFix = SecretRedactor.redactText(suggestedFix)
        self.id = [
            agentName,
            sourcePath,
            serverID ?? "",
            category.rawValue,
            severity.rawValue,
            self.title,
        ].joined(separator: ":")
    }
}

public struct DoctorFindingGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let agentName: String
    public let sourcePath: String
    public let findings: [DoctorFinding]

    public init(agentName: String, sourcePath: String, findings: [DoctorFinding]) {
        self.id = "\(agentName):\(sourcePath)"
        self.agentName = agentName
        self.sourcePath = sourcePath
        self.findings = findings
    }
}

public struct DoctorFindingFilter: Codable, Equatable, Sendable {
    public let severity: DoctorFindingSeverity?
    public let sourcePath: String?
    public let serverID: String?

    public var isActive: Bool {
        severity != nil || sourcePath != nil || serverID != nil
    }

    public init(
        severity: DoctorFindingSeverity? = nil,
        sourcePath: String? = nil,
        serverID: String? = nil
    ) {
        self.severity = severity
        self.sourcePath = sourcePath?.isEmpty == true ? nil : sourcePath
        self.serverID = serverID?.isEmpty == true ? nil : serverID
    }

    public func matches(_ finding: DoctorFinding) -> Bool {
        if let severity, finding.severity != severity { return false }
        if let sourcePath, finding.sourcePath != sourcePath { return false }
        if let serverID, finding.serverID != serverID { return false }
        return true
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let findings: [DoctorFinding]
    public let groups: [DoctorFindingGroup]
    public let errorCount: Int
    public let warningCount: Int
    public let infoCount: Int

    public init(findings: [DoctorFinding]) {
        let sortedFindings = findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            if lhs.agentName != rhs.agentName {
                return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
            }
            if lhs.sourcePath != rhs.sourcePath {
                return lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        self.findings = sortedFindings
        self.errorCount = sortedFindings.filter { $0.severity == .error }.count
        self.warningCount = sortedFindings.filter { $0.severity == .warning }.count
        self.infoCount = sortedFindings.filter { $0.severity == .info }.count
        self.groups = Dictionary(grouping: sortedFindings) { finding in
            "\(finding.agentName):\(finding.sourcePath)"
        }.values.map { grouped in
            let first = grouped[0]
            return DoctorFindingGroup(
                agentName: first.agentName,
                sourcePath: first.sourcePath,
                findings: grouped
            )
        }.sorted { lhs, rhs in
            if lhs.agentName != rhs.agentName {
                return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
            }
            return lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath) == .orderedAscending
        }
    }

    public func filtered(by filter: DoctorFindingFilter) -> DoctorReport {
        guard filter.isActive else { return self }
        return DoctorReport(findings: findings.filter { filter.matches($0) })
    }
}

public struct DoctorReportBuilder: Sendable {
    public init() {}

    public func build(from result: ScanResult) -> DoctorReport {
        let serversByID = Dictionary(uniqueKeysWithValues: result.servers.map { ($0.id, $0) })
        var findings: [DoctorFinding] = []
        findings.append(contentsOf: result.sourceHealth.compactMap(sourceFinding))
        findings.append(contentsOf: result.issues.map { issueFinding($0, servers: result.servers) })
        findings.append(contentsOf: result.probeResults.compactMap { probeFinding($0, serversByID: serversByID) })
        return DoctorReport(findings: findings)
    }

    private func sourceFinding(_ health: ConfigSourceHealth) -> DoctorFinding? {
        let agentName = AgentRegistry.displayName(for: health.source.agent)
        switch health.state {
        case .parsed, .found:
            return nil
        case .missing:
            return DoctorFinding(
                severity: .info,
                category: .source,
                agentName: agentName,
                sourcePath: health.source.path,
                title: "\(agentName) config is missing",
                whyItMatters: "MCP-HQ cannot connect this agent to servers until its config exists.",
                suggestedFix: "Create the config through the agent, or use MCP-HQ config generation when ready."
            )
        case .noServers:
            return DoctorFinding(
                severity: .info,
                category: .source,
                agentName: agentName,
                sourcePath: health.source.path,
                title: "\(agentName) config has no MCP servers",
                whyItMatters: "The agent is known, but no MCP server bindings are currently enabled there.",
                suggestedFix: "Add a server in the agent or enable one through MCP-HQ config generation."
            )
        case .unsupported:
            return DoctorFinding(
                severity: .warning,
                category: .source,
                agentName: agentName,
                sourcePath: health.source.path,
                title: "\(agentName) config parser is unsupported",
                whyItMatters: "MCP-HQ found the file but cannot safely interpret it yet.",
                suggestedFix: "Add parser support before editing this config with MCP-HQ."
            )
        case .malformed:
            return DoctorFinding(
                severity: .error,
                category: .config,
                agentName: agentName,
                sourcePath: health.source.path,
                title: "\(agentName) config is malformed",
                whyItMatters: "The agent may fail to load MCP servers from this config.",
                suggestedFix: health.message
            )
        }
    }

    private func issueFinding(_ issue: ScanIssue, servers: [ServerDefinition]) -> DoctorFinding {
        let sourceScopedServers = servers.filter { $0.sourcePath == issue.source.path }
        let matchingServer = sourceScopedServers.first { server in
            issue.message.localizedCaseInsensitiveContains(server.displayName)
                || issue.message.localizedCaseInsensitiveContains(server.id)
        }
        let severity: DoctorFindingSeverity = issue.severity == .error ? .error : .warning
        return DoctorFinding(
            severity: severity,
            category: .server,
            agentName: AgentRegistry.displayName(for: issue.source.agent),
            sourcePath: issue.source.path,
            serverID: matchingServer?.id,
            serverName: matchingServer?.displayName,
            title: issue.message,
            whyItMatters: whyItMatters(for: issue.message),
            suggestedFix: suggestedFix(for: issue.message)
        )
    }

    private func probeFinding(_ probe: MCPProbeResult, serversByID: [String: ServerDefinition]) -> DoctorFinding? {
        guard probe.status == .warning || probe.status == .error else { return nil }
        let server = serversByID[probe.serverID]
        return DoctorFinding(
            severity: probe.status == .error ? .error : .warning,
            category: .probe,
            agentName: agentName(for: server),
            sourcePath: server?.sourcePath ?? "",
            serverID: probe.serverID,
            serverName: server?.displayName,
            title: probe.message,
            whyItMatters: "MCP-HQ could not confirm this server's MCP handshake or capability discovery.",
            suggestedFix: "Check the server command, URL, headers, environment, and logs; then rerun probes."
        )
    }

    private func agentName(for server: ServerDefinition?) -> String {
        guard let server,
              let agentPrefix = server.id.split(separator: ":", maxSplits: 1).first,
              let agent = AgentID(rawValue: String(agentPrefix)) else { return "Unknown" }
        return AgentRegistry.displayName(for: agent)
    }

    private func whyItMatters(for message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("command not found") {
            return "The agent will not be able to launch this stdio MCP server."
        }
        if lowercased.contains("missing keychain secret") {
            return "The config points at a Keychain item that is not present, so the server cannot recover that credential at launch."
        }
        if lowercased.contains("could not validate keychain secret") {
            return "MCP-HQ could not confirm whether the Keychain-backed credential exists; the server may fail until access is restored."
        }
        if lowercased.contains("keychain migration write failed") || lowercased.contains("previous keychain migration write failed") {
            return "A guarded migration did not finish writing the credential to Keychain, so MCP-HQ must avoid treating partial writes as a completed config migration."
        }
        if lowercased.contains("missing env var") {
            return "The server likely needs a credential or path value before it can start successfully."
        }
        if lowercased.contains("duplicate") {
            return "Duplicate MCP targets can make it hard to know which process or tool binding is active."
        }
        return "This diagnostic can affect whether the agent can use the MCP server reliably."
    }

    private func suggestedFix(for message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("command not found") {
            return "Install the command, use an absolute path, or add the command's directory to the launch environment."
        }
        if lowercased.contains("missing keychain secret") {
            return "Re-enter the secret and migrate/store it back to Keychain, or remove the keychain:// reference if the credential was intentionally deleted."
        }
        if lowercased.contains("could not validate keychain secret") {
            return "Unlock Keychain and grant MCP-HQ or this terminal access, then rerun doctor; if access cannot be restored, re-enter and migrate the secret."
        }
        if lowercased.contains("keychain migration write failed") || lowercased.contains("previous keychain migration write failed") {
            return "Confirm config snapshots and partial Keychain writes were rolled back, fix Keychain access, then rerun migration without pasting plaintext into config."
        }
        if lowercased.contains("missing env var") {
            return "Set the environment variable or migrate the secret into Keychain-backed config rendering."
        }
        if lowercased.contains("duplicate") {
            return "Remove one duplicate target or intentionally consolidate it through MCP-HQ."
        }
        return "Review the source config and rerun MCP-HQ doctor after applying a fix."
    }
}

public enum DoctorReportExportFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case text
    case json

    public var label: String {
        switch self {
        case .text:
            return "TXT"
        case .json:
            return "JSON"
        }
    }

    public var fileName: String {
        switch self {
        case .text:
            return "doctor-report.txt"
        case .json:
            return "doctor-report.json"
        }
    }

    public var fileExtension: String {
        switch self {
        case .text:
            return "txt"
        case .json:
            return "json"
        }
    }
}

public struct DoctorReportExporter: Sendable {
    public init() {}

    public func render(_ report: DoctorReport, format: DoctorReportExportFormat) throws -> String {
        switch format {
        case .text:
            return DoctorReportFormatter().formatText(report)
        case .json:
            return try DoctorReportFormatter().formatJSON(report)
        }
    }

    public func write(_ report: DoctorReport, format: DoctorReportExportFormat, to url: URL) throws {
        let text = try render(report, format: format)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

public struct DoctorReportFormatter: Sendable {
    public init() {}

    public func formatText(_ report: DoctorReport, filter: DoctorFindingFilter = DoctorFindingFilter()) -> String {
        let report = report.filtered(by: filter)
        var lines = [
            "MCP-HQ doctor",
            "",
            "Findings: \(report.findings.count)",
            "Errors: \(report.errorCount)",
            "Warnings: \(report.warningCount)",
            "Info: \(report.infoCount)",
        ]

        for group in report.groups {
            lines.append("")
            lines.append("\(group.agentName)")
            lines.append("  source: \(group.sourcePath)")
            for finding in group.findings {
                lines.append("  [\(finding.severity.rawValue)] \(finding.category.rawValue): \(finding.title)")
                if let serverName = finding.serverName {
                    lines.append("    server: \(serverName)")
                }
                lines.append("    why: \(finding.whyItMatters)")
                lines.append("    fix: \(finding.suggestedFix)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func formatJSON(_ report: DoctorReport, filter: DoctorFindingFilter = DoctorFindingFilter()) throws -> String {
        let report = report.filtered(by: filter)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScanOutputFormatterError.invalidUTF8
        }
        return json
    }
}
