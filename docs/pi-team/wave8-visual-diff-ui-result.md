# Wave 8 Visual Diff UI Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/AgentConfigRenderer.swift`
  - Added `ConfigDiffFormatter`, `ConfigVisualDiffLine`, and structured added/removed/context diff output.
  - Config previews now carry both compact redacted diff text and structured redacted visual diff lines.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Config preview/apply sheets show a structured redacted diff with counts and line numbers, followed by the compact preview.
- `Tests/MCPHQCoreTests/AgentConfigRendererTests.swift`
  - Added visual diff and redaction coverage.

## Validation

- `swift test --filter AgentConfigRendererTests --filter LocalControlAPITests --filter PackageAppScriptTests`
