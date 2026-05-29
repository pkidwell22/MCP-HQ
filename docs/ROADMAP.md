# MCP-HQ Roadmap

Last updated: 2026-05-29

## Phase 0: Planning and spikes

Goal: answer the riskiest architecture questions before building too much UI.

Tasks:

1. Create fixture MCP configs for Claude, Gemini, and Hermes.
2. Spike Swift parsing for JSON and YAML config shapes.
3. Spike process scanning on macOS with command-line capture.
4. Spike minimal MCP initialize + tools/list from Swift.
5. Spike Keychain read/write for secret placeholders.
6. Spike sandbox/TestFlight constraints.
7. Decide Developer ID first vs TestFlight-first.

Exit criteria:

- confirmed initial config formats
- confirmed process scanning approach
- confirmed whether Swift MCP discovery is practical
- packaging strategy chosen

## Phase 1: Read-only scanner: MCP Radar

Goal: show what exists without touching user files.

Features:

- SwiftUI app shell
- menu bar item
- dashboard window
- config scanner
- process scanner
- server list/detail screen
- local SQLite registry
- read-only diagnostic report export

Acceptance criteria:

- app launches on macOS
- scans `/Users/<user>/.claude/mcp.json` if present
- scans `/Users/<user>/.gemini/config/mcp_config.json` if present
- scans `/Users/<user>/.hermes/config.yaml` if present
- shows configured servers with source path
- shows detected running processes likely related to MCP
- does not write any config files

## Phase 2: Doctor mode

Goal: make MCP breakages understandable.

Features:

- command availability checks
- env var/secret checks
- JSON/YAML parse diagnostics
- duplicate server/tool detection
- safe MCP initialize + tools/list checks
- GUI PATH warning checks
- severity-ranked findings

Acceptance criteria:

- missing command produces actionable error
- invalid config produces exact file/path reason
- missing env var produces suggested Keychain mapping
- healthy server shows discovered tool count
- report can be copied/exported

## Phase 3: Config preview and generation

Goal: let the user safely manage per-agent MCP configs.

Features:

- internal canonical registry
- per-agent bindings
- generated config preview
- diff view
- backup before write
- rollback
- preserve unknown config entries where possible

Acceptance criteria:

- user can enable one server for Claude and preview diff
- user can write config after approval
- backup is created
- rollback restores exact previous content
- generated config parses successfully

## Phase 4: Keychain secrets

Goal: store credentials once and inject them safely.

Features:

- secret creation UI
- secret presence/status display
- env/header binding model
- generated configs reference or materialize secrets depending on agent capability
- redaction in logs and reports

Acceptance criteria:

- GitHub token can be saved as Keychain item
- server env var can bind to Keychain item
- reports never show raw token
- generated config warns if plaintext secret is required

## Phase 5: Hub-owned lifecycle management

Goal: MCP-HQ can own selected servers.

Features:

- convert imported server to hub-owned copy
- start/stop/restart
- log viewer
- health checks
- auto-start at login
- restart policy with loop protection

Acceptance criteria:

- user can start a hub-owned test server
- logs are visible
- server health updates in dashboard
- stop terminates correct process
- restart loop is detected and halted

## Phase 6: CLI and local API

Goal: make the core usable outside the UI.

Features:

- local API over Unix socket or localhost
- `mcphq` CLI
- commands:
  - `mcphq scan`
  - `mcphq list`
  - `mcphq doctor`
  - `mcphq config preview <agent>`
  - `mcphq logs <server>`

Acceptance criteria:

- CLI can trigger scan and list servers
- CLI can run doctor and emit JSON
- local API requires local auth token if exposed over HTTP

## Phase 7: Optional MCP router

Goal: expose selected downstream servers through one MCP endpoint.

Features:

- MCP server endpoint exposed by MCP-HQ
- downstream stdio and HTTP MCP clients
- tool namespacing
- session isolation
- audit logging
- basic policy enforcement

Acceptance criteria:

- an MCP client can connect to MCP-HQ router
- router lists namespaced tools from two downstream servers
- router can call a simple downstream tool
- denied tool returns clear MCP error
- per-agent audit event is recorded

## Phase 8: Catalog and profiles

Goal: make setup easy and repeatable.

Features:

- curated MCP server catalog
- install checks
- profiles: Coding, Research, Local-only, Dangerous, Client-specific
- one-click apply profile to agent
- import/export profile bundles

Acceptance criteria:

- user can install/configure a catalog server
- user can apply a profile to an agent
- generated config matches profile policy

## Recommended first implementation ticket list

1. Create Swift package/app skeleton. ✅
2. Add SQLite schema migrations for registry tables.
3. Add fixture configs under `fixtures/configs`. ✅
4. Implement Claude config parser. ✅
5. Implement Hermes config parser. ✅
6. Implement Gemini config parser. ✅
7. Implement process scanner. ✅
8. Implement server correlation heuristic.
9. Build server list UI using fixture data.
10. Connect UI to real scanner.
11. Add diagnostic report export.

## Release names

- 0.1 MCP Radar: read-only visibility
- 0.2 MCP Doctor: diagnostics
- 0.3 MCP Config: safe config generation
- 0.4 MCP Vault: Keychain secrets
- 0.5 MCP Supervisor: hub-owned lifecycle
- 0.6 MCP Router: optional proxy
