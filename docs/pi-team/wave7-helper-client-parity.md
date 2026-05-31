# Wave 7: App Helper Client Parity

## Goal

Reduce the gap between the native app and the local control helper by identifying and implementing a safe next slice of shared-client usage in the app.

## Requirements

- Prefer helper-backed reads/actions where the endpoint is configured and available.
- Preserve direct-core fallback when the helper is unavailable.
- Do not route destructive operations through a less guarded path.
- Keep redaction and token handling intact.
- Add tests around any new state/client boundary.
- Write a result summary to `docs/pi-team/wave7-helper-client-parity-result.md`.

## Suggested Starting Points

- `Sources/MCPHQCore/LocalControlClientState.swift`
- `Sources/MCPHQCore/LocalControlTransport.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`

## Validation

```bash
swift test --filter LocalControlTransportTests --filter LocalControlAPITests
swift build --product MCPHQApp
```
