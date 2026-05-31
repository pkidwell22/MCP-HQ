# Wave 8 Release Polish Result

Integrated in main worktree.

## Changed

- `scripts/package_app.sh`
  - Added staged bundle validation before replacing the final `.app`.
  - Added optional `.icns` support via `APP_ICON_PATH` and `APP_ICON_NAME`.
  - Added clearer bundle metadata: `CFBundleGetInfoString`, `CFBundleSpokenName`, and `NSPrincipalClass`.
  - Preserved ad-hoc signing with `SIGN_IDENTITY='-'`.
- `Tests/MCPHQCoreTests/PackageAppScriptTests.swift`
  - Added coverage for validation and optional icon packaging hooks.

## Validation

- `swift test --filter AgentConfigRendererTests --filter LocalControlAPITests --filter PackageAppScriptTests`
