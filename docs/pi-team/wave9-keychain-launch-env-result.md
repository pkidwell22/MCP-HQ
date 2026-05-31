# Wave 9 Keychain Launch Environment Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/RuntimeSupervisor.swift`
  - Added `RuntimeLaunchEnvironmentResolver`.
  - Hub-owned runtime starts now resolve `keychain://...` env values through the configured `SecretStore` before spawning.
  - Exact `$VAR` / `${VAR}` env values and embedded `${VAR}` references now resolve from the parent/process environment before spawning.
  - Missing Keychain secrets, unavailable secret stores, Keychain read failures, and missing env references fail before launch with redacted `RuntimeSupervisorError` cases.
  - Resolved secret values are passed only to the child process environment; runtime instance records keep their existing redacted command-line behavior.
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`
  - Added coverage for successful Keychain/env resolution.
  - Added coverage that missing Keychain/env references do not launch a process and do not expose raw secrets in errors.
- `docs/FULL_VISION_AUDIT.md`
  - Updated the Keychain/lifecycle status and removed the undecided hub-owned injection gap.

## Validation

- `swift test --filter RuntimeLifecycleTests`
