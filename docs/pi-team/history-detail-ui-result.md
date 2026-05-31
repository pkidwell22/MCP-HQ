# History Detail UI Result

Implemented in mainline after the initial History summary sheet.

## Changed Files

- `Sources/MCPHQApp/MCPHQApp.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`
- `docs/pi-team/history-ui-result.md`

## What Changed

- Added native History run drill-down from each summary row.
- Reused `SQLiteScanHistoryStore.load(runID:)` plus `ScanOutputFormatter` so app details share the CLI's redacted TXT/JSON rendering path.
- Added a run detail sheet with TXT/JSON switching, selectable text, Copy, and Application Support export.
- Wrapped app JSON exports with `runID`, `scannedAt`, and the redacted scan object.

## Validation

```text
swift build --product MCPHQApp
```

The full suite/package and live app smoke pass should be run after this slice is merged with any concurrent app work.

## Remaining Gaps

- History exports still write under Application Support rather than a user-chosen location.
- The detail view exposes the redacted scan result, not separate relational browsing for sources, findings, processes, or trend comparisons.
