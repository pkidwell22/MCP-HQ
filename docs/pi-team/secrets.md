# Pi Workstream: Keychain Secret Management

You are one worker in a larger MCP-HQ implementation team. Work in this repo copy only.

Model requested by user: GPT 5.5 high reasoning.

## Goal

Add the first safe Keychain secret-management slice.

## Context

Read:

- `docs/FULL_VISION_AUDIT.md`
- `docs/PRD.md` sections 7.4 and 8
- `docs/TECH_STACK.md` Keychain notes
- `Sources/MCPHQCore/Models.swift`
- `Sources/MCPHQCore/ServerDiagnosticChecker.swift`
- `Sources/MCPHQCore/AgentConfigRenderer.swift`

## Implement

- Add a core secret-detection/migration model for env/header values.
- Add a macOS Keychain store abstraction with a testable protocol/fake.
- Add validation for secret presence without revealing values.
- Add focused tests that do not require writing real Keychain items unless guarded behind an explicit integration flag.
- Preserve redaction behavior.

## Constraints

- Do not expose secret values in output or test failures.
- Do not mutate the user's real Keychain in normal tests.
- Run `swift test`.
- Write a summary of changed files and remaining gaps to `docs/pi-team/secrets-result.md`.
