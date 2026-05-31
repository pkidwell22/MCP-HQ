# Lifecycle Panel Result

Merged from the `lifecycle-panel` Pi worker with small UI/string adaptations.

## Changed Files

- `Sources/MCPHQCore/RuntimeLifecycle.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## What Changed

- Added redacted `logFilePath` to lifecycle explanations.
- Added read-only lifecycle panel models and formatter.
- Added safe copy-only actions:
  - copy runtime ID
  - copy a redacted `mcphq logs --file ...` command when a known log path exists
- Added a native Lifecycle & Logs sheet with ownership/status/control/log explanations.
- No start/stop/restart/kill UI actions were added.

## Validation

Worker validation:

```text
swift test
swift build
```

Result in the isolated copy: full suite and app build passed with the expected Keychain integration skip.

Mainline validation is still required after merge with concurrent history/control/Doctor changes.

## Remaining Gaps

- The sheet uses the latest scan and known supervised runtime metadata; it does not automatically discover arbitrary agent log files.
- Hub-owned start/stop/restart stays out of the UI until helper-backed supervision is persistent.
- No inline log viewer yet.
