# History UI Result

Merged from the `history-ui` Pi worker with small mainline adaptations.

## Changed Files

- `Sources/MCPHQApp/MCPHQApp.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## What Changed

- Added `recentHistorySummaries` to `DashboardViewModel`.
- Refresh/probe persistence now refreshes the in-memory history summary list.
- Added a native History toolbar/detail affordance.
- Added a History sheet that shows recent run timestamps, run IDs, and source/server/finding/process/probe counts from `SQLiteScanHistoryStore.listRunSummaries(limit:)`.

## Validation

The worker ran:

```text
swift test
```

Result in the isolated copy: 174 tests passed with the expected Keychain integration skip.

Mainline verification is still required after merging with the concurrent `history show` CLI slice.

## Remaining Gaps

- The first mainline follow-up added selected-run redacted TXT/JSON detail, copy, and Application Support export.
- Remaining history work is deeper relational browsing, trends, and user-chosen export destinations.
