# Wave 10 Health Cache UI and Cadence Result

## Changed files

- `Sources/MCPHQCore/MCPHQCommand.swift`
  - Text `mcphq control status` now prints health-cache metadata when available: scanned timestamp, cache age, cache source, freshness/staleness, refresh recommendation, and scan status.
  - JSON `control status` now encodes status dates as ISO-8601.
- `Sources/MCPHQCore/HealthCache.swift`
  - Added cache age formatting, freshness/staleness helpers, and a default stale threshold.
- `Sources/MCPHQCore/LocalControlAPI.swift`
  - Local control status responses now include cache age, stale threshold, freshness, and refresh recommendation when backed by a health-cache snapshot.
- `Sources/MCPHQCore/LocalControlLaunchAgent.swift`
  - Helper endpoint availability messages now include cache freshness and relative age when available.
- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`
  - Added endpoint-backed coverage that a scan populates the helper health cache and a later default status response reports cached metadata.
- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`
  - Added fresh and stale cache metadata coverage.

## Validation

- `swift test --filter LocalControlAPITests --filter MCPHQCommandTests`

## Remaining gaps

- No automatic background refresh loop was added; scans remain explicit.
