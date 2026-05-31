# Wave 4 Control Parity Result

## Scope

Focused local control API parity for CLI commands that already have router support.

## Changed Files

- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
- `docs/pi-team/wave4-control-parity-result.md`

## What Changed

- Added `--endpoint-file` support to `mcphq scan`.
  - With an endpoint file, scan dispatches through `LocalControlClientStateHelper` / `LocalControlHTTPClient` to the `.scan` local-control route.
  - Without an endpoint file, scan preserves the existing direct in-process behavior.
- Added `--endpoint-file` support to `mcphq doctor`.
  - With an endpoint file, doctor dispatches through the shared local-control client/helper boundary to the `.doctor` route.
  - Without an endpoint file, doctor preserves the existing direct in-process scan/report path.
- Updated CLI usage text for scan/doctor endpoint-file support.
- Added endpoint-backed command tests proving remote HTTP-backed behavior and redaction for scan output and doctor probe findings.

## Notes / Constraints

- Endpoint-backed `scan` and `doctor` accept at most one `--source`, matching the current `LocalControlRequest.source` shape.
- Endpoint-backed probes are requested only when `--probe` is present, so the helper is not asked to run live probes for ordinary scan/doctor calls.

## Validation

```text
swift test --filter MCPHQCommandTests/testScanCanUseEndpointBackedHTTPClientAndRedactsSecrets --filter MCPHQCommandTests/testDoctorCanUseEndpointBackedHTTPClientAndRedactsProbeSecrets
swift test --filter LocalControl --filter MCPHQCommandTests
swift test
```

Result: passed. Full suite executed 190 tests with 1 expected Keychain integration skip.
