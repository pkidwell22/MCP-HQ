# Control plane UI slice result

## Changed files

- `Sources/MCPHQCore/LocalControlLaunchAgent.swift`
  - Added helper path resolution for packaged `Contents/MacOS/mcphq`, sibling executables, and `PATH`.
  - Added endpoint availability and status snapshot models for native helper UI.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added a toolbar affordance: **Control Helper**.
  - Added a native `ControlHelperSheet` showing LaunchAgent plist installed state, launchd loaded/not-loaded/unknown state, endpoint availability, and helper path/source.
  - Added safe view-model actions to refresh helper status, preview LaunchAgent plist install, and install the plist only.
  - The install/preview path resolves `Contents/MacOS/mcphq` first via `LocalControlHelperPathResolver`; the sheet explicitly does not run `launchctl bootstrap` or `bootout`.
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
  - Added dry-run plist install coverage that verifies no plist file is written.
  - Added helper path resolver coverage for bundled `Contents/MacOS/mcphq` preference.
  - Added snapshot label/availability coverage for installed, launchd, endpoint, helper path, and missing-helper reason.

## Validation

- Ran `swift test --filter LocalControlTransportTests`.
- Result: passed — 18 tests executed, 0 failures.

## Remaining gaps

- The app still writes the plist directly through core, not through a helper-backed IPC path.
- The sheet does not start/stop the LaunchAgent; bootstrap/bootout remain CLI/manual follow-up actions by design for this safe slice.
- Endpoint availability refresh is synchronous and lightweight, but could be moved to an async task for better UI responsiveness.
- No SwiftUI snapshot tests were added for the new sheet; coverage is focused on core status/path/install helpers.
