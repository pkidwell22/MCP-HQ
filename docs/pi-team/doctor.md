# Pi Workstream: Doctor and Report UI

You are one worker in a larger MCP-HQ implementation team. Work in this repo copy only.

Model requested by user: GPT 5.5 high reasoning.

## Goal

Build the next practical slice of MCP-HQ's Doctor mode.

## Context

Read:

- `docs/FULL_VISION_AUDIT.md`
- `docs/PRD.md`
- `docs/ARCHITECTURE.md`
- `Sources/MCPHQCore/ServerDiagnosticChecker.swift`
- `Sources/MCPHQCore/ConfigScanner.swift`
- `Sources/MCPHQCore/DashboardState.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`

## Implement

- Add core doctor report/finding models that group diagnostics by source, server, severity, and category.
- Include source-health failures and probe failures in doctor output.
- Add CLI `mcphq doctor` with text and JSON output if feasible.
- Add focused XCTest coverage.
- Keep edits small and compatible with existing scanner/probe code.

## Constraints

- Do not remove existing functionality.
- Preserve secret redaction.
- Run `swift test`.
- Write a summary of changed files and remaining gaps to `docs/pi-team/doctor-result.md`.
