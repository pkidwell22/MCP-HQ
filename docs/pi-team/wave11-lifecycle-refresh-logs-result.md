# Wave 11 Lifecycle Refresh and Logs Result

## Changed files

- `Sources/MCPHQCore/RuntimeLifecycle.swift`
  - Added bounded, read-only `RuntimeLifecycleLogPathResolver`.
  - Enriches hub-owned runtime explanations with auto-located supervisor logs when a persisted `logPath` is missing.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Wires `request.logDirectory` into `runtime_explain`.
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`
  - Added log resolver tests.
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`
  - Added API coverage for automatic log lookup.

## Validation

- `swift test --filter RuntimeLifecycleTests --filter LocalControlAPITests`
- `swift build --product MCPHQApp`

## Remaining gaps

- This adds safe automatic lookup for known hub-owned log files; it does not add a native live refresh timer or broaden reads to externally owned agent logs.
