# Control Client Result

Merged from the `control-client` Pi worker with current mainline adaptations.

## Changed Files

- `Sources/MCPHQCore/LocalControlClientState.swift`
- `Sources/MCPHQCore/LocalControlLaunchAgent.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`
- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## What Changed

- Added `LocalControlClientStateHelper`, a small shared dispatch helper for direct-core vs endpoint-backed control requests.
- Added redacted endpoint client state models that expose helper metadata without exposing endpoint tokens.
- Centralized `control status` local-control dispatch through the helper.
- Added `mcphq runtime explain --endpoint-file ...` so a read-only runtime explanation can be served by a running control helper.

## Validation

Worker validation:

```text
swift test
```

Result in the isolated copy: full suite passed with the expected Keychain integration skip.

Mainline validation is still required after merge with concurrent history and Doctor CLI changes.

## Remaining Gaps

- Most app paths still call core directly.
- Most CLI routes still use direct core unless an endpoint-specific path has been wired.
- Production token generation/storage policy is still undecided for the loopback HTTP helper.
