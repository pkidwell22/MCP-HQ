# Wave 8 App Helper Read Parity Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Dashboard refresh and probe refresh now go through `LocalControlClientStateHelper.sendPreferringEndpoint(...)`.
  - Direct-core fallback remains available for read-only scan refresh when the helper endpoint is unavailable.
  - Control Helper shows the dashboard read client backend and availability.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Scan-like read routes can use explicit `targetSources`, allowing the app to send the same source set it would scan directly.
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`
  - Added coverage for scan requests using explicit target sources.

## Validation

- `swift test --filter AgentConfigRendererTests --filter LocalControlAPITests --filter PackageAppScriptTests`
- `swift test --filter RuntimeLifecycleTests --filter LocalControlAPITests --filter MCPHQCommandTests`
