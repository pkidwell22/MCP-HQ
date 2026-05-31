# Wave 8: Visual Diff UI

## Goal

Improve the native config preview/apply experience beyond a single monospaced text blob by adding a structured diff presentation while preserving the existing safe preview/apply semantics.

## Requirements

- Keep the current redacted compact diff text available.
- Add a structured visual diff view or section that separates added, removed, and context lines.
- Preserve redaction guarantees for generated config and diff output.
- Do not change apply behavior, backup behavior, stale guards, or rollback behavior.
- Add tests at the formatter/model layer if a new diff parser/model is introduced.
- Write a result summary to `docs/pi-team/wave8-visual-diff-ui-result.md`.

## Suggested Starting Points

- `Sources/MCPHQCore/AgentConfigRenderer.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Tests/MCPHQCoreTests/AgentConfigRendererTests.swift`

## Validation

```bash
swift test --filter AgentConfigRendererTests
swift build --product MCPHQApp
```
