# Pi Workstream Result: Doctor Primary Workflow Polish

Merged on 2026-05-31.

## Changed Files

- `Sources/MCPHQCore/DoctorReport.swift`
  - Added richer grouping keys for doctor findings: source path + server + severity + category.
  - Extended `DoctorFindingFilter` with `category` and matched filtering.
  - Added keychain recovery findings to doctor report synthesis with clear why/fix messaging.
  - Updated text formatter to include grouped `source`, `server`, `category`, and `severity` lines for each section.
- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Added `--category` CLI filtering support.
  - Extended `mcphq doctor` to merge persisted keychain recovery states with current keychain validation findings.
  - Ensured keychain recovery report is injected into doctor report rendering.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Enhanced doctor payload from control endpoint to include keychain recovery findings for app/clients.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added copy action for individual doctor findings with redacted output text.
  - Added category filtering UI + persistence and updated filter chips to show category and server metadata.
  - Switched doctor rendering pipeline to include keychain recovery states both at startup and after probes/rescans.
- `Tests/MCPHQCoreTests/DoctorReportTests.swift`
  - Added coverage for grouped output (source/server/severity/category).
  - Added category filter coverage in existing finding-filter tests.
  - Added keychain recovery finding test asserting no plaintext secret leakage in text and JSON formatter output.

## Validation

- `swift test --filter DoctorReportTests`
- `swift test --filter MCPHQCommandTests`
- `swift test`
- Result: `291` tests executed, `0` failures, `1` skipped.

## Remaining gaps

- No targeted `MCPHQApp` UI test coverage for doctor category filtering and copy action.
- The app’s doctor JSON export path still uses the same report model, but richer interactive action surfaces (share sheet/named exports) are not yet addressed.
- No dedicated CLI assertion yet for `--category` output compatibility in command tests.
