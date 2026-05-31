# Pi Workstream Result: Control Helper App Actions

Merged on 2026-05-30.

## Changed Files

- `Sources/MCPHQCore/LocalControlLaunchAgent.swift`
  - Added snapshot gating for helper bootstrap and bootout.
  - Added user-facing disabled reasons for missing helper, missing plist, already loaded, and not loaded states.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added confirmation-gated Start Helper and Stop Helper actions to the Control Helper sheet.
  - Start/Stop call the existing `launchctl bootstrap` and `launchctl bootout` manager paths, refresh status afterward, and show redacted command output.
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
  - Covered the new app-facing helper action gating states.
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## Validation

- `swift test --filter LocalControlTransportTests`
- `swift build --product MCPHQApp`

## Remaining Gaps

- The app still mostly talks to core directly instead of using the helper-backed local-control client.
- Production token generation/storage for the loopback helper still needs a final decision.
- Background scan cadence and health cache are not wired yet.
