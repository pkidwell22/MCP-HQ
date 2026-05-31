# MCP-HQ Pi Workstream: Config UI

You are working in an isolated copy of MCP-HQ. Implement the next practical config-management UI slice.

Context:
- Core already has `AgentConfigSafeApplier`, `AgentConfigRenderer`, and CLI `mcphq config preview/apply`.
- The SwiftUI app is in `Sources/MCPHQApp/MCPHQApp.swift`.
- Keep changes focused, tested, and secret-safe.

Goal:
- Add a native app affordance that lets a user preview config rendering/apply readiness from scanned sources.
- Prefer a read-only/safe first slice over risky writes if needed.
- Show source/target, generated preview/diff text, reparse count, backup/dry-run messaging, and errors.

Constraints:
- Do not expose plaintext secrets.
- Do not write real user config files from the UI without an explicit dry-run/safe path.
- Follow existing SwiftUI style in this repo.
- Run `swift test`.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/config-ui-result.md` with changed files, validation, and remaining gaps.
