# Wave 4 Lifecycle & Logs Result

## Changed files

- `Sources/MCPHQCore/RuntimeLifecycle.swift`
  - Added `RuntimeLifecyclePanelLogView` to carry read-only log availability/explanation into panel rows.
  - Added `RuntimeLifecyclePanelLogLoader` and result/error models that use `RuntimeLogTailer` for bounded, redacted log tails.
  - Kept lifecycle controls explanatory/read-only in the panel state; no external/unknown process control was added.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added a log line limit picker to the native Lifecycle & Logs sheet.
  - Added per-runtime bounded log loading for rows with known log paths.
  - Added explicit read-only/unavailable log messages when MCP-HQ has no log path.
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`
  - Added pure core coverage for panel log availability and bounded log loading/redaction.
  - Added coverage for unavailable log-path explanations.

## Validation

- `swift test --filter RuntimeLifecycleTests` ✅
- `swift build --product MCPHQApp` ✅

## Remaining gaps

- The native sheet can only load logs when the panel state includes a known log path, e.g. a supervised `RuntimeInstance.logPath`.
- `ScanResult`-only observed external processes still show read-only explanations and do not fabricate log paths or controls.
- Full daemon-backed hub supervision and persistent native app lifecycle control remain future work.
