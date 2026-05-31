# Wave 7 Keychain Recovery UI Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/DashboardState.swift`
  - Added dashboard Keychain recovery rows derived from `SecretRecoveryReport`.
  - Keychain recovery rows count as dashboard warnings and are redacted at the model boundary.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added a native "Validate Keychain" action.
  - Validates persisted secret-binding rows when available.
  - Also validates current `keychain://` config references that do not yet have persisted rows.
  - Uses presence checks only through `secretExists`; it never reads or displays secret values.
  - Shows missing/inaccessible references with safe recovery guidance, config preview, migration-review, and rerun-validation actions.
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
  - Added coverage that recovery reporting uses presence-only checks for missing and inaccessible states.
- `Tests/MCPHQCoreTests/DashboardStateBuilderTests.swift`
  - Added coverage for redacted dashboard recovery rows and safe action labels.

## Validation

- `swift test --filter SecretManagementTests --filter DashboardStateBuilderTests --filter SQLiteScanHistoryStoreTests --filter LocalControlTransportTests --filter LocalControlAPITests`

## Remaining Caveats

- MCP-HQ can detect and explain missing/inaccessible Keychain references, but it cannot recover an unknown deleted credential value. The user must re-enter the credential when needed.
- Hub-owned runtime secret injection still needs a product decision.
