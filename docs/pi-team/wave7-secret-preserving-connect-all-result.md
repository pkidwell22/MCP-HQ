# Wave 7 Secret-Preserving Connect All Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/AgentConfigAuthoring.swift`
  - Connect All now retargets template servers while preserving existing target-side Keychain env/header references for matching keys.
  - Header preservation matches keys case-insensitively.
  - Target server IDs remain source-specific.
- `Sources/MCPHQCore/AgentConfigRenderer.swift`
  - `keychain://...` values are treated as safe references during rendering instead of sensitive literals to convert into `${ENV_VAR}` placeholders.
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
  - Added a regression proving Connect All preserves a target `keychain://` GitHub token reference while still updating command/args from the template.

## Validation

- `swift test --filter AgentConfigAuthoringTests --filter AgentConfigRendererTests --filter SecretManagementTests`
- Real-machine preview check:
  - `mcphq config connect-all preview --template-source codex:/Users/patkidwell/.codex/config.toml --target-source hermes:/Users/patkidwell/.hermes/config.yaml`
  - The generated Hermes GitHub binding kept the existing `keychain://com.mcphq.secrets/...GITHUB_PERSONAL_ACCESS_TOKEN` reference.

## Remaining Caveats

- This preserves existing target Keychain references; it does not yet migrate an env placeholder into Keychain by itself.
- It does not prove the external agent has reloaded the changed config.
