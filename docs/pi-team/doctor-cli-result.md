# Doctor CLI Result

Merged from the `doctor-cli` Pi worker with small test adaptations.

## Changed Files

- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## What Changed

- Added Doctor CLI filters:
  - `--severity error|warning|info`
  - `--source-path path`
  - `--server id-or-name`
- Filters apply to both text and JSON output through `DoctorFindingFilter`.
- `--server` accepts an exact server ID or resolves a visible server name to the matching finding's server ID.
- Updated usage/help and docs.

## Validation

Worker validation:

```text
swift test
```

Result in the isolated copy: full suite passed with the expected Keychain integration skip.

Mainline validation is still required after merge with concurrent history changes.

## Remaining Gaps

- Native app Doctor filter selections are not persisted yet.
- CLI filtering is finding-oriented; broader saved report/export presets remain future work.
