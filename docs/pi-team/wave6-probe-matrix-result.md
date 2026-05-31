# Wave 6 Probe Matrix Result

## Files changed

- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
  - Added per-binding Connect All verification state.
  - Added `AgentBulkConnectVerificationMatrixFormatter` for a redacted markdown matrix.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Shows verification matrix details in the Connect All applied sheet text, alongside the structured native result view.
- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Prints the same matrix for `config connect-all apply` output.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Prints the same matrix for local-control Connect All apply responses.
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
  - Added/updated coverage for per-binding config status, probe status, matrix formatting, and secret redaction.
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
  - Updated CLI expectations for the matrix and honest wording.

## Behavior

After Connect All apply, verification now includes a per-target/per-binding matrix with columns:

- target source;
- binding;
- config verification (`configured`, `missing binding`, `config missing`, `parse failed`, `unsupported`);
- live probe (`not run`, `probeable`, `warning`, `failed`, `skipped`, `no probe result`, `not available`).

The wording avoids claiming that an external agent loaded or reloaded the changed config. Successful config parse/binding checks are described as `configured`; successful live probes are described as `probeable`.

Secrets are redacted in matrix cells, binding names, paths, probe messages, app text, CLI output, and local-control output.

## Tests run

- `swift test --filter AgentConfigAuthoringTests`
  - Passed in the agent copy.
- `swift test --filter MCPHQCommandTests/testConfigConnectAllApply`
  - Passed in the agent copy.
- `swift test`
  - Passed in the agent copy: 247 tests, 1 skipped, 0 failures.
- Mainline focused verification after integration:
  - `swift test --filter AgentConfigAuthoringTests --filter MCPHQCommandTests/testConfigConnectAllApply --filter NativeAppPreferencesTests`
  - Passed: 21 tests, 0 failures.

## Caveats

- The macOS app still starts a live probe scan after Connect All apply and the immediate sheet matrix initially shows `not run` unless probe evidence is available to the verifier. Probe findings continue to appear in the dashboard/Doctor views after the scan completes.
