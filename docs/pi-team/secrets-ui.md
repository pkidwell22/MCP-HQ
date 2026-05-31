# MCP-HQ Pi Workstream: Secrets UI

You are working in an isolated copy of MCP-HQ. Implement the next practical secret-management UI/core slice.

Context:
- Core already has `SecretDetector`, `SecretStore`, `MacOSKeychainSecretStore`, and presence validation.
- The app has inventory, Doctor, source rows, and server inspector.
- Keep values redacted; never display actual secrets.

Goal:
- Surface detected literal secrets and/or Keychain reference presence in app state/UI.
- Add focused core models if useful, but avoid broad rewrites.
- If migration is too large, implement review/status first with a clean path to migration.

Constraints:
- Do not expose plaintext secrets.
- Real Keychain writes should require explicit action; tests should use `InMemorySecretStore`.
- Run `swift test`.

Deliverable:
- Code changes in your repo copy.
- A summary in `docs/pi-team/secrets-ui-result.md` with changed files, validation, and remaining gaps.
