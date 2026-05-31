# Wave 8: Release and Native Polish

## Goal

Move MCP-HQ closer to a real distributable macOS app by improving bundle metadata and first-run/native polish without destabilizing core behavior.

## Requirements

- Audit `scripts/package_app.sh`, `Package.swift`, app metadata, and existing settings/native polish.
- Add a safe next release-polish slice such as app icon metadata placeholders, clearer bundle metadata, or packaging validation.
- Avoid requiring a real Developer ID certificate for tests.
- Preserve ad-hoc signing path with `SIGN_IDENTITY='-'`.
- Add or update package script tests when behavior changes.
- Write a result summary to `docs/pi-team/wave8-release-polish-result.md`.

## Suggested Starting Points

- `scripts/package_app.sh`
- `Package.swift`
- `Tests/MCPHQCoreTests/PackageAppScriptTests.swift`
- `Sources/MCPHQApp/MCPHQApp.swift`

## Validation

```bash
swift test --filter PackageAppScriptTests --filter NativeAppPreferencesTests
SIGN_IDENTITY='-' scripts/package_app.sh
```
