# Wave 6: Native App Polish Result

## Summary

Implemented a focused native polish improvement: the MCP-HQ dashboard window now uses AppKit frame autosave, so macOS persists and restores the dashboard window size and position across launches.

## Files changed

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added a small SwiftUI/AppKit bridge (`DashboardWindowFrameAutosaveView`) that attaches to the dashboard window and calls `setFrameAutosaveName` once the underlying `NSWindow` is available.
  - Applied the bridge to the main dashboard `Window` content without changing the visual layout.
- `Sources/MCPHQCore/NativeAppPreferences.swift`
  - Added `dashboardWindowFrameAutosaveName` and a sanitizer helper for autosave names, following the existing native preferences pattern.
- `Tests/MCPHQCoreTests/NativeAppPreferencesTests.swift`
  - Added coverage for defaulting/trimming the dashboard window frame autosave name.

## Behavior

- Users can resize or move the MCP-HQ dashboard window.
- macOS stores the frame under a stable autosave name.
- On the next app launch, AppKit restores the saved size and position when possible.
- No new settings UI or visual clutter was added.

## Tests run

- `swift test --filter NativeAppPreferencesTests`
  - Passed: 4 tests, 0 failures.
- `swift test`
  - Passed: 247 tests, 0 failures, 1 skipped opt-in Keychain integration test.

## Caveats

- The frame restore path is AppKit-managed, so the automated test covers the preference/sanitization helper rather than launching the full GUI and asserting window geometry.
