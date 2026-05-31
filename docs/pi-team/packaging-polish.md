# MCP-HQ Pi Workstream: Packaging Polish

You are working in an isolated copy of MCP-HQ. Implement the next packaging/native polish slice.

Context:
- `scripts/package_app.sh` builds `.build/MCP-HQ.app`.
- Full vision needs better bundle metadata, app state persistence, settings, login item later, signing/notarization hooks.

Goal:
- Improve the package script and native app polish in a verifiable, local-development-safe way.
- Add metadata/version handling, clean rebuild behavior, optional signing hook, or window/sidebar persistence if feasible.

Constraints:
- Do not require paid signing/notarization credentials.
- Keep local app launch working.
- Run `swift test` and package script if relevant.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/packaging-polish-result.md` with changed files, validation, and remaining gaps.
