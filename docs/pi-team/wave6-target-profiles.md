# Wave 6: Reusable Connect All Target Profiles

You are working in an isolated copy of MCP-HQ. Implement a focused, tested slice for reusable bulk-connect target profiles.

Goal:
- Add a small persisted model for named Connect All target profiles so repeated setups can remember a list of target sources.
- Surface profile data through CLI/registry or core API enough to prove persistence works.
- Keep native UI changes minimal unless they are straightforward and tested.

Constraints:
- Use existing SQLite/control-plane patterns.
- Do not break existing rollback transactions or desired-state tables.
- Avoid broad schema churn; use a new migration only if needed.
- Keep generated output secret-safe.

Suggested inspection points:
- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
- `Sources/MCPHQCore/AgentRegistry.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`

Deliverables:
- Code and tests in your copy.
- Run focused tests; run full `swift test` if practical.
- Write `docs/pi-team/wave6-target-profiles-result.md` summarizing files changed, behavior, tests, and any caveats.
