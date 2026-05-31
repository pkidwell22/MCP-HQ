import Foundation

public enum AgentCanonicalDriftActionExecutorError: Error, Equatable, CustomStringConvertible {
    case cannotApplyReviewRequiredAction(AgentCanonicalDriftActionKind)

    public var description: String {
        switch self {
        case .cannotApplyReviewRequiredAction:
            return "This canonical drift action is review-only and cannot be applied directly."
        }
    }
}

public struct AgentCanonicalDriftActionExecutor {
    private let planner: AgentConfigAuthoringPlanner

    public init(controlPlaneStore: SQLiteScanHistoryStore? = nil) {
        self.planner = AgentConfigAuthoringPlanner(controlPlaneStore: controlPlaneStore)
    }

    public func canApply(_ action: AgentCanonicalDriftSuggestedAction) -> Bool {
        action.operation != .payloadReplacementPreview
    }

    public func draft(
        for action: AgentCanonicalDriftSuggestedAction,
        templateServer: ServerDefinition,
        targetSource: ConfigSource,
        existingServers: [ServerDefinition]
    ) throws -> AgentBindingDraftPreview {
        let enabledSourceIDs = enabledSourceIDs(for: action)
        let forcePreviewForSourceIDs = action.operation == .payloadReplacementPreview ? Set([targetSource.id]) : []

        return try planner.previewBinding(
            templateServer: templateServer,
            targetSources: [targetSource],
            existingServers: existingServers,
            enabledSourceIDs: enabledSourceIDs,
            forcePreviewForSourceIDs: forcePreviewForSourceIDs
        )
    }

    public func apply(
        for action: AgentCanonicalDriftSuggestedAction,
        templateServer: ServerDefinition,
        targetSource: ConfigSource,
        existingServers: [ServerDefinition]
    ) throws -> AgentBindingDraftApplyResult {
        guard canApply(action) else {
            throw AgentCanonicalDriftActionExecutorError.cannotApplyReviewRequiredAction(action.kind)
        }

        let enabledSourceIDs = enabledSourceIDs(for: action)
        return try planner.applyBinding(
            templateServer: templateServer,
            targetSources: [targetSource],
            existingServers: existingServers,
            enabledSourceIDs: enabledSourceIDs
        )
    }

    private func enabledSourceIDs(for action: AgentCanonicalDriftSuggestedAction) -> Set<String> {
        if action.operation == .bindingDraftDisable {
            return []
        }
        return [action.sourceID]
    }
}
