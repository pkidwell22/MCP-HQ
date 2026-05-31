# Wave 10 Keychain Write Recovery Result

## Changed files

- `Sources/MCPHQCore/SecretManagement.swift`
  - Added `SecretMigrationWriteFailure`, including failed/pending secrets, partial references written before failure, redacted underlying errors, and safe recovery guidance.
  - Batch migration now carries prior successful references into a thrown write failure so callers can roll them back.
  - Recovery reporting now preserves `migration_write_failed` rows and counts them separately from missing/inaccessible references.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Server-level and Config Manager secret migrations record failed/pending bindings when Keychain writes fail.
  - Config Manager migration failure handling restores config snapshots and deletes partial Keychain writes before showing recovery text.
- `Sources/MCPHQCore/DashboardState.swift`
  - Added dashboard labels and guidance for migration-write-failed recovery rows.
- `Sources/MCPHQCore/DoctorReport.swift`
  - Doctor explanations now include why/fix text for Keychain migration write failures.
- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Registry secret validation output includes migration-write-failed counts.
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
  - Added partial-write redaction, batch rollback-reference, and recovery reporter coverage.

## Validation

- `swift test --filter SecretManagementTests`
- `swift build --product MCPHQApp`

## Remaining gaps

- Recovery rows explain the safe path, but the app still needs explicit retry/cleanup actions for migration-write-failed rows.
