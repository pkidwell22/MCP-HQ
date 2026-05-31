# Wave 7: Native Connect All Target Profiles UI

## Goal

Add the next Config Manager slice for persisted/reusable Connect All target profiles.

The CLI/core can save and reuse named Connect All target profiles. The native app should expose enough UI to make that feature discoverable and useful.

## Requirements

- Show saved target profiles in the Config Manager flow or a small sheet.
- Let the user load a profile into the Connect All target selection.
- Let the user save the current target selection as a named profile.
- Avoid destructive writes until the existing preview/apply confirmation flow.
- Keep labels honest: profiles describe target config paths, not proof that external agents loaded them.
- Add tests at the state/model layer where practical.
- Write a result summary to `docs/pi-team/wave7-profile-ui-result.md`.

## Suggested Starting Points

- `Sources/MCPHQApp/MCPHQApp.swift`
- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
- `Tests/MCPHQCoreTests/NativeAppPreferencesTests.swift`

## Validation

```bash
swift test --filter SQLiteScanHistoryStoreTests --filter NativeAppPreferencesTests
swift build --product MCPHQApp
```
