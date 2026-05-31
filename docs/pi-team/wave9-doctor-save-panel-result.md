# Wave 9 Doctor Save Panel Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/DoctorReport.swift`
  - Added `DoctorReportExportFormat` and `DoctorReportExporter` so Doctor report rendering/writing is shared and testable in core.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Preserved the existing Application Support export path.
  - Added a macOS `NSSavePanel`-backed `saveDoctorReportAs` flow for user-chosen TXT/JSON destinations.
  - Updated the Doctor export menu with Application Support and Choose Destination sections.
- `Tests/MCPHQCoreTests/DoctorReportTests.swift`
  - Added coverage that exporting to an arbitrary chosen destination writes redacted JSON and never includes the original secret.

## Validation

- `swift test --filter DoctorReportTests --filter RuntimeLifecycleTests`

## Remaining Gaps

- The save-panel path is compile/build covered, but not UI-automation tested.
