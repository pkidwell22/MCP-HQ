# Wave 11: Keychain Retry and Cleanup UX

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that turns `migration_write_failed` recovery rows into safer user actions.

Context:
- `SecretMigrationWriteFailure` now records failed/pending secrets and partial write references.
- `SecretRecoveryStatus.migrationWriteFailed` exists and is surfaced in dashboard recovery rows.
- The app currently explains the safe recovery path but does not offer explicit retry/cleanup actions for failed rows.

Goal:
- Add a small, tested core/app slice for retry/cleanup affordances around migration-write-failed rows.

Requirements:
- Do not expose plaintext secret values.
- Do not mutate the real Keychain in tests; use fakes.
- Prefer a small core helper/model that can produce safe action labels/messages for migration-write-failed rows.
- Add app UI only if it can be done narrowly and safely.
- Add tests that verify redaction and recovery-state behavior.
- Write a result summary to `docs/pi-team/wave11-keychain-retry-cleanup-result.md` with changed files, validation, and remaining gaps.

Validation:
- Run focused tests for secret management/dashboard/app-adjacent state.
- Run `swift build --product MCPHQApp`.
