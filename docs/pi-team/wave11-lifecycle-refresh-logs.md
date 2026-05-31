# Wave 11: Lifecycle Refresh and Log Lookup

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that improves native lifecycle/log usefulness without broad supervision rewrites.

Context:
- Runtime ownership/control explanations exist.
- Helper-backed start/stop/restart controls exist for hub-owned runtimes.
- Bounded log viewing exists for known supervised log paths.

Goal:
- Add a narrow improvement for lifecycle status freshness and/or automatic log lookup.

Requirements:
- Prefer read-only logic and safe UI state over process mutation.
- If adding refresh cadence, make it testable and bounded; do not create an always-running daemon.
- If adding log lookup, only read safe, bounded, redacted known paths.
- Add focused tests.
- Write a result summary to `docs/pi-team/wave11-lifecycle-refresh-logs-result.md` with changed files, validation, and remaining gaps.

Validation:
- Run `swift test --filter RuntimeLifecycleTests --filter LocalControlAPITests`.
- Run `swift build --product MCPHQApp`.
