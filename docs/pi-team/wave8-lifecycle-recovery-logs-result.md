# Wave 8 Lifecycle Recovery and Logs Result

Integrated in main worktree.

## Changed

- `Sources/MCPHQCore/RuntimeLifecycle.swift`
  - Added a shared runtime reconciler that merges persisted hub-owned runtime metadata into observed process rows by PID.
  - Known hub-owned rows keep their `hub:*` runtime ID and log path instead of becoming duplicate process rows.
  - Stale hub-owned runtime records now explain recovery and keep stop/restart disabled when no matching PID is visible.
  - Added helper control-plane availability to panel state/formatting.
- `Sources/MCPHQApp/MCPHQApp.swift`
  - Lifecycle & Logs refreshes helper endpoint availability when opened.
  - The sheet displays helper availability and disables lifecycle controls when the helper is unavailable.
- `Sources/MCPHQCore/LocalControlAPI.swift` and `Sources/MCPHQCore/MCPHQCommand.swift`
  - Runtime explain paths use the shared reconciler.
- `Tests/MCPHQCoreTests/RuntimeLifecycleTests.swift`
  - Added coverage for known log-path reconciliation, stale runtime recovery, and helper-unavailable control disabling.

## Validation

- `swift test --filter RuntimeLifecycleTests --filter LocalControlAPITests --filter MCPHQCommandTests`
