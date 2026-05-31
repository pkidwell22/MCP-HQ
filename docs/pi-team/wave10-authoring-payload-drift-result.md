# Wave 10 Authoring Payload Drift Result

## Changed files

- `Sources/MCPHQCore/AgentBindingDesiredState.swift`
  - Added `payload_mismatch` drift status.
  - Added redacted payload drift details to canonical source bindings.
  - Compares transport, command, args, URL, env, and headers when a desired-enabled binding is present in the latest scan.
- `Tests/MCPHQCoreTests/AgentBindingDesiredStateTests.swift`
  - Added matching and mismatching payload drift coverage.
  - Verifies secret-looking values are not exposed in drift details.

## Validation

- `swift test --filter AgentBindingDesiredStateTests --filter SecretRedactorTests`

## Remaining gaps

- The Config Manager UI still needs to surface payload drift details in a polished way.
