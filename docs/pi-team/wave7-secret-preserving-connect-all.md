# Wave 7: Secret-Preserving Connect All

## Goal

Fix Connect All so target-side secret-safe bindings are not downgraded when a template source has a less-safe env placeholder or literal-looking value.

Observed QA issue:

- Native Config Manager Preview Connect All used Codex as the template.
- Hermes already had a `keychain://...` value for `github` `GITHUB_PERSONAL_ACCESS_TOKEN`.
- The draft would replace that target-side Keychain reference with `${GITHUB_PERSONAL_ACCESS_TOKEN}` from Codex.

## Requirements

- When replacing an existing binding with a template binding of the same display name, preserve target-side `keychain://` env/header values for matching keys.
- Prefer target-side secret-safe references over template env placeholders and literal-looking secrets.
- Do not preserve non-secret target values that would keep stale command/url/args semantics.
- Keep source-specific server IDs correct for the target source.
- Cover single-binding previews and bulk Connect All previews.
- Add regression tests showing a target Keychain reference survives a Connect All draft.
- Keep redaction guarantees intact.

## Constraints

- Work in your isolated copy only.
- Do not edit the user's real config files.
- Preserve existing tests and behavior unless the requirement demands a change.
- Write a result summary to `docs/pi-team/wave7-secret-preserving-connect-all-result.md`.

## Suggested Starting Points

- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
- `Sources/MCPHQCore/SecretManagement.swift`
- `Sources/MCPHQCore/SecretRedactor.swift`

## Validation

Run focused tests first:

```bash
swift test --filter AgentConfigAuthoringTests
```

Then run:

```bash
swift test
swift build --product MCPHQApp
```
