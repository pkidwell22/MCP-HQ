# MCP-HQ Pi Workstream: SQLite Persistence

You are working in an isolated copy of MCP-HQ. Implement the next persistence slice toward the full vision.

Context:
- Current app has a JSON last-scan cache via `JSONScanResultStore`.
- Full vision calls for queryable local history/registry storage.

Goal:
- Add a SQLite-backed registry/history foundation if feasible using available system SQLite.
- At minimum, define migration/schema code and persist scan runs, sources, servers, findings, and runtime/process snapshots.
- Keep JSON cache compatibility if changing app startup is too risky.

Constraints:
- Keep schema small and testable.
- Do not add heavyweight dependencies without checking Package.swift conventions.
- Run `swift test`.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/sqlite-persistence-result.md` with changed files, validation, and remaining gaps.
