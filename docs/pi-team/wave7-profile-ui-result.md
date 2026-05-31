# Wave 7 Profile UI Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Config Manager now loads persisted Connect All target profiles from SQLite.
  - Connect All Targets can save the current target config selection as a named profile.
  - Saved profiles can be loaded into the target picker.
  - Newly saved profiles appear immediately in the still-open target picker.
  - Labels remain scoped to target config paths; profiles do not claim that external agents have reloaded configs.

## Validation

- `swift test --filter SQLiteScanHistoryStoreTests --filter MCPHQCommandTests/testConfigConnectAllCanSaveAndReuseTargetProfile --filter NativeAppPreferencesTests`
- `swift test`
- `swift build --product MCPHQApp`
- Live packaged-app smoke test: saved a temporary Connect All profile, verified the Profiles menu appeared immediately, then removed the smoke profile from the app SQLite store.
