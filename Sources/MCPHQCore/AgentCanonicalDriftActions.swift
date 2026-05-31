import Foundation

public enum AgentCanonicalDriftActionKind: String, Codable, Equatable, Sendable {
    case restoreMissingDesiredBinding = "restore_missing_desired_binding"
    case removeDisabledBinding = "remove_disabled_binding"
    case replacePayloadWithDesiredState = "replace_payload_with_desired_state"
}

public enum AgentCanonicalDriftActionRisk: String, Codable, Equatable, Sendable {
    case low
    case reviewRequired = "review_required"
}

public enum AgentCanonicalDriftActionOperation: String, Codable, Equatable, Sendable {
    case bindingDraftEnable = "binding_draft_enable"
    case bindingDraftDisable = "binding_draft_disable"
    case payloadReplacementPreview = "payload_replacement_preview"
}

public struct AgentCanonicalDriftSuggestedAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AgentCanonicalDriftActionKind
    public let risk: AgentCanonicalDriftActionRisk
    public let operation: AgentCanonicalDriftActionOperation
    public let normalizedName: String
    public let displayName: String
    public let source: ConfigSource
    public let sourceID: String
    public let agentName: String
    public let intent: AgentCanonicalSourceBindingIntent
    public let driftStatus: AgentCanonicalBindingDriftStatus
    public let title: String
    public let detailText: String
    public let payloadDriftDetails: [String]

    public var isLowRisk: Bool { risk == .low }

    public init(
        kind: AgentCanonicalDriftActionKind,
        risk: AgentCanonicalDriftActionRisk,
        operation: AgentCanonicalDriftActionOperation,
        normalizedName: String,
        displayName: String,
        source: ConfigSource,
        agentName: String,
        intent: AgentCanonicalSourceBindingIntent,
        driftStatus: AgentCanonicalBindingDriftStatus,
        title: String,
        detailText: String,
        payloadDriftDetails: [String] = []
    ) {
        self.kind = kind
        self.risk = risk
        self.operation = operation
        self.normalizedName = normalizedName
        self.displayName = displayName
        self.source = source
        self.sourceID = source.id
        self.agentName = agentName
        self.intent = intent
        self.driftStatus = driftStatus
        self.title = SecretRedactor.redactText(title)
        self.detailText = SecretRedactor.redactText(detailText)
        self.payloadDriftDetails = payloadDriftDetails.map(SecretRedactor.redactText)
        self.id = [normalizedName, source.id, kind.rawValue].joined(separator: ":")
    }
}

public struct AgentCanonicalDriftActionPlan: Codable, Equatable, Sendable {
    public let actions: [AgentCanonicalDriftSuggestedAction]

    public var count: Int { actions.count }
    public var lowRiskActions: [AgentCanonicalDriftSuggestedAction] { actions.filter(\.isLowRisk) }

    public init(actions: [AgentCanonicalDriftSuggestedAction]) {
        self.actions = actions.sorted(by: Self.actionSort)
    }

    public init(model: AgentCanonicalAuthoringModel) {
        self.init(actions: AgentCanonicalDriftActionPlanner().suggestedActions(for: model))
    }

    public func actions(for normalizedName: String) -> [AgentCanonicalDriftSuggestedAction] {
        let normalized = AgentBindingDesiredStateIndex.normalizedName(normalizedName)
        return actions.filter { $0.normalizedName == normalized }
    }

    private static func actionSort(_ lhs: AgentCanonicalDriftSuggestedAction, _ rhs: AgentCanonicalDriftSuggestedAction) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        if lhs.agentName != rhs.agentName {
            return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
        }
        if lhs.source.path != rhs.source.path {
            return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

public struct AgentCanonicalDriftActionPlanner: Sendable {
    public init() {}

    public func plan(for model: AgentCanonicalAuthoringModel) -> AgentCanonicalDriftActionPlan {
        AgentCanonicalDriftActionPlan(actions: suggestedActions(for: model))
    }

    public func suggestedActions(for model: AgentCanonicalAuthoringModel) -> [AgentCanonicalDriftSuggestedAction] {
        model.bindings.flatMap { suggestedActions(for: $0) }.sorted(by: actionSort)
    }

    public func suggestedActions(for summary: AgentCanonicalBindingSummary) -> [AgentCanonicalDriftSuggestedAction] {
        summary.sourceBindings.compactMap(suggestedAction(for:)).sorted(by: actionSort)
    }

    public func suggestedAction(for binding: AgentCanonicalSourceBinding) -> AgentCanonicalDriftSuggestedAction? {
        switch binding.driftStatus {
        case .missingFromScan:
            guard binding.intent == .desiredEnabled else { return nil }
            return AgentCanonicalDriftSuggestedAction(
                kind: .restoreMissingDesiredBinding,
                risk: .low,
                operation: .bindingDraftEnable,
                normalizedName: binding.identity.normalizedName,
                displayName: binding.identity.displayName,
                source: binding.source,
                agentName: binding.agentName,
                intent: binding.intent,
                driftStatus: binding.driftStatus,
                title: "Add \(binding.identity.displayName) to \(binding.agentName)",
                detailText: "Desired state is enabled but no scanned binding was found. Add the saved desired binding to \(binding.agentName)."
            )
        case .presentButDisabled:
            guard binding.intent == .desiredDisabled else { return nil }
            return AgentCanonicalDriftSuggestedAction(
                kind: .removeDisabledBinding,
                risk: .low,
                operation: .bindingDraftDisable,
                normalizedName: binding.identity.normalizedName,
                displayName: binding.identity.displayName,
                source: binding.source,
                agentName: binding.agentName,
                intent: binding.intent,
                driftStatus: binding.driftStatus,
                title: "Remove \(binding.identity.displayName) from \(binding.agentName)",
                detailText: "Desired state is disabled but the binding is still present. Remove it from \(binding.agentName)."
            )
        case .payloadMismatch:
            guard binding.intent == .desiredEnabled else { return nil }
            let detailSuffix = binding.payloadDriftDetails.isEmpty ? "payload differs" : binding.payloadDriftDetails.joined(separator: "; ")
            return AgentCanonicalDriftSuggestedAction(
                kind: .replacePayloadWithDesiredState,
                risk: .reviewRequired,
                operation: .payloadReplacementPreview,
                normalizedName: binding.identity.normalizedName,
                displayName: binding.identity.displayName,
                source: binding.source,
                agentName: binding.agentName,
                intent: binding.intent,
                driftStatus: binding.driftStatus,
                title: "Review \(binding.identity.displayName) payload in \(binding.agentName)",
                detailText: "Desired state is enabled and present, but \(detailSuffix). Preview replacing this binding with the saved desired payload before applying.",
                payloadDriftDetails: binding.payloadDriftDetails
            )
        case .inSync, .observedOnly:
            return nil
        }
    }

    private func actionSort(_ lhs: AgentCanonicalDriftSuggestedAction, _ rhs: AgentCanonicalDriftSuggestedAction) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        if lhs.agentName != rhs.agentName {
            return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
        }
        if lhs.source.path != rhs.source.path {
            return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
