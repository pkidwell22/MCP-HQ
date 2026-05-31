# Wave 4 Settings Polish Result

## Changed Files

- `Sources/MCPHQCore/NativeAppPreferences.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/NativeAppPreferencesTests.swift`
- `docs/pi-team/wave4-settings-polish-result.md`

## What Changed

- Added a native Settings sheet with persisted UserDefaults/AppStorage preferences for:
  - default History run limit,
  - preferred export format (`TXT` or `JSON`),
  - probe-on-refresh behavior,
  - local control helper endpoint file path.
- Wired the History limit into `DashboardViewModel.refreshHistorySummaries`, so the History sheet now loads the user-selected number of recent runs.
- Wired probe-on-refresh into the Refresh action; when enabled, Refresh delegates to the existing live probe path.
- Wired the endpoint file path into Control Helper status and LaunchAgent preview/install configuration.
- Wired preferred export format into the History run detail sheet's default/remembered segmented format selection.
- Improved the empty History state with an icon and clearer next-step copy.
- Added focused pure helper tests for settings bounds, export format fallback, and endpoint path sanitization.

## Validation

```text
swift build --product MCPHQApp
swift test --filter NativeAppPreferencesTests
```

Passed: app build completed and 3 focused settings-helper tests passed.
