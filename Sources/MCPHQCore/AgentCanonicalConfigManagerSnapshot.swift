import Foundation

public struct AgentCanonicalConfigManagerSnapshot: Equatable, Sendable {
    public let summaryText: String
    public let bindingRows: [AgentCanonicalConfigManagerBindingRow]

    public init(model: AgentCanonicalAuthoringModel) {
        self.summaryText = model.summaryText
        self.bindingRows = model.bindings.map(AgentCanonicalConfigManagerBindingRow.init(summary:))
    }

    public var bindingCount: Int { bindingRows.count }
    public var driftCount: Int { bindingRows.reduce(0) { $0 + $1.driftCount } }

    public func binding(named name: String) -> AgentCanonicalConfigManagerBindingRow? {
        let normalized = AgentBindingDesiredStateIndex.normalizedName(name)
        return bindingRows.first { $0.normalizedName == normalized }
    }
}

public struct AgentCanonicalConfigManagerBindingRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let normalizedName: String
    public let displayName: String
    public let transportLabel: String
    public let agentNames: [String]
    public let enabledSourceIDs: Set<String>
    public let desiredStateSourceIDs: Set<String>
    public let hasPersistedDesiredState: Bool
    public let sourceCount: Int
    public let desiredEnabledCount: Int
    public let desiredDisabledCount: Int
    public let observedOnlyCount: Int
    public let driftCount: Int
    public let summaryText: String
    public let driftText: String
    public let sourceRows: [AgentCanonicalConfigManagerSourceRow]
    public let templateServer: ServerDefinition

    public init(summary: AgentCanonicalBindingSummary) {
        let actionsBySourceID = Dictionary(
            uniqueKeysWithValues: AgentCanonicalDriftActionPlanner()
                .suggestedActions(for: summary)
                .map { ($0.sourceID, $0) }
        )
        let sourceRows = summary.sourceBindings.map { binding in
            AgentCanonicalConfigManagerSourceRow(binding: binding, suggestedAction: actionsBySourceID[binding.source.id])
        }
        let enabledSourceIDs = Set(sourceRows.filter(\.isEnabledForAuthoring).map(\.sourceID))
        self.id = summary.identity.id
        self.normalizedName = summary.identity.normalizedName
        self.displayName = summary.identity.displayName
        self.transportLabel = summary.templateServer.transport.rawValue
        self.agentNames = Set(sourceRows.filter { enabledSourceIDs.contains($0.sourceID) }.map(\.agentName)).sorted()
        self.enabledSourceIDs = enabledSourceIDs
        self.desiredStateSourceIDs = Set(sourceRows.filter { $0.intent == .desiredEnabled }.map(\.sourceID))
        self.hasPersistedDesiredState = sourceRows.contains { $0.intent != .observedOnly }
        self.sourceCount = enabledSourceIDs.count
        self.desiredEnabledCount = summary.desiredEnabledCount
        self.desiredDisabledCount = summary.desiredDisabledCount
        self.observedOnlyCount = summary.observedOnlyCount
        self.driftCount = summary.driftCount
        self.summaryText = Self.summaryText(
            desiredEnabledCount: summary.desiredEnabledCount,
            desiredDisabledCount: summary.desiredDisabledCount,
            observedOnlyCount: summary.observedOnlyCount
        )
        self.driftText = Self.driftText(sourceRows: sourceRows)
        self.sourceRows = sourceRows
        self.templateServer = summary.templateServer
    }

    private static func summaryText(
        desiredEnabledCount: Int,
        desiredDisabledCount: Int,
        observedOnlyCount: Int
    ) -> String {
        [
            "\(desiredEnabledCount) desired on",
            "\(desiredDisabledCount) desired off",
            "\(observedOnlyCount) observed only",
        ].joined(separator: " | ")
    }

    private static func driftText(sourceRows: [AgentCanonicalConfigManagerSourceRow]) -> String {
        let grouped = Dictionary(grouping: sourceRows.filter(\.isDrift), by: \.driftStatus)
        let total = grouped.values.reduce(0) { $0 + $1.count }
        guard total > 0 else { return "No drift" }

        var parts: [String] = []
        let counts: [(AgentCanonicalBindingDriftStatus, String)] = [
            (.missingFromScan, "missing"),
            (.presentButDisabled, "disabled but present"),
            (.payloadMismatch, "payload mismatch"),
        ]
        for (status, label) in counts {
            let count = grouped[status]?.count ?? 0
            if count > 0 { parts.append("\(count) \(label)") }
        }
        return "\(total) drift\(total == 1 ? "" : "s"): " + parts.joined(separator: ", ")
    }
}

public struct AgentCanonicalConfigManagerSourceRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let agentName: String
    public let sourcePath: String
    public let intent: AgentCanonicalSourceBindingIntent
    public let driftStatus: AgentCanonicalBindingDriftStatus
    public let payloadDriftDetails: [String]
    public let isPresentInScan: Bool
    public let scannedServerID: String?
    public let intentLabel: String
    public let driftLabel: String
    public let detailText: String
    public let suggestedAction: AgentCanonicalDriftSuggestedAction?
    public let suggestedActionText: String?
    public let isDrift: Bool
    public let isEnabledForAuthoring: Bool

    public init(binding: AgentCanonicalSourceBinding, suggestedAction: AgentCanonicalDriftSuggestedAction? = nil) {
        self.id = binding.id
        self.sourceID = binding.source.id
        self.agentName = binding.agentName
        self.sourcePath = binding.source.path
        self.intent = binding.intent
        self.driftStatus = binding.driftStatus
        self.payloadDriftDetails = binding.payloadDriftDetails
        self.isPresentInScan = binding.isPresentInScan
        self.scannedServerID = binding.scannedServerID
        self.intentLabel = Self.intentLabel(binding.intent)
        self.driftLabel = Self.driftLabel(binding.driftStatus)
        self.detailText = Self.detailText(binding: binding)
        self.suggestedAction = suggestedAction
        self.suggestedActionText = suggestedAction?.isLowRisk == true ? suggestedAction?.title : nil
        self.isDrift = binding.driftStatus.isDrift
        self.isEnabledForAuthoring = binding.intent == .desiredEnabled || binding.intent == .observedOnly
    }

    private static func intentLabel(_ intent: AgentCanonicalSourceBindingIntent) -> String {
        switch intent {
        case .desiredEnabled:
            return "desired on"
        case .desiredDisabled:
            return "desired off"
        case .observedOnly:
            return "observed"
        }
    }

    private static func driftLabel(_ status: AgentCanonicalBindingDriftStatus) -> String {
        switch status {
        case .inSync:
            return "in sync"
        case .missingFromScan:
            return "missing"
        case .presentButDisabled:
            return "disabled but present"
        case .payloadMismatch:
            return "payload mismatch"
        case .observedOnly:
            return "observed only"
        }
    }

    private static func detailText(binding: AgentCanonicalSourceBinding) -> String {
        guard binding.driftStatus == .payloadMismatch, !binding.payloadDriftDetails.isEmpty else {
            return driftLabel(binding.driftStatus)
        }
        return SecretRedactor.redactText(binding.payloadDriftDetails.joined(separator: "; "))
    }
}
