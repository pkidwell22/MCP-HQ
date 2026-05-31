# Pi Workstream Result: Doctor Export Formats

Merged on 2026-05-30.

## Changed Files

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added a Doctor export format model for text and JSON.
  - Replaced the single Export button with an Export menu in the detailed Doctor panel.
  - Writes `doctor-report.txt` or `doctor-report.json` under Application Support.
- `Tests/MCPHQCoreTests/DoctorReportTests.swift`
  - Added JSON formatter coverage that decodes the output and verifies secret redaction.
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## Validation

- `swift test --filter DoctorReportTests`
- `swift build --product MCPHQApp`

## Remaining Gaps

- Add richer native destinations such as a save panel or Share sheet.
- Consider timestamped Doctor exports if users need historical report files beyond SQLite scan history.
