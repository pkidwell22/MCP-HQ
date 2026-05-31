# Wave 10: Health Cache UI and Cadence

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that makes the helper health cache visible and useful from app/CLI surfaces without building a full daemon scheduler yet.

## Context

`HealthCacheSnapshot` and `JSONHealthCacheStore` now exist. The local-control router updates the cache on scan/status and can serve matching default non-probe status from cache.

## Requirements

- Surface cache age/status in helper/control status output or app helper status where it fits naturally.
- Add a conservative refresh cadence concept if it can be done safely without a background daemon, such as a stale-cache threshold helper or status metadata.
- Keep scans explicit; do not add a forever background loop unless the existing architecture already has a safe home for it.
- Preserve direct-core fallback behavior and redaction.
- Add focused tests for cache age/status formatting and stale/fresh decisions.

## Validation

Run:

```bash
swift test --filter LocalControlAPITests
swift test --filter LocalControlTransportTests
swift test --filter MCPHQCommandTests
swift build --product MCPHQApp
```

Write a result summary to `docs/pi-team/wave10-health-cache-ui-cadence-result.md` with changed files, validation, and remaining gaps.
