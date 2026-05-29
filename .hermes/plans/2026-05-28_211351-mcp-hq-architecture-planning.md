# MCP-HQ Architecture Planning Document

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Establish the product, architecture, infrastructure, and roadmap foundation for MCP-HQ.

**Architecture:** Native macOS app plus local helper/core service. HTTP/Unix socket for control plane, MCP-native transport for optional data-plane proxying.

**Tech Stack:** SwiftUI, AppKit menu bar integration, Swift helper, SQLite, macOS Keychain, LaunchAgent/login item, optional future Rust MCP router.

---

## Deliverables created

- `README.md`
- `docs/PRD.md`
- `docs/TECH_STACK.md`
- `docs/ARCHITECTURE.md`
- `docs/INFRASTRUCTURE_FLOW.md`
- `docs/ROADMAP.md`
- `docs/OPEN_QUESTIONS.md`

## Next implementation plan

### Task 1: Create Swift app skeleton

**Objective:** Create the initial MCP-HQ macOS app project structure.

**Files:**

- Create: `app/MCPHQApp/`
- Create: `core/MCPHQCore/`
- Create: `fixtures/configs/`
- Create: `tests/`

**Verification:** Project builds with `swift build` or Xcode once package/project format is chosen.

### Task 2: Add fixture configs

**Objective:** Add representative Claude, Gemini, and Hermes MCP configs for parser tests.

**Files:**

- Create: `fixtures/configs/claude/mcp.json`
- Create: `fixtures/configs/gemini/mcp_config.json`
- Create: `fixtures/configs/hermes/config.yaml`

**Verification:** Fixture files parse as valid JSON/YAML.

### Task 3: Define registry schema

**Objective:** Create SQLite schema for canonical server registry.

**Files:**

- Create: `core/MCPHQCore/Sources/MCPHQCore/Registry/Schema.swift`
- Create: `core/MCPHQCore/Tests/MCPHQCoreTests/RegistrySchemaTests.swift`

**Verification:** Test creates in-memory DB and applies schema.

### Task 4: Implement config parsers

**Objective:** Parse known agent config shapes into `ServerDefinition` and `ConfigSource` records.

**Files:**

- Create: `core/MCPHQCore/Sources/MCPHQCore/ConfigParsing/ClaudeParser.swift`
- Create: `core/MCPHQCore/Sources/MCPHQCore/ConfigParsing/HermesParser.swift`
- Create: `core/MCPHQCore/Sources/MCPHQCore/ConfigParsing/GeminiParser.swift`

**Verification:** Golden fixture parser tests pass.

### Task 5: Implement read-only scanner

**Objective:** Combine config parsing and process scanning into one scan result.

**Files:**

- Create: `core/MCPHQCore/Sources/MCPHQCore/Scanning/Scanner.swift`
- Create: `core/MCPHQCore/Sources/MCPHQCore/Scanning/ProcessScanner.swift`

**Verification:** Scanner returns server inventory from fixtures and live machine process table.

### Task 6: Build first dashboard

**Objective:** Show scanned servers in a native macOS UI.

**Files:**

- Create/Modify: `app/MCPHQApp/...`

**Verification:** App launches and shows server list from scan results.
