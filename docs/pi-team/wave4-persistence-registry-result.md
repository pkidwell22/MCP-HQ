# Wave 4 persistence registry result

## Changed files

- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
  - Added persisted Doctor report history alongside existing scan history.
  - Added `SQLiteDoctorReportSummary` and `SQLiteStoredDoctorReport` public models.
  - Added idempotent v2 schema objects: `doctor_reports`, `doctor_report_findings`, and query indexes.
  - Added `saveDoctorReport`, `loadDoctorReport`, and `listDoctorReportSummaries` APIs.
  - Existing `save(_:)` now writes a matching redacted Doctor report for the scan run ID while preserving existing scan history APIs.
  - Doctor report persistence stores redacted report JSON plus queryable finding rows and severity/source/server counts.
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
  - Added migration idempotency coverage for the Doctor report tables.
  - Added save/list/load coverage for Doctor report summaries and full reports.
  - Added secret-redaction coverage proving Doctor report history does not persist plaintext secrets.

## Validation

- Ran `swift test --filter SQLiteScanHistoryStoreTests` — passed.

## Remaining gaps

- CLI/UI listing is still scan-history-first; Doctor report history is exposed through core APIs for now.
- Existing scan `result_json` compatibility is preserved, so this slice only guarantees redaction for the new Doctor report history payload and finding rows.
