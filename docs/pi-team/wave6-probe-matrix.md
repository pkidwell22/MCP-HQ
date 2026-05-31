# Wave 6: Connect All Probe Matrix

You are working in an isolated copy of MCP-HQ. Implement a focused, tested slice that improves post-Connect-All verification.

Goal:
- After Connect All apply, the user should see a clear matrix of selected target sources and bindings showing:
  - config parsed/binding verification status;
  - live probe status when available;
  - honest language: "configured" or "probeable", never "agent loaded" unless directly proven.

Constraints:
- Keep the scope tight and compatible with existing app/core patterns.
- Preserve existing safe-apply and rollback behavior.
- Do not expose secrets in UI, logs, tests, or JSON.
- Prefer adding state/formatting helpers in core when it reduces SwiftUI bulk.

Suggested inspection points:
- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
- `Tests/MCPHQCoreTests/DashboardStateBuilderTests.swift`

Deliverables:
- Code and tests in your copy.
- Run at least focused tests; run full `swift test` if practical.
- Write `docs/pi-team/wave6-probe-matrix-result.md` summarizing files changed, behavior, tests, and any caveats.
