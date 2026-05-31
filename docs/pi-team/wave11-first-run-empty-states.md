# Wave 11: First Run and Empty States

You are working in a temporary repo copy for MCP-HQ. Implement a focused native polish slice around first-run or empty states.

Context:
- The app is bundle-able and has settings, history, helper, doctor, lifecycle, and config manager sheets.
- The app still needs production polish for first-run/empty-state clarity.

Goal:
- Improve one or two empty states that matter most for a new user connecting coding agents.

Requirements:
- Keep UI practical and app-like; no landing-page/marketing hero.
- Do not add large decorative layouts.
- Prefer existing SwiftUI style and concise copy.
- Add focused tests if state/model logic changes; if UI-only, build the app.
- Write a result summary to `docs/pi-team/wave11-first-run-empty-states-result.md` with changed files, validation, and remaining gaps.

Validation:
- Run relevant focused tests if added.
- Run `swift build --product MCPHQApp`.
