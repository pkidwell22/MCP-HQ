# Wave 11: Canonical Drift Resolution

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that makes canonical payload drift actionable rather than just visible.

Context:
- `AgentCanonicalAuthoringModel` detects missing, disabled-but-present, observed-only, and payload-mismatch drift.
- `AgentCanonicalConfigManagerSnapshot` surfaces redacted drift details in the native Config Manager.
- Binding draft/apply flows already exist for enabling/disabling sources.

Goal:
- Add a narrow core/app helper for suggested drift actions that future UI can execute or preview.

Requirements:
- Suggested actions should be secret-safe and deterministic.
- Cover at least payload mismatch, missing desired binding, and present-but-disabled cases.
- Prefer a core model/helper first; app UI may show the suggested action text if low risk.
- Do not perform broad Config Manager rewrites.
- Add focused tests.
- Write a result summary to `docs/pi-team/wave11-canonical-drift-resolution-result.md` with changed files, validation, and remaining gaps.

Validation:
- Run `swift test --filter AgentBindingDesiredStateTests --filter AgentConfigAuthoringTests`.
- Run `swift build --product MCPHQApp`.
