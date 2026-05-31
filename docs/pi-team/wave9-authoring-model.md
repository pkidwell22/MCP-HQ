# Wave 9: Canonical Authoring Model

You are working in an isolated copy of MCP-HQ. Add the next small slice toward a full canonical config authoring model.

## Goal

The current Config Manager is still largely scan-row driven. Add a focused internal model/helper that can represent desired server bindings independent of the latest scan.

Suggested scope:

- Model canonical authoring server identity, source binding intent, and drift status.
- Build from existing scan result plus persisted desired state rows.
- Expose summary data that future Config Manager UI can use.

## Constraints

- Do not rewrite the Config Manager UI.
- Keep existing safe apply and rollback behavior intact.
- Prefer core model tests.

## Deliverable

Write a result summary to `docs/pi-team/wave9-authoring-model-result.md` with changed files, validation, and remaining gaps.
