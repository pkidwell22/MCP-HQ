# Wave 9 Authoring Model Result

## Changed files

- `Sources/MCPHQCore/AgentBindingDesiredState.swift`
  - Added canonical authoring model types for server identity, per-source binding intent, drift status, source binding rows, binding summaries, and top-level summary counts.
  - Added `AgentCanonicalAuthoringModel` builder that merges the latest `ScanResult` with persisted `SQLiteDesiredServerState` rows.
  - Desired-only bindings can now exist independently of the latest scan result.
- `Tests/MCPHQCoreTests/AgentBindingDesiredStateTests.swift`
  - Added coverage for scan plus desired-state merging, drift classification, observed-only scan bindings, and desired-only bindings missing from the latest scan.

## Validation

- `swift test --filter LocalControlAPITests --filter ScanResultStoreTests --filter AgentBindingDesiredStateTests`

## Remaining gaps

- Config Manager still uses its existing scan-row-derived UI state; a future UI slice should wire it to the canonical model.
- Drift labels are intentionally coarse: `missing_from_scan`, `present_but_disabled`, `observed_only`, and `in_sync`.
- Payload drift does not yet compare command, args, env, or header details for bindings present in both desired state and scan.
