# Wave 12 Lifecycle Probe Result

- Date: 2026-05-31
- Branch: `codex/wave12-lifecycle-probe`
- Mission slice: probe robustness and cancellation for slow/hanging probes (safe path, no destructive lifecycle actions)

## Changed files
- [Sources/MCPHQCore/MCPHTTPProbe.swift](docs/pi-team/../../Sources/MCPHQCore/MCPHTTPProbe.swift)
- [Sources/MCPHQCore/MCPStdioProbe.swift](docs/pi-team/../../Sources/MCPHQCore/MCPStdioProbe.swift)
- [Tests/MCPHQCoreTests/MCPHTTPProbeTests.swift](docs/pi-team/../../Tests/MCPHQCoreTests/MCPHTTPProbeTests.swift)
- [Tests/MCPHQCoreTests/MCPStdioProbeTests.swift](docs/pi-team/../../Tests/MCPHQCoreTests/MCPStdioProbeTests.swift)

## What changed
- Added phase-specific request labeling in both HTTP and stdio probes so timeout failures report the stalled step (initialize/notifications/resources/prompts/tools/ping) instead of a generic probe timeout.
- Mapped low-level `URLSession` timeout errors into phase-aware `HTTP` probe timeout errors so diagnostics remain actionable for the request in progress.
- Kept cancellation behavior and termination paths intact while ensuring explicit timeout messages are consistently redacted-safe.
- Updated tests for explicit stdio/HTTP timeout messaging and added HTTP initialize timeout coverage.

## Validation
- `swift test --filter MCPStdioProbeTests --filter MCPHTTPProbeTests`
- `swift test`

## Remaining gaps
- We still do not expose progress callbacks or per-step status into the app-level refresh UI during probe execution.
- HTTP probe still uses fixed per-call timeout from probe instance config; no global probe budget/abort threshold exists yet.
