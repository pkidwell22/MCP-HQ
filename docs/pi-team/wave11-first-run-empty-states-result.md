# Wave 11: First Run and Empty States Result

## Changed files

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Reworked the empty dashboard inventory into a compact first-run checklist with practical next actions: open Config Manager, Refresh, and Run Probes.
  - Added `ConfigManagerEmptyBindingsView` so the Config Manager explains what to do when no MCP bindings have been discovered yet.
  - Kept changes UI-only; no state/model logic changed.

## Validation

- `swift build --product MCPHQApp`

## Remaining gaps

- The empty states are not covered by snapshot/UI tests.
- Further polish could add context-aware suggestions based on which supported agent config files already exist.
