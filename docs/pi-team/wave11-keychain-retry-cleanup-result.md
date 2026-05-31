# Wave 11 Keychain Retry and Cleanup Result

## Changed files

- `Sources/MCPHQCore/DashboardState.swift`
  - Added status-specific recovery action titles for Keychain recovery rows.
  - Migration-write-failed rows now surface explicit review/retry/re-secret-review labels.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - The Keychain Recovery panel now exposes the row-level secondary action, wired to rerun validation.
- `Tests/MCPHQCoreTests/DashboardStateBuilderTests.swift`
  - Added coverage that migration-write-failed rows get safe retry/cleanup action labels and remain redacted.

## Validation

- `swift test --filter DashboardStateBuilderTests --filter SecretManagementTests`
- `swift build --product MCPHQApp`

## Remaining gaps

- Retry remains validation-oriented; there is not yet a dedicated one-click cleanup/retry executor that can safely distinguish already-rolled-back failures from failures needing manual intervention.
