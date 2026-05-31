# Pi Workstream Result: Doctor Filter Persistence

Merged on 2026-05-30.

## Changed Files

- `Sources/MCPHQApp/MCPHQApp.swift`
  - Persisted detailed Doctor severity/source/server filters with `@AppStorage`.
  - Kept the compact sidebar Doctor summary unfiltered so saved detailed filters do not hide sidebar alerts.
- `README.md`
- `docs/FULL_VISION_AUDIT.md`

## Validation

- `swift build --product MCPHQApp`

## Remaining Gaps

- Doctor export still only writes the current text report file.
- Richer export/share destinations and formats remain open.
