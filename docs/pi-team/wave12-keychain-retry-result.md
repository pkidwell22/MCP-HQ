# Wave 12 Keychain Retry and Cleanup Result

## Changed files

- `Sources/MCPHQCore/SecretManagement.swift`
  - Added `SecretMigrationWriteFailureRecoveryPlan`, `SecretMigrationWriteFailureRecoveryResult`, and `SecretMigrationWriteFailureRecoveryService`.
  - Recovery plan filters migration-write-failed states, supports optional secret-ID targeting, and generates a redacted preview message.
  - Recovery result now reports attempted/deleted/already-missing counts.
  - Cleanup execution now deletes references idempotently and only treats keychain-not-found delete errors as safe, missing-state actions.
- `Sources/MCPHQCore/DashboardState.swift`
  - Added `supportsMigrationCleanup` flag to `DashboardKeychainRecoveryRow`.
  - Migration-write-failed rows now carry cleanup support to distinguish safe executable retry behavior.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Added `lastSecretRecoveryReport` cache so retry actions can target the latest keychain recovery states.
  - Added `cleanupMigrationWriteFailedKeychainReferences(for:)` that builds a targeted cleanup plan, executes idempotent reference deletion, and reruns validation.
  - Wired migration-write-failed row secondary actions in `KeychainRecoveryPanel` to this cleanup/retry path.
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
  - Added tests for recovery planning targeting only migration rows.
  - Added idempotent cleanup tests covering delete then already-missing rerun.
  - Added redaction checks for recovery preview/result text.
- `Tests/MCPHQCoreTests/DashboardStateBuilderTests.swift`
  - Added coverage for `supportsMigrationCleanup` on migration and non-migration recovery rows.

## Validation

- `swift test --filter SecretManagementTests`
- `swift test --filter DashboardStateBuilderTests`

## Remaining gaps

- Consider adding explicit pre-execution confirmation UI (e.g., count summary and checkbox) before cleanup.
- Add integration coverage for the app action path under `KeychainRecoveryPanel` and real store fallback conditions.
