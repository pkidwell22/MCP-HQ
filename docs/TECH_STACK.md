# MCP-HQ Tech Stack Plan

Last updated: 2026-05-28

## Recommendation

Build MCP-HQ as a native macOS app with a separate local helper/core service.

Recommended initial stack:

- UI: SwiftUI
- menu bar/status item: AppKit `NSStatusItem` bridged into SwiftUI
- local storage: SQLite
- secrets: macOS Keychain
- background helper: Swift executable launched with LaunchAgent/SMAppService-style login item
- local control API: Unix domain socket preferred; localhost HTTP acceptable for early development
- config parsers: Swift Codable/YAML parser libraries
- MCP protocol: start with minimal Swift client for discovery; evaluate Rust core before proxy work
- packaging: Developer ID notarized app first; TestFlight feasibility spike early

## Why not Electron first?

Electron would be fastest for a UI but is poorly aligned with the product:

- heavy footprint while the user is already running many local servers
- awkward native integrations for Keychain, login items, sandboxing, process ownership
- less credible for a polished Mac utility

Electron is acceptable for a throwaway prototype, not the ideal product shell.

## Why not Tauri first?

Tauri is viable, especially if the core is Rust. But for a macOS/TestFlight-focused product, native SwiftUI has advantages:

- better menu bar and settings integration
- cleaner Keychain and macOS permissions story
- better TestFlight/App Store path
- no webview complexity for native controls
- easier integration with Login Items, notifications, file access prompts

Tauri remains a good fallback if cross-platform becomes a priority.

## Why native SwiftUI?

MCP-HQ is a Mac-first developer utility. It benefits from feeling native:

- menu bar status
- command palette / keyboard shortcuts later
- native settings
- native notifications
- Keychain
- file access panels/security-scoped bookmarks
- LaunchAgent/login item helper
- Apple notarization/TestFlight path

## Core service language options

### Option A: Swift core

Pros:

- simplest packaging
- one language
- strong macOS API integration
- easiest TestFlight path

Cons:

- likely more custom MCP protocol work
- fewer ready-made MCP SDK primitives than Python/TypeScript

Use for: MVP scanner, config manager, lifecycle manager.

### Option B: Rust core

Pros:

- excellent process/networking/system tooling
- portable later
- good async runtime
- strong fit for MCP proxy/router

Cons:

- Swift/Rust FFI or subprocess boundary
- more build/release complexity

Use for: future MCP router/proxy if Swift becomes painful.

### Option C: Node/Python helper

Pros:

- fastest MCP SDK reuse
- easiest protocol experimentation

Cons:

- runtime bundling
- heavier
- brittle user-machine dependencies
- worse TestFlight/App Store story

Use only for exploratory spikes, not the production Mac helper unless absolutely necessary.

## Recommended architecture split

### MCP-HQ.app

Responsibilities:

- SwiftUI dashboard
- menu bar state
- onboarding
- settings
- config diff preview
- permission prompts
- Keychain UI
- diagnostic report viewer

### MCP-HQ Helper

Responsibilities:

- process scanning
- config parsing/writing
- server launching/stopping for hub-owned servers
- log collection
- local control API
- MCP handshake/listing for discovery
- SQLite writes
- policy and profile evaluation

The helper should be restartable independently of the UI.

## Storage

Suggested app support paths:

- `~/Library/Application Support/MCP-HQ/mcphq.sqlite`
- `~/Library/Application Support/MCP-HQ/logs/`
- `~/Library/Application Support/MCP-HQ/backups/`
- `~/Library/Application Support/MCP-HQ/generated/`
- `~/Library/Application Support/MCP-HQ/catalog/`

Secrets:

- Keychain service: `com.mcphq.secrets`
- account format: `<server-id>/<secret-name>`

## Packaging strategy

### Phase 1: Developer ID notarized

Best for early power-user testing.

Advantages:

- fewer sandbox constraints
- easier access to config files and process APIs
- simpler helper story
- faster iteration

### Phase 2: TestFlight spike

Validate:

- can read/write selected config files after user grants access
- can install/manage helper/login item
- can inspect enough process metadata
- can launch subprocesses as needed
- can access Keychain as expected

### Phase 3: Decide distribution

Possible outcomes:

1. Stay Developer ID notarized for full power.
2. TestFlight/App Store for UI plus separately installed helper.
3. Sandboxed App Store version with reduced scope.

## Third-party dependencies to evaluate

Swift:

- SQLite.swift or GRDB for SQLite
- Yams for YAML parsing
- swift-argument-parser for CLI/helper commands
- swift-log for logging
- swift-crypto if needed

Rust, if used later:

- tokio
- serde
- sqlx or rusqlite
- rmcp or another MCP Rust crate if mature enough

## Testing stack

- XCTest for Swift units
- integration test fixtures for config files
- golden-file tests for generated configs
- subprocess fixture MCP servers for handshake/list_tools tests
- UI smoke tests later with XCUITest

## Development principle

Start with read-only discovery and diagnostics. Defer full proxying until after config/lifecycle flows are reliable.
