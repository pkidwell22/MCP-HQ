# Wave 10 Canonical Config Manager UI Result

## Changed files

- `Sources/MCPHQCore/AgentCanonicalConfigManagerSnapshot.swift`
  - Added a UI-facing canonical snapshot adapter over `AgentCanonicalAuthoringModel`.
  - Summarizes desired on/off, observed-only bindings, drift counts, per-source intent, drift labels, and redacted payload mismatch details.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Config Manager binding rows now come from the canonical snapshot instead of rebuilding desired state from scan-shaped rows.
  - Added a canonical state disclosure that shows per-source intent and drift, including payload mismatch details when available.
- `Tests/MCPHQCoreTests/AgentBindingDesiredStateTests.swift`
  - Added coverage for canonical Config Manager summary/drift rows.

## Validation

- `swift test --filter AgentBindingDesiredStateTests`
- `swift build --product MCPHQApp`

## Remaining gaps

- Canonical payload drift is visible but not yet actionable; future UI should guide resolution and cleanup stale intent rows.
