# Wave 8: Native App Helper Read Parity

## Goal

Route the native app's read-only refresh paths through the shared local-control client boundary when the helper endpoint is configured and available, while preserving direct-core fallback for safe reads.

## Requirements

- Use `LocalControlClientStateHelper.sendPreferringEndpoint(...)` for dashboard refresh and probe refresh.
- Preserve direct in-process scan fallback when the endpoint is unavailable.
- Do not route guarded/mutating operations through a direct fallback.
- Surface the current client backend/availability somewhere useful, preferably the Control Helper sheet.
- Keep redaction and endpoint token handling intact.
- Add tests around any new model/client boundary where practical.
- Write a result summary to `docs/pi-team/wave8-app-helper-read-parity-result.md`.

## Suggested Starting Points

- `Sources/MCPHQApp/MCPHQApp.swift`
- `Sources/MCPHQCore/LocalControlClientState.swift`
- `Sources/MCPHQCore/LocalControlAPI.swift`
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`

## Validation

```bash
swift test --filter LocalControlTransportTests --filter LocalControlAPITests
swift build --product MCPHQApp
```
