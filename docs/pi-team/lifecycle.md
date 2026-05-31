# Pi Workstream: Lifecycle, Ownership, and Logs

You are one worker in a larger MCP-HQ implementation team. Work in this repo copy only.

Model requested by user: GPT 5.5 high reasoning.

## Goal

Build the next safe slice toward lifecycle/log visibility without prematurely killing or managing agent-owned processes.

## Context

Read:

- `docs/FULL_VISION_AUDIT.md`
- `docs/ARCHITECTURE.md` ownership model
- `docs/INFRASTRUCTURE_FLOW.md` lifecycle flow
- `Sources/MCPHQCore/MCPProcessScanner.swift`
- `Sources/MCPHQCore/ServerProcessMatcher.swift`
- `Sources/MCPHQCore/DashboardState.swift`

## Implement

- Add runtime ownership models: `agentOwned`, `hubOwned`, `unknown`.
- Classify current process matches as observed/agent-owned where possible.
- Add CPU/memory fields if practical from process scanner output.
- Add log/status model stubs for future hub-owned supervision.
- Add tests for ownership classification and process snapshot rendering.

## Constraints

- Do not implement destructive stop/restart yet unless hub-owned identity is unambiguous and fully tested.
- Preserve current process scanner behavior.
- Run `swift test`.
- Write a summary of changed files and remaining gaps to `docs/pi-team/lifecycle-result.md`.
