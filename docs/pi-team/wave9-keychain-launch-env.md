# Wave 9: Keychain Launch Environment

You are working in an isolated copy of MCP-HQ. Implement or critique the next slice for hub-owned runtime secret injection.

## Goal

Hub-owned runtime launches should resolve safe config references before spawning a process:

- `keychain://service/account` env values should be read from the configured secret store and injected only into the child process environment.
- `${VAR}` and `$VAR` env references should resolve from the parent process environment, preserving existing behavior for literal values.
- Missing or inaccessible secrets/env references should fail launch with a redacted, actionable error, not start a broken runtime.
- Raw secret values must never appear in `RuntimeInstance`, errors, logs, docs, tests, or UI summaries.

## Constraints

- Keep destructive lifecycle actions helper-owned.
- Do not mutate the real Keychain in tests; use `InMemorySecretStore`.
- Prefer focused core tests in `RuntimeLifecycleTests`.
- Keep API changes small and compatible with existing call sites.

## Deliverable

Write a result summary to `docs/pi-team/wave9-keychain-launch-env-result.md` with changed files, validation, and remaining gaps.
