# Pi Workstream: Local Persistence

You are one worker in a larger MCP-HQ implementation team. Work in this repo copy only.

Model requested by user: GPT 5.5 high reasoning.

## Goal

Add the first local persistence slice for scan state.

## Context

Read:

- `docs/FULL_VISION_AUDIT.md`
- `docs/ARCHITECTURE.md` data model sections
- `docs/TECH_STACK.md` SQLite notes
- `Sources/MCPHQCore/ConfigScanner.swift`
- `Sources/MCPHQCore/ScanCoordinator.swift`
- `Sources/MCPHQCore/DashboardState.swift`

## Implement

- Add a simple local registry or scan-result store using standard libraries where possible.
- If SQLite is practical without adding a package, use the system SQLite C library; otherwise create a file-backed JSON store as a stepping stone and document the SQLite follow-up.
- Persist and reload the latest `ScanResult`.
- Add tests around write/read, schema/versioning or file versioning, and redaction expectations.

## Constraints

- Do not require external services.
- Do not persist raw secret values where safe redacted alternatives are intended.
- Run `swift test`.
- Write a summary of changed files and remaining gaps to `docs/pi-team/persistence-result.md`.
