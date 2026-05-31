# Wave 6: Native App Polish

You are working in an isolated copy of MCP-HQ. Implement a focused, tested native polish slice.

Goal:
- Add one or more small production-polish improvements from the full-vision audit, preferably persisted window size/position or better first-run/empty-state behavior.
- The change should be low-risk, idiomatic SwiftUI/AppKit, and testable where practical.

Constraints:
- Keep it focused; do not redesign the app.
- Follow existing `NativeAppPreferences` and app state patterns.
- Avoid visual clutter.

Suggested inspection points:
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Sources/MCPHQCore/NativeAppPreferences.swift`
- `Tests/MCPHQCoreTests/NativeAppPreferencesTests.swift`
- `scripts/package_app.sh`

Deliverables:
- Code and tests in your copy.
- Run focused tests; run full `swift test` if practical.
- Write `docs/pi-team/wave6-app-polish-result.md` summarizing files changed, behavior, tests, and any caveats.
