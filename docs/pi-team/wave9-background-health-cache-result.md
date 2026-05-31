# Wave 9 Background Health Cache Result

## Changed files

- `Sources/MCPHQCore/HealthCache.swift`
  - Added redacted `HealthCacheSnapshot`, `HealthSummaryCounts`, `HealthCacheScanStatus`, and `JSONHealthCacheStore`.
  - Stores scan status, timestamp, requested source scope, probe flag, summary counts, and redacted failure messages.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Added optional health-cache metadata to local-control responses.
  - Status responses can report scan timestamp, scan status, and whether counts came from cache.
  - Scan/status paths update the cache with the full requested source scope, including missing configs.
  - Default non-probe status requests can reuse a matching cached snapshot instead of forcing a fresh scan.
- `Sources/MCPHQCore/LocalControlEndpoint.swift`
  - Wires an Application Support health-cache store into the default helper router.
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`
  - Covers scan cache updates and default status reuse for a source set that includes a missing config path.
- `Tests/MCPHQCoreTests/ScanResultStoreTests.swift`
  - Covers health-cache round-trip and failure-message redaction.

## Validation

- `swift test --filter LocalControlAPITests --filter ScanResultStoreTests --filter AgentBindingDesiredStateTests`

## Remaining gaps

- No long-running background scheduler yet; cache refresh is still driven by scan/status routes.
- The app does not yet surface cache age/state prominently outside helper/status metadata.
