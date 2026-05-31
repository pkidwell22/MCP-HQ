# Wave 9: Doctor Export Destination Polish

You are working in an isolated copy of MCP-HQ. Add the next safe slice for Doctor report export polish.

## Goal

The app already copies/exports redacted Doctor reports. Add a native user-chosen save destination or equivalent AppKit save-panel path for redacted Doctor reports.

## Constraints

- Preserve existing Application Support export path.
- Never export unredacted secrets.
- Keep scope focused; avoid broad UI redesign.
- Prefer testable formatting/export helper additions in core when practical.

## Deliverable

Write a result summary to `docs/pi-team/wave9-doctor-save-panel-result.md` with changed files, validation, and remaining gaps.
