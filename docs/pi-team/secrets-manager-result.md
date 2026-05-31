# Pi Workstream Result: Config Manager Secrets

Merged and adapted on 2026-05-30.

## Changed Files

- `Sources/MCPHQCore/SecretManagement.swift`
  - Added `SecretMigrationPlan` and `SecretBatchMigrationResult`.
  - Added batch planning/migration APIs for arrays of `ServerDefinition`.
  - Hardened detected-secret redaction so short sensitive values are still reported as `<redacted>`.
  - Avoids migrating plain path values just because they are long/token-like.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added per-binding/per-server literal secret counts in Config Manager.
  - Added a binding-level Secret Review sheet that never displays plaintext values.
  - Added guarded Config Manager migration into macOS Keychain references.
  - Restores config snapshots and deletes newly written Keychain references if a later config write fails.
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
  - Added batch migration coverage with `InMemorySecretStore`.
  - Verifies short sensitive values do not appear in planning output.
  - Verifies `_PATH` values are not treated as secrets by generic token-shape detection.
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## Validation

- `swift test --filter SecretManagementTests`
- `swift build --product MCPHQApp`

## Remaining Gaps

- Add richer recovery UI for Keychain write failures.
- Decide how hub-owned launch resolves Keychain references into process environments.
- Add app-level UI smoke/snapshot coverage for the Secret Review sheet.
