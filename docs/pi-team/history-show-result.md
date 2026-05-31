# History Show Result

Implemented in mainline while the Pi team worked in isolated copies.

## Changed Files

- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## What Changed

- Added `SQLiteScanHistoryStore.load(runID:)` to retrieve a specific stored scan run.
- Added `mcphq history show <run-id> [--json]`.
- Text output wraps the existing redacted scan formatter with run metadata.
- JSON output wraps the existing redacted scan JSON under `scan`, plus `runID` and `scannedAt`.
- Added tests that confirm raw stored secret values are not emitted by history text or JSON output.

## Validation

```text
swift test --filter SQLiteScanHistoryStoreTests
swift test --filter MCPHQCommandTests/testHistory
```

Both focused test sets passed.

## Remaining Gaps

- Native app history browsing still needs a real UI.
- `history show` currently exports the scan result detail, not separate relational tables for sources/findings/process snapshots.
