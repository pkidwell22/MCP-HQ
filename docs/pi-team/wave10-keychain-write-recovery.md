# Wave 10: Keychain Write Recovery

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that improves Keychain migration write-failure recovery.

## Context

MCP-HQ already detects literal secrets, plans/batches Keychain migrations, validates presence without exposing values, and surfaces missing/inaccessible references. Remaining product polish is around write failures during guarded migrations: users should get safe, actionable recovery guidance, and partial migrations should not leave configs or recorded bindings in a confusing state.

## Requirements

- Improve core recovery reporting for Keychain write failures during migration.
- Ensure partial writes are described without exposing secret values.
- If possible, add app-facing rows/messages that distinguish missing secret, inaccessible secret, and migration write failure.
- Preserve existing rollback behavior for config snapshots and newly written references.
- Add focused tests with a failing fake `SecretStore`.

## Validation

Run:

```bash
swift test --filter SecretManagementTests
swift test --filter AgentConfigAuthoringTests
swift build --product MCPHQApp
```

Write a result summary to `docs/pi-team/wave10-keychain-write-recovery-result.md` with changed files, validation, and remaining gaps.
