# MCP-HQ Pi Workstream: Lifecycle And Logs

You are working in an isolated copy of MCP-HQ. Implement the next lifecycle/logs slice.

Context:
- Core has runtime models and process ownership/resource visibility.
- Full vision needs hub-owned start/stop/restart and read-only explanations for externally owned processes.

Goal:
- Add safe lifecycle/log abstractions and UI/CLI messaging.
- Prefer read-only explanations and log-tail models before destructive control.
- If adding commands, make externally owned processes clearly non-controllable.

Constraints:
- No destructive process kills unless explicitly hub-owned in a test-controlled path.
- Redact command lines/log lines.
- Run `swift test`.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/lifecycle-logs-result.md` with changed files, validation, and remaining gaps.
