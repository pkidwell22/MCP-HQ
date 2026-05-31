# Doctor actions result

## Changed files

- `Sources/MCPHQCore/DoctorReport.swift`
  - Added `DoctorFindingFilter` for severity, source path, and server ID.
  - Added filtered `DoctorReport` and formatter entry points.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added opt-in Doctor filters for the wide Doctor panel.
  - Updated Doctor copy/export actions to use the currently filtered report when invoked from the Doctor panel.
  - Added safe per-finding actions to open the source config and preview generated config where a source path is available.
  - Redacted displayed/copied config preview text for environment/header values associated with sensitive names, while keeping the underlying apply path based on scanned server models rather than displayed text.
- `Tests/MCPHQCoreTests/DoctorReportTests.swift`
  - Added focused coverage for `DoctorFindingFilter` combinations across severity, source, and server.

## Validation

- Ran `swift test --filter DoctorReportTests`.
- Ran `swift build --product MCPHQApp`.
- Both passed.

## Remaining gaps

- Doctor filters are local UI state in each Doctor panel; they are not persisted across app launches.
- The CLI `mcphq doctor` still does not expose severity/server filtering flags, although the core formatter supports filters.
- Config draft previews outside the direct Doctor preview path may still need a broader shared redacted-preview model for complete consistency.
