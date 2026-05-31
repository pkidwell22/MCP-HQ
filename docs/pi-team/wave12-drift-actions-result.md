# Wave 12 Drift Actions Result

## Scope completed

This slice adds executable canonical drift action plumbing for safe, preview-first canonical actions.

## Changed files

- `Sources/MCPHQCore/AgentCanonicalDriftActionExecutor.swift` (new)
  - Added `AgentCanonicalDriftActionExecutor` to map planned drift actions to single-source `previewBinding`/`applyBinding` calls.
  - Enforces review-only behavior for payload replacement actions.
  - Preserves control-plane recording through injected `SQLiteScanHistoryStore`.
- `Sources/MCPHQCore/AgentCanonicalDriftActions.swift`
  - Added `primaryActionLabel` and `isReviewOnly` on `AgentCanonicalDriftSuggestedAction` for UI-safe action presentation.
- `Sources/MCPHQCore/AgentCanonicalConfigManagerSnapshot.swift`
  - Added `suggestedActionButtonLabel` to source rows for state-facing action labels.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added canonical drift action draft creation + apply entry points.
  - Added per-source canonical-drift action draft sheet state path and preview/apply handler.
  - Kept actions preview-first and routed apply through executor with target-source guard.
  - Added `canonicalAction` to `ConfigBindingDraftSheetState` to safely retain action context.
- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
  - Extended `previewBinding` with `forcePreviewForSourceIDs` to support payload review previews when no state change is detected.
- `Tests/MCPHQCoreTests/AgentBindingDesiredStateTests.swift`
  - Added `testCanonicalDriftActionMappingAndSummarySurfaceControls` for planner/action label/state mapping assertions.
- `Tests/MCPHQCoreTests/AgentCanonicalDriftActionExecutorTests.swift` (new)
  - Added focused unit coverage for restore, disable, and payload-review-required execution behavior.

## Validation

- `swift test --filter AgentBindingDesiredStateTests`
- `swift test --filter AgentCanonicalDriftActionExecutorTests`
- `swift test`

All tests passed.

## Remaining gaps / next UI step

- Remaining gap: the canonical drift action path is wired to a shared preview/apply sheet but still does not have a dedicated “action result/error” surface for review-required payload replacement.
- Exact next UI step: add an explicit canonical-drift action row/state summary in the Config Manager binding section that clearly surfaces a review-only action state (disabled apply button + copy-safe review rationale) and separate success/failure messaging after executor apply.
