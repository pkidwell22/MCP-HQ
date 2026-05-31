# Pi Workstream: Config Manager CLI and Preview

You are one worker in a larger MCP-HQ implementation team. Work in this repo copy only.

Model requested by user: GPT 5.5 high reasoning.

## Goal

Expose the existing config generation/safe-apply foundation through a usable CLI workflow.

## Context

Read:

- `docs/FULL_VISION_AUDIT.md`
- `Sources/MCPHQCore/AgentConfigRenderer.swift`
- `Sources/MCPHQCore/AgentConfigParser.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`

## Implement

- Add CLI subcommands such as:
  - `mcphq config preview --source agent:/path --server-source agent:/path`
  - or another small, testable shape that previews generated config without writing.
- Add a dry-run/apply path only if it can be tested safely with temporary files.
- Return backup path after apply.
- Ensure generated output reparses and never prints literal secrets.
- Add focused XCTest coverage.

## Constraints

- Never write real user config paths in tests.
- Preserve existing `scan` behavior.
- Run `swift test`.
- Write a summary of changed files and remaining gaps to `docs/pi-team/config-manager-result.md`.
