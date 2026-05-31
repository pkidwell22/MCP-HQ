# MCP-HQ Pi Workstream: Local Control API

You are working in an isolated copy of MCP-HQ. Implement the next local control API slice.

Context:
- App and CLI currently call core directly.
- Full vision calls for a helper/control API with status, scan, servers, doctor, and config preview/apply endpoints.

Goal:
- Add a local API model/router foundation that can be shared by CLI/app.
- It can be in-process and test-only for now; do not overbuild a daemon.
- Include route/request/response types for status, scan, servers, doctor, and config preview/apply.

Constraints:
- No insecure network listener unless explicitly scoped and tested.
- Keep responses redacted.
- Run `swift test`.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/local-api-result.md` with changed files, validation, and remaining gaps.
