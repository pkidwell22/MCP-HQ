# Secret Digest False Positive Result

Implemented in mainline after live Config Manager smoke testing.

## Changed Files

- `Sources/MCPHQCore/SecretManagement.swift`
- `Tests/MCPHQCoreTests/SecretManagementTests.swift`

## What Changed

- Tightened secret migration detection so trusted digest/fingerprint fields such as `NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S` are not treated as literal secrets merely because they look token-like.
- Preserved migration behavior for sensitive field names such as token/API key/auth/password and for sensitive headers.
- Kept path-like values excluded from migration.

## Validation

```text
swift test --filter SecretManagementTests
swift test --filter DashboardStateBuilderTests/testBuildsSecretRowsWithoutExposingLiteralValues
```

Both focused checks passed. The real Keychain integration test remains opt-in and was skipped as expected.

## Remaining Gaps

- Secret detection still uses conservative heuristics; future UX should let users mark a field as non-secret/secret explicitly when MCP-HQ cannot infer intent.
