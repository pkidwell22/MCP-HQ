# Wave 6 Target Profiles Result

## Summary

Implemented reusable Connect All target profiles backed by the existing SQLite control-plane store.

## Files Changed

- `Sources/MCPHQCore/SQLiteScanHistoryStore.swift`
  - Added `SQLiteConnectAllTargetProfileRecord`.
  - Added `connect_all_target_profiles` schema table and migration marker `5`.
  - Added APIs to upsert, load, and list named Connect All target profiles.
  - Deduplicates persisted target sources while preserving order.
- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Added `--profile` and `--save-profile` to `config connect-all preview/apply`.
  - Added `registry target-profiles` text/JSON listing.
  - Updated CLI usage/examples.
- `Tests/MCPHQCoreTests/SQLiteScanHistoryStoreTests.swift`
  - Added persistence/query coverage for target profiles.
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
  - Added CLI coverage for saving a target profile, reusing it, and listing it via registry.

## Behavior

- `mcphq config connect-all preview/apply ... --save-profile NAME` persists the selected target sources after a successful operation.
- `mcphq config connect-all preview/apply ... --profile NAME` loads target sources from the saved profile.
- Explicit `--target-source` values may be combined with `--profile`; duplicates are removed by source id.
- `mcphq registry target-profiles [--json]` surfaces saved profiles.
- Existing rollback transaction and desired-state tables were not changed.

## Tests

- Agent copy focused run: `swift test --filter 'SQLiteScanHistoryStoreTests|MCPHQCommandTests'`
  - 61 tests passed.
- Agent copy full run: `swift test`
  - 248 tests passed, 1 skipped keychain opt-in test.
- Mainline focused verification after integration:
  - `swift test --filter SQLiteScanHistoryStoreTests --filter MCPHQCommandTests`
  - 61 tests passed.

## Caveats

- Native UI was not changed for this slice; profile support is exposed through CLI/core registry APIs.
