# Wave 10: Authoring Payload Drift

You are working in a temporary repo copy for MCP-HQ. Implement a focused core slice that makes the canonical authoring model detect payload drift, not just presence drift.

## Context

`AgentCanonicalAuthoringModel` currently reports coarse statuses:

- `in_sync`
- `missing_from_scan`
- `present_but_disabled`
- `observed_only`

When a desired binding and scanned server both exist for the same source, the model should be able to tell whether command, args, transport, URL, env, or headers differ in a secret-safe way.

## Requirements

- Extend the canonical model with a payload drift status or details that distinguish payload mismatch from plain in-sync.
- Compare only redacted/secret-safe representations when exposing messages or details.
- Do not expose literal secrets in summaries, diffs, or tests.
- Keep existing API source-compatible where possible, or update tests/callers deliberately.
- Add tests for command/args/env/header/URL drift and a no-drift case.

## Validation

Run:

```bash
swift test --filter AgentBindingDesiredStateTests
swift test --filter SecretRedactorTests
```

Write a result summary to `docs/pi-team/wave10-authoring-payload-drift-result.md` with changed files, validation, and remaining gaps.
