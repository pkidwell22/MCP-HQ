# Wave 7 Helper Client Parity Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Added route-level direct-core fallback policy.
  - Read-only routes may fall back: status, scan, servers, doctor, config preview, Connect All preview, and runtime explain.
  - Mutating/guarded routes do not fall back: config apply, Connect All apply, runtime start, runtime stop, and runtime restart.
- `Sources/MCPHQCore/LocalControlClientState.swift`
  - Added `sendPreferringEndpoint(...)` APIs.
  - Endpoint HTTP is tried first when configured.
  - Safe read routes can fall back to a caller-provided direct response when the endpoint is missing or unavailable.
  - Fallback state records redacted endpoint/error metadata.
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
  - Added coverage for endpoint preference, read-only direct fallback, token redaction, and no fallback for guarded mutations.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Dashboard refresh and probe refresh now prefer the configured helper endpoint for read-only scans.
  - Direct-core fallback remains available for read-only scan refresh when the endpoint is missing/unavailable.
  - Control Helper sheet shows the dashboard client's current backend and availability.

## Validation

- `swift test --filter LocalControlTransportTests --filter LocalControlAPITests`
- `swift build --product MCPHQApp`

## Remaining Caveats

- The app still needs broader adoption of `sendPreferringEndpoint(...)` for additional read-only helper-backed actions beyond dashboard scan refresh.
- Runtime controls remain helper-only and intentionally do not fall back to direct core.
