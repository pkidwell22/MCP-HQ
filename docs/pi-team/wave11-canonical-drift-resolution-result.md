# Wave 11: Canonical Drift Resolution Result

## Changed files

- `Sources/MCPHQCore/AgentCanonicalDriftActions.swift`
  - Added secret-safe, deterministic suggested drift action models and planner.
  - Covers missing desired bindings, present-but-disabled bindings, and payload mismatches.
  - Includes action kind, risk, operation hint, target source metadata, redacted detail text, and deterministic IDs.
- `Sources/MCPHQCore/AgentCanonicalConfigManagerSnapshot.swift`
  - Adds optional suggested actions to source rows.
  - Exposes low-risk suggested action text while keeping review-required payload rewrites out of low-risk UI text.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Shows low-risk suggested action text in the Config Manager canonical state disclosure.
- `Tests/MCPHQCoreTests/AgentBindingDesiredStateTests.swift`
  - Added focused tests for deterministic action generation, operation hints, low-risk filtering, redaction, and snapshot exposure.

## Validation

- `swift test --filter AgentBindingDesiredStateTests --filter AgentConfigAuthoringTests`
- `swift build --product MCPHQApp`

## Remaining gaps

- Suggested actions are model/helper output plus low-risk UI text only; no UI execution path was added.
- Payload mismatch actions are marked `review_required` and provide a preview operation hint, but there is not yet a dedicated payload replacement draft/apply executor.
- Observed-only bindings remain visible drift context but do not currently receive a suggested action.
