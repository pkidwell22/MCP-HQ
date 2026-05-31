# Wave 9: Background Health Cache

You are working in an isolated copy of MCP-HQ. Add a focused, testable slice for background scan cadence and health cache.

## Goal

Move toward a control-center model where the helper can serve cached health state instead of every UI refresh needing a fresh scan.

Suggested scope:

- Add a small health cache model/store around latest scan status, timestamp, and summary counts.
- Wire it through local-control status or scan response if clean.
- Keep behavior deterministic and redacted.

## Constraints

- Do not introduce a long-running scheduler if that is too large; a cache model with explicit update/read operations is enough for this wave.
- Prefer core tests.
- Avoid changing app behavior unless the model is proven.

## Deliverable

Write a result summary to `docs/pi-team/wave9-background-health-cache-result.md` with changed files, validation, and remaining gaps.
