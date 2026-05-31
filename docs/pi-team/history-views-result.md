# History views result

## Changed files

- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
  - Added `SQLiteScanHistoryRunSummary`.
  - Added `listRunSummaries(limit:)` for newest-first, bounded summary queries.
- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Added `mcphq history list [--json] [--limit count|-n count]`.
  - Text output shows run timestamp, run ID, and source/server/finding/process/probe counts.
  - JSON output encodes the same summaries with ISO-8601 dates.
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
  - Added temp-SQLite coverage for latest-N summary ordering, limits, and persisted counts.
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
  - Added temp-SQLite CLI coverage for text and JSON `history list` output.

## Validation

- Ran `swift test --filter SQLiteScanHistoryStoreTests`.
- Ran `swift test --filter MCPHQCommandTests/testHistory`.
- Both focused runs passed.

## Remaining gaps

- CLI `scan` still does not write to history; history is populated by app refresh/probe paths unless callers seed/use the store directly.
- App surface does not yet include a historical run browser.
- History API is summary-only; no dedicated CLI/app drill-down into per-run sources, servers, findings, or process snapshots yet.
