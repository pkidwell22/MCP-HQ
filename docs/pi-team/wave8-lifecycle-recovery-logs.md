# Wave 8: Lifecycle Recovery and Logs

## Goal

Improve lifecycle/log UX for hub-owned and externally owned processes, especially recovery when helper state is stale or unavailable.

## Requirements

- Make helper-unavailable/stale-runtime states clearer in the native Lifecycle & Logs surface.
- Improve automatic log lookup for known hub-owned runtime rows.
- Keep external/agent-owned process controls read-only.
- Do not kill or control unknown/agent-owned processes.
- Preserve bounded, redacted log loading.
- Add tests at the runtime lifecycle model/formatter layer.
- Write a result summary to `docs/pi-team/wave8-lifecycle-recovery-logs-result.md`.

## Suggested Starting Points

- `Sources/MCPHQCore/RuntimeLifecycle.swift`
- `Sources/MCPHQCore/RuntimeSupervisor.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`

## Validation

```bash
swift test --filter RuntimeLifecycleTests
swift build --product MCPHQApp
```
