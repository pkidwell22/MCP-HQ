# Wave 12 Safe Config Apply Result

## Implemented changes

- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
  - Added file snapshot capture to single-source preview targets.
  - Extended `applyBinding(...)` with optional `expectedFileSnapshots` input.
  - Added explicit stale-preview verification using existing snapshot verifier before applying single-source edits.
  - Updated `previewBinding(...)` and `applyBinding(...)` call paths so single-source apply can reject out-of-date previews.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Passed `draftState.draft?.fileSnapshotsByPath` into `applyBinding(...)` from `applyBindingDraft(...)`.
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
  - Added `testApplyBindingRejectsStalePreviewSnapshot` to validate stale single-source preview rejection + no write side effects.
- `docs/pi-team/wave12-safe-config-apply-result.md`
  - Added this result summary.

## Tests run

- `swift test --filter AgentConfigAuthoringTests`

## Remaining gaps

- Core/API single-source preview/apply route (`LocalControlRequest`/`LocalControlRouter`) does not yet include preview snapshot payloads, so stale rejection is currently enforced only for in-app direct-apply and planner-call sites that pass snapshots.
- CLI `config` commands that apply without endpoint-file mode use `AgentConfigSafeApplier` directly and therefore do not participate in stale-preview rejection.
- Remaining hardening items from the broader spec (parse/write verification report detail, rollback-on-verification-failure plumbing, richer secret-safe render guarantees) are still pending.
