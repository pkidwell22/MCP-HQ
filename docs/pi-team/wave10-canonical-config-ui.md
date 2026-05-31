# Wave 10: Canonical Config Manager UI

You are working in a temporary repo copy for MCP-HQ. Implement a focused slice that moves the native Config Manager toward the canonical authoring model.

## Context

The core now has `AgentCanonicalAuthoringModel` in `Sources/MCPHQCore/AgentBindingDesiredState.swift`. The current app Config Manager still derives most binding rows from scan-shaped data. The goal is not a massive rewrite; the goal is to make the native UI consume or surface the canonical model enough that future richer authoring can build on it.

## Requirements

- Build a small app-facing state adapter from `AgentCanonicalAuthoringModel` if needed.
- In the Config Manager sheet, surface canonical summary/drift information for server bindings.
- Preserve all existing safe apply, preview, rollback, profile, and secret review behavior.
- Do not add destructive behavior or automatic config writes.
- Keep text concise and redacted.
- Add focused tests for the adapter/model/UI snapshot helper if a pure SwiftUI UI test is impractical.

## Validation

Run:

```bash
swift test --filter AgentBindingDesiredStateTests
swift test --filter DashboardStateBuilderTests
swift build --product MCPHQApp
```

Write a result summary to `docs/pi-team/wave10-canonical-config-ui-result.md` with changed files, validation, and remaining gaps.
