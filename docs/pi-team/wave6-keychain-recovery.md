# Wave 6: Keychain Validation and Recovery

You are working in an isolated copy of MCP-HQ. Implement a focused, tested slice around Keychain validation and recovery.

Goal:
- Use existing secret-binding persistence and Keychain presence validation to produce clearer recovery state for missing or inaccessible Keychain references.
- Prefer a core state/reporting helper plus CLI/app-facing formatting hooks over a large UI-only patch.
- The user should learn what is missing and what action is safe, without raw secret values.

Constraints:
- Never print or persist plaintext secrets.
- Preserve existing Keychain integration test opt-in behavior.
- Keep failure messages actionable and redacted.

Suggested inspection points:
- `Sources/MCPHQCore/SecretManagement.swift`
- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
- `Sources/MCPHQCore/ServerDiagnosticChecker.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`
- `Tests/MCPHQCoreTests/ServerDiagnosticCheckerTests.swift`

Deliverables:
- Code and tests in your copy.
- Run focused tests; run full `swift test` if practical.
- Write `docs/pi-team/wave6-keychain-recovery-result.md` summarizing files changed, behavior, tests, and any caveats.
