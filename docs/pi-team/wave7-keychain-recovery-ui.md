# Wave 7: Keychain Recovery UI

## Goal

Turn the new Keychain recovery/core validation model into a visible native app flow.

## Requirements

- Surface missing/inaccessible Keychain references with safe recovery guidance.
- Use presence validation only; never read or display secret values.
- Use persisted secret-binding rows where available.
- Provide safe next actions such as "review config", "open migration/review", or "rerun validation"; avoid pretending MCP-HQ can recover an unknown secret value.
- Add tests at the model/state layer where practical.
- Write a result summary to `docs/pi-team/wave7-keychain-recovery-ui-result.md`.

## Suggested Starting Points

- `Sources/MCPHQCore/SecretManagement.swift`
- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
- `Sources/MCPHQCore/DashboardState.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
- `Tests/MCPHQCoreTests/DashboardStateBuilderTests.swift`

## Validation

```bash
swift test --filter SecretManagementTests --filter DashboardStateBuilderTests --filter SQLiteScanHistoryStoreTests
swift build --product MCPHQApp
```
