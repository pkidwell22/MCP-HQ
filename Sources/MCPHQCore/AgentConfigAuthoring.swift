import CryptoKit
import Foundation

public enum AgentConfigAuthoringError: Error, Equatable, CustomStringConvertible {
    case noTargetSources
    case noTemplateServers
    case staleTargetSource(String)
    case applyFailed(String)
    case rollbackUnavailable
    case rollbackFailed(String)

    public var description: String {
        switch self {
        case .noTargetSources:
            return "No target agent sources were provided"
        case .noTemplateServers:
            return "No template server bindings were provided"
        case .staleTargetSource(let path):
            return "Target config changed after preview and must be previewed again: \(SecretRedactor.redactText(path))"
        case .applyFailed(let message):
            return "Binding draft apply failed: \(message)"
        case .rollbackUnavailable:
            return "No rollback targets were available"
        case .rollbackFailed(let message):
            return "Bulk rollback failed: \(message)"
        }
    }
}

public struct AgentConfigFileSnapshot: Equatable, Sendable {
    public let path: String
    public let exists: Bool
    public let byteCount: Int?
    public let modificationTime: Date?
    public let sha256: String?

    public init(path: String, exists: Bool, byteCount: Int?, modificationTime: Date?, sha256: String?) {
        self.path = path
        self.exists = exists
        self.byteCount = byteCount
        self.modificationTime = modificationTime
        self.sha256 = sha256
    }
}

public struct AgentBindingTargetPreview: Equatable {
    public let source: ConfigSource
    public let agentName: String
    public let isEnabled: Bool
    public let serverCount: Int
    public let serversAfterChange: [ServerDefinition]
    public let preview: GeneratedConfigPreview
    public let fileSnapshot: AgentConfigFileSnapshot

    public init(
        source: ConfigSource,
        agentName: String,
        isEnabled: Bool,
        serverCount: Int,
        serversAfterChange: [ServerDefinition],
        preview: GeneratedConfigPreview,
        fileSnapshot: AgentConfigFileSnapshot
    ) {
        self.source = source
        self.agentName = agentName
        self.isEnabled = isEnabled
        self.serverCount = serverCount
        self.serversAfterChange = serversAfterChange
        self.preview = preview
        self.fileSnapshot = fileSnapshot
    }
}

public struct AgentBindingDraftPreview: Equatable {
    public let bindingName: String
    public let targetPreviews: [AgentBindingTargetPreview]
    public let desiredEnabledCount: Int

    public var changedPreviews: [AgentBindingTargetPreview] {
        targetPreviews.filter { $0.preview.diffText != "No changes\n" }
    }

    public var fileSnapshotsByPath: [String: AgentConfigFileSnapshot] {
        Dictionary(uniqueKeysWithValues: targetPreviews.map { ($0.source.path, $0.fileSnapshot) })
    }

    public var summaryText: String {
        let enabledCount = desiredEnabledCount
        let changedCount = changedPreviews.count
        return "\(bindingName): \(enabledCount) enabled agent\(enabledCount == 1 ? "" : "s") • \(changedCount) source\(changedCount == 1 ? "" : "s") would change"
    }

    public init(bindingName: String, targetPreviews: [AgentBindingTargetPreview], desiredEnabledCount: Int) {
        self.bindingName = bindingName
        self.targetPreviews = targetPreviews
        self.desiredEnabledCount = desiredEnabledCount
    }
}

public struct AgentBindingApplyTargetResult: Equatable {
    public let source: ConfigSource
    public let agentName: String
    public let isEnabled: Bool
    public let serverCount: Int
    public let backupPath: String?

    public init(source: ConfigSource, agentName: String, isEnabled: Bool, serverCount: Int, backupPath: String?) {
        self.source = source
        self.agentName = agentName
        self.isEnabled = isEnabled
        self.serverCount = serverCount
        self.backupPath = backupPath
    }
}

public struct AgentBindingDraftApplyResult: Equatable {
    public let bindingName: String
    public let appliedTargets: [AgentBindingApplyTargetResult]

    public var summaryText: String {
        "\(bindingName): applied \(appliedTargets.count) source\(appliedTargets.count == 1 ? "" : "s")"
    }

    public init(bindingName: String, appliedTargets: [AgentBindingApplyTargetResult]) {
        self.bindingName = bindingName
        self.appliedTargets = appliedTargets
    }
}

public struct AgentBulkBindingTargetPreview: Equatable {
    public let source: ConfigSource
    public let agentName: String
    public let bindingCount: Int
    public let serverCount: Int
    public let serversAfterChange: [ServerDefinition]
    public let preview: GeneratedConfigPreview
    public let fileSnapshot: AgentConfigFileSnapshot

    public init(
        source: ConfigSource,
        agentName: String,
        bindingCount: Int,
        serverCount: Int,
        serversAfterChange: [ServerDefinition],
        preview: GeneratedConfigPreview,
        fileSnapshot: AgentConfigFileSnapshot
    ) {
        self.source = source
        self.agentName = agentName
        self.bindingCount = bindingCount
        self.serverCount = serverCount
        self.serversAfterChange = serversAfterChange
        self.preview = preview
        self.fileSnapshot = fileSnapshot
    }
}

public struct AgentBulkBindingDraftPreview: Equatable {
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let targetPreviews: [AgentBulkBindingTargetPreview]

    public var changedPreviews: [AgentBulkBindingTargetPreview] {
        targetPreviews.filter { $0.preview.diffText != "No changes\n" }
    }

    public var summaryText: String {
        let changedCount = changedPreviews.count
        let targetCount = targetPreviews.count
        let sourceLabel = templateSource.map { " from \(AgentRegistry.displayName(for: $0.agent))" } ?? ""
        return "\(templateBindingCount) binding\(templateBindingCount == 1 ? "" : "s")\(sourceLabel) • \(changedCount) of \(targetCount) source\(targetCount == 1 ? "" : "s") would change"
    }

    public var fileSnapshotsByPath: [String: AgentConfigFileSnapshot] {
        Dictionary(uniqueKeysWithValues: targetPreviews.map { ($0.source.path, $0.fileSnapshot) })
    }

    public init(templateSource: ConfigSource?, templateBindingCount: Int, targetPreviews: [AgentBulkBindingTargetPreview]) {
        self.templateSource = templateSource
        self.templateBindingCount = templateBindingCount
        self.targetPreviews = targetPreviews
    }
}

public struct AgentBulkBindingApplyTargetResult: Equatable {
    public let source: ConfigSource
    public let agentName: String
    public let bindingCount: Int
    public let serverCount: Int
    public let backupPath: String?

    public init(source: ConfigSource, agentName: String, bindingCount: Int, serverCount: Int, backupPath: String?) {
        self.source = source
        self.agentName = agentName
        self.bindingCount = bindingCount
        self.serverCount = serverCount
        self.backupPath = backupPath
    }
}

public struct AgentBulkConnectRollbackTarget: Codable, Equatable, Sendable {
    public let source: ConfigSource
    public let agentName: String
    public let backupPath: String?
    public let shouldDeleteCreatedFile: Bool

    public init(source: ConfigSource, agentName: String, backupPath: String?, shouldDeleteCreatedFile: Bool) {
        self.source = source
        self.agentName = agentName
        self.backupPath = backupPath
        self.shouldDeleteCreatedFile = shouldDeleteCreatedFile
    }
}

public struct AgentBulkConnectRollbackPlan: Codable, Equatable, Sendable {
    public let id: String
    public let createdAt: Date
    public let targets: [AgentBulkConnectRollbackTarget]

    public var summaryText: String {
        "\(targets.count) target source\(targets.count == 1 ? "" : "s") can be rolled back"
    }

    public init(id: String = UUID().uuidString, createdAt: Date = Date(), targets: [AgentBulkConnectRollbackTarget]) {
        self.id = id
        self.createdAt = createdAt
        self.targets = targets
    }
}

public struct AgentBulkConnectRollbackResult: Codable, Equatable, Sendable {
    public let planID: String
    public let restoredTargets: [AgentBulkConnectRollbackTarget]

    public var summaryText: String {
        "rolled back \(restoredTargets.count) target source\(restoredTargets.count == 1 ? "" : "s")"
    }

    public init(planID: String, restoredTargets: [AgentBulkConnectRollbackTarget]) {
        self.planID = planID
        self.restoredTargets = restoredTargets
    }
}

public struct AgentBulkBindingDraftApplyResult: Equatable {
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let appliedTargets: [AgentBulkBindingApplyTargetResult]
    public let verificationReport: AgentBulkConnectVerificationReport?
    public let rollbackPlan: AgentBulkConnectRollbackPlan?

    public var summaryText: String {
        "applied \(templateBindingCount) binding\(templateBindingCount == 1 ? "" : "s") to \(appliedTargets.count) source\(appliedTargets.count == 1 ? "" : "s")"
    }

    public init(
        templateSource: ConfigSource?,
        templateBindingCount: Int,
        appliedTargets: [AgentBulkBindingApplyTargetResult],
        verificationReport: AgentBulkConnectVerificationReport? = nil,
        rollbackPlan: AgentBulkConnectRollbackPlan? = nil
    ) {
        self.templateSource = templateSource
        self.templateBindingCount = templateBindingCount
        self.appliedTargets = appliedTargets
        self.verificationReport = verificationReport
        self.rollbackPlan = rollbackPlan
    }
}

public enum AgentBulkConnectVerificationStatus: String, Equatable, Sendable {
    case configured
    case missingConfig
    case unsupported
    case parseFailed
    case missingBindings
}

public enum AgentBulkConnectProbeVerificationStatus: String, Equatable, Sendable {
    case notRun
    case healthy
    case partial
    case failed
}

public enum AgentBulkConnectBindingConfigStatus: String, Equatable, Sendable {
    case configured
    case missingConfig
    case unsupported
    case parseFailed
    case missingBinding
}

public enum AgentBulkConnectBindingProbeStatus: String, Equatable, Sendable {
    case notRun
    case probeable
    case warning
    case failed
    case skipped
    case missing
    case unavailable
}

public struct AgentBulkConnectBindingVerification: Equatable, Sendable {
    public let bindingName: String
    public let configStatus: AgentBulkConnectBindingConfigStatus
    public let probeStatus: AgentBulkConnectBindingProbeStatus
    public let probeMessage: String

    public init(
        bindingName: String,
        configStatus: AgentBulkConnectBindingConfigStatus,
        probeStatus: AgentBulkConnectBindingProbeStatus = .notRun,
        probeMessage: String = "Live probe was not run for this binding."
    ) {
        self.bindingName = SecretRedactor.redactText(bindingName)
        self.configStatus = configStatus
        self.probeStatus = probeStatus
        self.probeMessage = SecretRedactor.redactText(probeMessage)
    }
}

public struct AgentBulkConnectTargetVerification: Equatable, Sendable {
    public let source: ConfigSource
    public let agentName: String
    public let status: AgentBulkConnectVerificationStatus
    public let expectedBindingCount: Int
    public let presentBindingCount: Int
    public let missingBindingNames: [String]
    public let message: String
    public let probeStatus: AgentBulkConnectProbeVerificationStatus
    public let healthyProbeCount: Int
    public let warningProbeCount: Int
    public let errorProbeCount: Int
    public let skippedProbeCount: Int
    public let missingProbeCount: Int
    public let probeMessage: String
    public let bindingVerifications: [AgentBulkConnectBindingVerification]

    public init(
        source: ConfigSource,
        agentName: String,
        status: AgentBulkConnectVerificationStatus,
        expectedBindingCount: Int,
        presentBindingCount: Int,
        missingBindingNames: [String],
        message: String,
        probeStatus: AgentBulkConnectProbeVerificationStatus = .notRun,
        healthyProbeCount: Int = 0,
        warningProbeCount: Int = 0,
        errorProbeCount: Int = 0,
        skippedProbeCount: Int = 0,
        missingProbeCount: Int = 0,
        probeMessage: String = "Live probes were not run for this verification.",
        bindingVerifications: [AgentBulkConnectBindingVerification] = []
    ) {
        self.source = source
        self.agentName = agentName
        self.status = status
        self.expectedBindingCount = expectedBindingCount
        self.presentBindingCount = presentBindingCount
        self.missingBindingNames = missingBindingNames
        self.message = SecretRedactor.redactText(message)
        self.probeStatus = probeStatus
        self.healthyProbeCount = healthyProbeCount
        self.warningProbeCount = warningProbeCount
        self.errorProbeCount = errorProbeCount
        self.skippedProbeCount = skippedProbeCount
        self.missingProbeCount = missingProbeCount
        self.probeMessage = SecretRedactor.redactText(probeMessage)
        self.bindingVerifications = bindingVerifications
    }
}

public enum AgentBulkConnectVerificationMatrixFormatter {
    public static func markdownTableLines(for report: AgentBulkConnectVerificationReport) -> [String] {
        var lines = [
            "| Target source | Binding | Config verification | Live probe |",
            "| --- | --- | --- | --- |",
        ]
        let rows = report.targets.flatMap { target in
            target.bindingVerifications.map { verification in
                "| \(cell("\(target.agentName) \(target.source.path)")) | \(cell(verification.bindingName)) | \(cell(configLabel(verification.configStatus))) | \(cell(probeLabel(verification.probeStatus))) |"
            }
        }
        lines.append(contentsOf: rows.isEmpty ? ["| (none) | (none) | not available | not available |"] : rows)
        return lines.map(SecretRedactor.redactConfigText)
    }

    public static func markdownTable(for report: AgentBulkConnectVerificationReport) -> String {
        markdownTableLines(for: report).joined(separator: "\n")
    }

    private static func configLabel(_ status: AgentBulkConnectBindingConfigStatus) -> String {
        switch status {
        case .configured:
            return "configured"
        case .missingConfig:
            return "config missing"
        case .unsupported:
            return "unsupported"
        case .parseFailed:
            return "parse failed"
        case .missingBinding:
            return "missing binding"
        }
    }

    private static func probeLabel(_ status: AgentBulkConnectBindingProbeStatus) -> String {
        switch status {
        case .notRun:
            return "not run"
        case .probeable:
            return "probeable"
        case .warning:
            return "warning"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        case .missing:
            return "no probe result"
        case .unavailable:
            return "not available"
        }
    }

    private static func cell(_ value: String) -> String {
        SecretRedactor.redactConfigText(value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AgentBulkConnectVerificationReport: Equatable, Sendable {
    public let templateBindingCount: Int
    public let targets: [AgentBulkConnectTargetVerification]

    public var configuredCount: Int {
        targets.filter { $0.status == .configured }.count
    }

    public var probeHealthyTargetCount: Int {
        targets.filter { $0.probeStatus == .healthy }.count
    }

    public var probeSummaryText: String {
        guard targets.contains(where: { $0.probeStatus != .notRun }) else {
            return "Live probes were not run for this verification."
        }
        return "\(probeHealthyTargetCount) of \(targets.count) target source\(targets.count == 1 ? "" : "s") passed live probe verification"
    }

    public var summaryText: String {
        "\(configuredCount) of \(targets.count) target source\(targets.count == 1 ? "" : "s") configured and parseable"
    }

    public init(templateBindingCount: Int, targets: [AgentBulkConnectTargetVerification]) {
        self.templateBindingCount = templateBindingCount
        self.targets = targets
    }
}

public struct AgentBulkConnectVerifier {
    private let parser: AgentConfigParser
    private let fileManager: FileManager

    public init(parser: AgentConfigParser = AgentConfigParser(), fileManager: FileManager = .default) {
        self.parser = parser
        self.fileManager = fileManager
    }

    public func verify(
        templateServers: [ServerDefinition],
        targetSources: [ConfigSource],
        probeResults: [MCPProbeResult]? = nil
    ) -> AgentBulkConnectVerificationReport {
        let expectedNames = Self.uniqueExpectedNames(templateServers)
        let targets = targetSources.sorted(by: sourceSort).map { source in
            verify(source: source, expectedNames: expectedNames, probeResults: probeResults)
        }
        return AgentBulkConnectVerificationReport(templateBindingCount: expectedNames.count, targets: targets)
    }

    private func verify(
        source: ConfigSource,
        expectedNames: [String],
        probeResults: [MCPProbeResult]?
    ) -> AgentBulkConnectTargetVerification {
        let agentName = AgentRegistry.displayName(for: source.agent)
        guard parser.supports(source.agent) else {
            return AgentBulkConnectTargetVerification(
                source: source,
                agentName: agentName,
                status: .unsupported,
                expectedBindingCount: expectedNames.count,
                presentBindingCount: 0,
                missingBindingNames: expectedNames,
                message: "MCP-HQ cannot parse \(agentName) configs yet.",
                bindingVerifications: Self.bindingVerifications(
                    expectedNames: expectedNames,
                    configStatus: .unsupported,
                    probeStatus: .unavailable,
                    probeMessage: "Live probe is unavailable because MCP-HQ cannot parse this config format."
                )
            )
        }
        guard fileManager.fileExists(atPath: source.path) else {
            return AgentBulkConnectTargetVerification(
                source: source,
                agentName: agentName,
                status: .missingConfig,
                expectedBindingCount: expectedNames.count,
                presentBindingCount: 0,
                missingBindingNames: expectedNames,
                message: "Config file is missing after apply.",
                bindingVerifications: Self.bindingVerifications(
                    expectedNames: expectedNames,
                    configStatus: .missingConfig,
                    probeStatus: .unavailable,
                    probeMessage: "Live probe is unavailable because the config file is missing."
                )
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
            try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
            let parsedServers = try parser.parse(data: data, source: source)
            let parsedByName = Dictionary(
                parsedServers.map { (Self.normalizedName($0.displayName), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let parsedNames = Set(parsedByName.keys)
            let normalizedExpectedNames = Set(expectedNames.map(Self.normalizedName))
            let expectedServers = expectedNames.compactMap { parsedByName[Self.normalizedName($0)] }
            let bindingVerifications = Self.bindingVerifications(
                expectedNames: expectedNames,
                parsedByName: parsedByName,
                probeResults: probeResults
            )
            let missingNames = expectedNames.filter { !parsedNames.contains(Self.normalizedName($0)) }
            if missingNames.isEmpty {
                let probeSummary = Self.probeSummary(
                    expectedServers: expectedServers.filter { normalizedExpectedNames.contains(Self.normalizedName($0.displayName)) },
                    probeResults: probeResults
                )
                return AgentBulkConnectTargetVerification(
                    source: source,
                    agentName: agentName,
                    status: .configured,
                    expectedBindingCount: expectedNames.count,
                    presentBindingCount: expectedNames.count,
                    missingBindingNames: [],
                    message: "All expected bindings are configured in a freshly parsed config. MCP-HQ has not verified that each external agent is using the changed config.",
                    probeStatus: probeSummary.status,
                    healthyProbeCount: probeSummary.healthy,
                    warningProbeCount: probeSummary.warning,
                    errorProbeCount: probeSummary.error,
                    skippedProbeCount: probeSummary.skipped,
                    missingProbeCount: probeSummary.missing,
                    probeMessage: probeSummary.message,
                    bindingVerifications: bindingVerifications
                )
            }
            return AgentBulkConnectTargetVerification(
                source: source,
                agentName: agentName,
                status: .missingBindings,
                expectedBindingCount: expectedNames.count,
                presentBindingCount: expectedNames.count - missingNames.count,
                missingBindingNames: missingNames,
                message: "Fresh parse is missing \(missingNames.count) expected binding\(missingNames.count == 1 ? "" : "s").",
                bindingVerifications: bindingVerifications
            )
        } catch {
            return AgentBulkConnectTargetVerification(
                source: source,
                agentName: agentName,
                status: .parseFailed,
                expectedBindingCount: expectedNames.count,
                presentBindingCount: 0,
                missingBindingNames: expectedNames,
                message: "Fresh parse failed after apply: \(String(describing: error))",
                bindingVerifications: Self.bindingVerifications(
                    expectedNames: expectedNames,
                    configStatus: .parseFailed,
                    probeStatus: .unavailable,
                    probeMessage: "Live probe is unavailable because the config did not parse."
                )
            )
        }
    }

    private func sourceSort(_ lhs: ConfigSource, _ rhs: ConfigSource) -> Bool {
        let leftAgent = AgentRegistry.displayName(for: lhs.agent)
        let rightAgent = AgentRegistry.displayName(for: rhs.agent)
        if leftAgent != rightAgent {
            return leftAgent.localizedCaseInsensitiveCompare(rightAgent) == .orderedAscending
        }
        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private static func uniqueExpectedNames(_ servers: [ServerDefinition]) -> [String] {
        var seen: Set<String> = []
        return servers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .compactMap { server in
                let normalized = normalizedName(server.displayName)
                guard !seen.contains(normalized) else { return nil }
                seen.insert(normalized)
                return server.displayName
            }
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func bindingVerifications(
        expectedNames: [String],
        configStatus: AgentBulkConnectBindingConfigStatus,
        probeStatus: AgentBulkConnectBindingProbeStatus,
        probeMessage: String
    ) -> [AgentBulkConnectBindingVerification] {
        expectedNames.map { name in
            AgentBulkConnectBindingVerification(
                bindingName: name,
                configStatus: configStatus,
                probeStatus: probeStatus,
                probeMessage: probeMessage
            )
        }
    }

    private static func bindingVerifications(
        expectedNames: [String],
        parsedByName: [String: ServerDefinition],
        probeResults: [MCPProbeResult]?
    ) -> [AgentBulkConnectBindingVerification] {
        expectedNames.map { name in
            guard let server = parsedByName[normalizedName(name)] else {
                return AgentBulkConnectBindingVerification(
                    bindingName: name,
                    configStatus: .missingBinding,
                    probeStatus: .unavailable,
                    probeMessage: "Live probe is unavailable because this binding is missing from the parsed config."
                )
            }
            let probe = bindingProbeStatus(for: server, probeResults: probeResults)
            return AgentBulkConnectBindingVerification(
                bindingName: name,
                configStatus: .configured,
                probeStatus: probe.status,
                probeMessage: probe.message
            )
        }
    }

    private static func bindingProbeStatus(
        for server: ServerDefinition,
        probeResults: [MCPProbeResult]?
    ) -> (status: AgentBulkConnectBindingProbeStatus, message: String) {
        guard let probeResults else {
            return (.notRun, "Live probe was not run for this binding.")
        }
        let probesByServerID = Dictionary(probeResults.map { ($0.serverID, $0) }, uniquingKeysWith: { first, _ in first })
        guard let probe = probesByServerID[server.id] else {
            return (.missing, "No live probe result was available for this configured binding.")
        }
        let message = SecretRedactor.redactText(probe.message)
        switch probe.status {
        case .healthy:
            return (.probeable, message.isEmpty ? "Live probe reported this binding as probeable." : message)
        case .warning:
            return (.warning, message.isEmpty ? "Live probe reported a warning for this binding." : message)
        case .error:
            return (.failed, message.isEmpty ? "Live probe failed for this binding." : message)
        case .skipped:
            return (.skipped, message.isEmpty ? "Live probe skipped this binding." : message)
        }
    }

    private static func probeSummary(
        expectedServers: [ServerDefinition],
        probeResults: [MCPProbeResult]?
    ) -> (status: AgentBulkConnectProbeVerificationStatus, healthy: Int, warning: Int, error: Int, skipped: Int, missing: Int, message: String) {
        guard let probeResults else {
            return (.notRun, 0, 0, 0, 0, 0, "Live probes were not run for this verification.")
        }
        let probesByServerID = Dictionary(probeResults.map { ($0.serverID, $0) }, uniquingKeysWith: { first, _ in first })
        var healthy = 0
        var warning = 0
        var error = 0
        var skipped = 0
        var missing = 0

        for server in expectedServers {
            guard let probe = probesByServerID[server.id] else {
                missing += 1
                continue
            }
            switch probe.status {
            case .healthy:
                healthy += 1
            case .warning:
                warning += 1
            case .error:
                error += 1
            case .skipped:
                skipped += 1
            }
        }

        let status: AgentBulkConnectProbeVerificationStatus
        if error > 0 || missing > 0 {
            status = .failed
        } else if warning > 0 || skipped > 0 {
            status = .partial
        } else {
            status = .healthy
        }
        let total = expectedServers.count
        let message = "Live probes: \(healthy) healthy, \(warning) warning, \(error) error, \(skipped) skipped, \(missing) missing of \(total) expected binding\(total == 1 ? "" : "s")."
        return (status, healthy, warning, error, skipped, missing, message)
    }
}

public struct AgentConfigAuthoringPlanner {
    private let safeApplier: AgentConfigSafeApplier
    private let fileManager: FileManager
    private let controlPlaneStore: SQLiteScanHistoryStore?
    private let now: () -> Date

    public init(
        safeApplier: AgentConfigSafeApplier = AgentConfigSafeApplier(),
        fileManager: FileManager = .default,
        controlPlaneStore: SQLiteScanHistoryStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.safeApplier = safeApplier
        self.fileManager = fileManager
        self.controlPlaneStore = controlPlaneStore
        self.now = now
    }

    public func previewBinding(
        templateServer: ServerDefinition,
        targetSources: [ConfigSource],
        existingServers: [ServerDefinition],
        enabledSourceIDs: Set<String>
    ) throws -> AgentBindingDraftPreview {
        guard !targetSources.isEmpty else {
            throw AgentConfigAuthoringError.noTargetSources
        }

        let serversBySource = Dictionary(grouping: existingServers, by: \.sourcePath)
        let normalizedBindingName = Self.normalizedName(templateServer.displayName)
        let targetPreviews = try targetSources.sorted(by: sourceSort).compactMap { source -> AgentBindingTargetPreview? in
            let desiredEnabled = enabledSourceIDs.contains(source.id)
            let currentServers = serversBySource[source.path] ?? []
            let currentlyHasBinding = currentServers.contains {
                Self.normalizedName($0.displayName) == normalizedBindingName
            }
            guard desiredEnabled != currentlyHasBinding else {
                return nil
            }
            let updatedServers = servers(
                currentServers,
                replacingBindingNamed: normalizedBindingName,
                with: desiredEnabled ? server(templateServer, for: source, preservingSecretReferencesFrom: nil) : nil
            )
            let preview = try safeApplier.preview(source: source, servers: updatedServers)
            return AgentBindingTargetPreview(
                source: source,
                agentName: AgentRegistry.displayName(for: source.agent),
                isEnabled: desiredEnabled,
                serverCount: updatedServers.count,
                serversAfterChange: updatedServers,
                preview: preview,
                fileSnapshot: try fileSnapshot(for: source)
            )
        }

        return AgentBindingDraftPreview(
            bindingName: templateServer.displayName,
            targetPreviews: targetPreviews,
            desiredEnabledCount: enabledSourceIDs.count
        )
    }

    public func applyBinding(
        templateServer: ServerDefinition,
        targetSources: [ConfigSource],
        existingServers: [ServerDefinition],
        enabledSourceIDs: Set<String>,
        expectedFileSnapshots: [String: AgentConfigFileSnapshot]? = nil
    ) throws -> AgentBindingDraftApplyResult {
        try verifyExpectedSnapshots(expectedFileSnapshots)
        let draft = try previewBinding(
            templateServer: templateServer,
            targetSources: targetSources,
            existingServers: existingServers,
            enabledSourceIDs: enabledSourceIDs
        )

        var snapshots: [String: Data?] = [:]
        var applied: [AgentBindingApplyTargetResult] = []

        do {
            for target in draft.changedPreviews {
                snapshots[target.source.path] = try snapshot(for: target.source)
                let result = try safeApplier.apply(source: target.source, servers: target.serversAfterChange, dryRun: false)
                applied.append(AgentBindingApplyTargetResult(
                    source: target.source,
                    agentName: target.agentName,
                    isEnabled: target.isEnabled,
                    serverCount: target.serverCount,
                    backupPath: result.backupPath
                ))
                try recordControlPlaneState(for: target, templateServer: templateServer, backupPath: result.backupPath)
            }
            return AgentBindingDraftApplyResult(bindingName: draft.bindingName, appliedTargets: applied)
        } catch {
            try restoreSnapshots(snapshots)
            throw AgentConfigAuthoringError.applyFailed(SecretRedactor.redactText(String(describing: error)))
        }
    }

    private func recordControlPlaneState(
        for target: AgentBindingTargetPreview,
        templateServer: ServerDefinition,
        backupPath: String?
    ) throws {
        guard let controlPlaneStore else { return }
        let timestamp = now()
        let desiredServer = server(templateServer, for: target.source, preservingSecretReferencesFrom: nil)
        try controlPlaneStore.upsertDesiredServerStates([desiredServer], for: target.source, enabled: target.isEnabled, updatedAt: timestamp)
        if let backupPath {
            _ = try controlPlaneStore.recordConfigBackup(
                source: target.source,
                backupPath: backupPath,
                reason: "\(target.isEnabled ? "enable" : "disable") \(templateServer.displayName) binding",
                createdAt: timestamp
            )
        }
    }

    private func snapshot(for source: ConfigSource) throws -> Data? {
        let url = URL(fileURLWithPath: source.path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func fileSnapshot(for source: ConfigSource) throws -> AgentConfigFileSnapshot {
        let url = URL(fileURLWithPath: source.path)
        guard fileManager.fileExists(atPath: source.path) else {
            return AgentConfigFileSnapshot(path: source.path, exists: false, byteCount: nil, modificationTime: nil, sha256: nil)
        }
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return AgentConfigFileSnapshot(
            path: source.path,
            exists: true,
            byteCount: data.count,
            modificationTime: attributes[.modificationDate] as? Date,
            sha256: digest
        )
    }

    private func verifyExpectedSnapshots(_ snapshots: [String: AgentConfigFileSnapshot]?) throws {
        guard let snapshots else { return }
        for expected in snapshots.values {
            let current = try fileSnapshot(for: ConfigSource(agent: .unknown, path: expected.path))
            guard current == expected else {
                throw AgentConfigAuthoringError.staleTargetSource(expected.path)
            }
        }
    }

    private func restoreSnapshots(_ snapshots: [String: Data?]) throws {
        for (path, data) in snapshots {
            let url = URL(fileURLWithPath: path)
            if let data {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } else if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func servers(
        _ currentServers: [ServerDefinition],
        replacingBindingNamed normalizedBindingName: String,
        with replacement: ServerDefinition?
    ) -> [ServerDefinition] {
        var next = currentServers.filter {
            Self.normalizedName($0.displayName) != normalizedBindingName
        }
        if let replacement {
            next.append(replacement)
        }
        return next.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func server(
        _ server: ServerDefinition,
        for source: ConfigSource,
        preservingSecretReferencesFrom existingServer: ServerDefinition?
    ) -> ServerDefinition {
        AgentConfigServerRetargeter.server(server, for: source, preservingSecretReferencesFrom: existingServer)
    }

    private func sourceSort(_ lhs: ConfigSource, _ rhs: ConfigSource) -> Bool {
        let leftAgent = AgentRegistry.displayName(for: lhs.agent)
        let rightAgent = AgentRegistry.displayName(for: rhs.agent)
        if leftAgent != rightAgent {
            return leftAgent.localizedCaseInsensitiveCompare(rightAgent) == .orderedAscending
        }
        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct AgentBulkConfigAuthoringPlanner {
    private let safeApplier: AgentConfigSafeApplier
    private let fileManager: FileManager
    private let controlPlaneStore: SQLiteScanHistoryStore?
    private let now: () -> Date

    public init(
        safeApplier: AgentConfigSafeApplier = AgentConfigSafeApplier(),
        fileManager: FileManager = .default,
        controlPlaneStore: SQLiteScanHistoryStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.safeApplier = safeApplier
        self.fileManager = fileManager
        self.controlPlaneStore = controlPlaneStore
        self.now = now
    }

    public func previewConnectAll(
        templateServers: [ServerDefinition],
        templateSource: ConfigSource? = nil,
        targetSources: [ConfigSource],
        existingServers: [ServerDefinition],
        enabledSourceIDs: Set<String>
    ) throws -> AgentBulkBindingDraftPreview {
        let templates = Self.uniqueTemplateServers(templateServers)
        guard !templates.isEmpty else {
            throw AgentConfigAuthoringError.noTemplateServers
        }
        let selectedSources = targetSources.filter { enabledSourceIDs.contains($0.id) }
        guard !selectedSources.isEmpty else {
            throw AgentConfigAuthoringError.noTargetSources
        }

        let serversBySource = Dictionary(grouping: existingServers, by: \.sourcePath)
        let templateNames = Set(templates.map { Self.normalizedName($0.displayName) })
        let targetPreviews = try selectedSources.sorted(by: sourceSort).map { source -> AgentBulkBindingTargetPreview in
            let currentServers = serversBySource[source.path] ?? []
            let currentServersByName = Dictionary(
                currentServers.map { (Self.normalizedName($0.displayName), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let updatedServers = Self.servers(
                currentServers,
                replacingBindingsNamed: templateNames,
                with: templates.map { template in
                    Self.server(
                        template,
                        for: source,
                        preservingSecretReferencesFrom: currentServersByName[Self.normalizedName(template.displayName)]
                    )
                }
            )
            let preview = try safeApplier.preview(source: source, servers: updatedServers)
            return AgentBulkBindingTargetPreview(
                source: source,
                agentName: AgentRegistry.displayName(for: source.agent),
                bindingCount: templates.count,
                serverCount: updatedServers.count,
                serversAfterChange: updatedServers,
                preview: preview,
                fileSnapshot: try fileSnapshot(for: source)
            )
        }

        return AgentBulkBindingDraftPreview(
            templateSource: templateSource,
            templateBindingCount: templates.count,
            targetPreviews: targetPreviews
        )
    }

    public func applyConnectAll(
        templateServers: [ServerDefinition],
        templateSource: ConfigSource? = nil,
        targetSources: [ConfigSource],
        existingServers: [ServerDefinition],
        enabledSourceIDs: Set<String>,
        expectedFileSnapshots: [String: AgentConfigFileSnapshot]? = nil
    ) throws -> AgentBulkBindingDraftApplyResult {
        try verifyExpectedSnapshots(expectedFileSnapshots)
        let draft = try previewConnectAll(
            templateServers: templateServers,
            templateSource: templateSource,
            targetSources: targetSources,
            existingServers: existingServers,
            enabledSourceIDs: enabledSourceIDs
        )

        var snapshots: [String: Data?] = [:]
        var applied: [AgentBulkBindingApplyTargetResult] = []

        do {
            for target in draft.changedPreviews {
                snapshots[target.source.path] = try snapshot(for: target.source)
                let result = try safeApplier.apply(source: target.source, servers: target.serversAfterChange, dryRun: false)
                applied.append(AgentBulkBindingApplyTargetResult(
                    source: target.source,
                    agentName: target.agentName,
                    bindingCount: target.bindingCount,
                    serverCount: target.serverCount,
                    backupPath: result.backupPath
                ))
                try recordControlPlaneState(for: target, backupPath: result.backupPath)
            }
            let verificationReport = AgentBulkConnectVerifier().verify(
                templateServers: templateServers,
                targetSources: targetSources.filter { enabledSourceIDs.contains($0.id) }
            )
            let rollbackPlan = Self.rollbackPlan(from: applied, createdAt: now())
            if let rollbackPlan {
                try controlPlaneStore?.recordBulkRollbackTransaction(
                    plan: rollbackPlan,
                    reason: "bulk connect \(draft.templateBindingCount) bindings",
                    createdAt: rollbackPlan.createdAt
                )
            }
            return AgentBulkBindingDraftApplyResult(
                templateSource: draft.templateSource,
                templateBindingCount: draft.templateBindingCount,
                appliedTargets: applied,
                verificationReport: verificationReport,
                rollbackPlan: rollbackPlan
            )
        } catch {
            try restoreSnapshots(snapshots)
            throw AgentConfigAuthoringError.applyFailed(SecretRedactor.redactText(String(describing: error)))
        }
    }

    public func rollbackConnectAll(_ plan: AgentBulkConnectRollbackPlan) throws -> AgentBulkConnectRollbackResult {
        guard !plan.targets.isEmpty else {
            throw AgentConfigAuthoringError.rollbackUnavailable
        }

        var snapshots: [String: Data?] = [:]
        do {
            for target in plan.targets {
                snapshots[target.source.path] = try snapshot(for: target.source)
            }
            for target in plan.targets {
                try rollback(target)
            }
            try controlPlaneStore?.markBulkRollbackTransaction(plan.id, status: "rolledBack", updatedAt: now())
            return AgentBulkConnectRollbackResult(planID: plan.id, restoredTargets: plan.targets)
        } catch {
            try? restoreSnapshots(snapshots)
            try? controlPlaneStore?.markBulkRollbackTransaction(plan.id, status: "rollbackFailed", updatedAt: now())
            throw AgentConfigAuthoringError.rollbackFailed(SecretRedactor.redactText(String(describing: error)))
        }
    }

    private func recordControlPlaneState(for target: AgentBulkBindingTargetPreview, backupPath: String?) throws {
        guard let controlPlaneStore else { return }
        let timestamp = now()
        let desiredServers = target.serversAfterChange.filter { server in
            target.preview.reparsedServers.contains { $0.displayName == server.displayName }
        }
        try controlPlaneStore.upsertDesiredServerStates(desiredServers, for: target.source, enabled: true, updatedAt: timestamp)
        if let backupPath {
            _ = try controlPlaneStore.recordConfigBackup(
                source: target.source,
                backupPath: backupPath,
                reason: "bulk connect \(target.bindingCount) bindings",
                createdAt: timestamp
            )
        }
    }

    private func snapshot(for source: ConfigSource) throws -> Data? {
        let url = URL(fileURLWithPath: source.path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func fileSnapshot(for source: ConfigSource) throws -> AgentConfigFileSnapshot {
        let url = URL(fileURLWithPath: source.path)
        guard fileManager.fileExists(atPath: source.path) else {
            return AgentConfigFileSnapshot(path: source.path, exists: false, byteCount: nil, modificationTime: nil, sha256: nil)
        }
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return AgentConfigFileSnapshot(
            path: source.path,
            exists: true,
            byteCount: data.count,
            modificationTime: attributes[.modificationDate] as? Date,
            sha256: digest
        )
    }

    private func verifyExpectedSnapshots(_ snapshots: [String: AgentConfigFileSnapshot]?) throws {
        guard let snapshots else { return }
        for expected in snapshots.values {
            let current = try fileSnapshot(for: ConfigSource(agent: .unknown, path: expected.path))
            guard current == expected else {
                throw AgentConfigAuthoringError.staleTargetSource(expected.path)
            }
        }
    }

    private func restoreSnapshots(_ snapshots: [String: Data?]) throws {
        for (path, data) in snapshots {
            let url = URL(fileURLWithPath: path)
            if let data {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } else if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func rollback(_ target: AgentBulkConnectRollbackTarget) throws {
        let targetURL = URL(fileURLWithPath: target.source.path)
        if target.shouldDeleteCreatedFile {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            return
        }

        guard let backupPath = target.backupPath else {
            throw AgentConfigAuthoringError.rollbackUnavailable
        }
        let backupURL = URL(fileURLWithPath: backupPath)
        let data = try Data(contentsOf: backupURL)
        try ConfigSyntaxValidator.validate(data: data, agent: target.source.agent)
        _ = try AgentConfigParser().parse(data: data, source: target.source)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: targetURL, options: [.atomic])
    }

    private static func rollbackPlan(from applied: [AgentBulkBindingApplyTargetResult], createdAt: Date) -> AgentBulkConnectRollbackPlan? {
        guard !applied.isEmpty else { return nil }
        let targets = applied.map { target in
            AgentBulkConnectRollbackTarget(
                source: target.source,
                agentName: target.agentName,
                backupPath: target.backupPath,
                shouldDeleteCreatedFile: target.backupPath == nil
            )
        }
        return AgentBulkConnectRollbackPlan(createdAt: createdAt, targets: targets)
    }

    private static func uniqueTemplateServers(_ servers: [ServerDefinition]) -> [ServerDefinition] {
        var seen: Set<String> = []
        return servers
            .sorted {
                let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return $0.sourcePath.localizedCaseInsensitiveCompare($1.sourcePath) == .orderedAscending
            }
            .filter { server in
                let key = normalizedName(server.displayName)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    private static func servers(
        _ currentServers: [ServerDefinition],
        replacingBindingsNamed normalizedBindingNames: Set<String>,
        with replacements: [ServerDefinition]
    ) -> [ServerDefinition] {
        (currentServers.filter { !normalizedBindingNames.contains(normalizedName($0.displayName)) } + replacements)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func server(
        _ server: ServerDefinition,
        for source: ConfigSource,
        preservingSecretReferencesFrom existingServer: ServerDefinition?
    ) -> ServerDefinition {
        AgentConfigServerRetargeter.server(server, for: source, preservingSecretReferencesFrom: existingServer)
    }

    private func sourceSort(_ lhs: ConfigSource, _ rhs: ConfigSource) -> Bool {
        let leftAgent = AgentRegistry.displayName(for: lhs.agent)
        let rightAgent = AgentRegistry.displayName(for: rhs.agent)
        if leftAgent != rightAgent {
            return leftAgent.localizedCaseInsensitiveCompare(rightAgent) == .orderedAscending
        }
        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum AgentConfigServerRetargeter {
    static func server(
        _ server: ServerDefinition,
        for source: ConfigSource,
        preservingSecretReferencesFrom existingServer: ServerDefinition?
    ) -> ServerDefinition {
        ServerDefinition(
            id: ServerDefinition.canonicalID(agent: source.agent, sourcePath: source.path, name: server.displayName),
            displayName: server.displayName,
            transport: server.transport,
            command: server.command,
            args: server.args,
            url: server.url,
            headers: preservingKeychainReferences(
                templateValues: server.headers,
                existingValues: existingServer?.headers ?? [:],
                matchKeysCaseInsensitively: true
            ),
            envBindings: preservingKeychainReferences(
                templateValues: server.envBindings,
                existingValues: existingServer?.envBindings ?? [:],
                matchKeysCaseInsensitively: false
            ),
            sourcePath: source.path
        )
    }

    private static func preservingKeychainReferences(
        templateValues: [String: String],
        existingValues: [String: String],
        matchKeysCaseInsensitively: Bool
    ) -> [String: String] {
        guard !templateValues.isEmpty, !existingValues.isEmpty else { return templateValues }
        var values = templateValues
        for key in templateValues.keys {
            guard let existingValue = existingValue(for: key, in: existingValues, caseInsensitive: matchKeysCaseInsensitively),
                  KeychainSecretReference.parse(from: existingValue) != nil else {
                continue
            }
            values[key] = existingValue
        }
        return values
    }

    private static func existingValue(
        for key: String,
        in values: [String: String],
        caseInsensitive: Bool
    ) -> String? {
        if let value = values[key] { return value }
        guard caseInsensitive else { return nil }
        return values.first { existingKey, _ in
            existingKey.localizedCaseInsensitiveCompare(key) == .orderedSame
        }?.value
    }
}
