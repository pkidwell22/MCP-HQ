# MCP-HQ Product Requirements Document

Last updated: 2026-05-28

## 1. Product summary

MCP-HQ is a macOS app for managing local MCP servers across AI agents and desktop tools.

It discovers running and configured MCP servers, diagnoses broken setups, centralizes secrets, generates app-specific MCP configs, manages server lifecycles, and eventually offers an optional MCP-native proxy/router with permissions and audit logs.

Short positioning:

> Docker Desktop for local MCP servers.

Alternate positioning:

> The Mac control center for MCP.

## 2. Problem

Power users now run many local AI apps and agents: Claude Desktop, Gemini, Hermes, Pi, Cursor, Codex, OpenCode, and others. Each app has its own MCP config format, its own environment assumptions, and its own way of launching stdio or HTTP servers.

The result is messy:

- duplicated MCP server definitions
- scattered config files
- secrets copied into multiple places
- missing PATH/env variables in GUI-launched apps
- stale npx/uvx/bun/python commands
- orphaned or invisible running processes
- hard-to-debug initialization failures
- no easy view of which agent can access which tool
- no safe rollback after config edits

## 3. Target users

### Primary user

A local AI power user/developer running several AI clients on macOS and multiple MCP servers.

They are comfortable with agents and local tools, but do not want to hand-edit five different config files every time they add a server.

### Secondary users

- indie developers building AI workflows
- small internal teams standardizing MCP setups
- creators using specialized MCP servers for design, video, notes, browser, GitHub, etc.
- MCP server authors who need a clean way for users to install and validate their servers

## 4. Goals

### MVP goals

1. Show all configured MCP servers across known apps.
2. Show running MCP-like processes and map them to configs where possible.
3. Diagnose common failures.
4. Preserve user trust with read-only mode first.
5. Provide a clear path to safe config generation and rollback.

### Long-term goals

1. Centralize MCP secrets in macOS Keychain.
2. Generate correct per-agent MCP configs.
3. Manage hub-owned server processes.
4. Provide profiles/policies per agent.
5. Expose an optional MCP-native router/proxy.
6. Audit MCP usage and enforce permissions.
7. Provide a curated MCP server catalog.

## 5. Non-goals for MVP

- Cloud sync.
- Team management.
- Payments/marketplace.
- Full many-agent multiplexed MCP proxy.
- Replacing MCP with a custom REST tool-calling API.
- App Store-first compliance at the expense of functionality.
- Cross-platform support before the macOS product works well.

## 6. Core product principles

1. Control plane can be HTTP or Unix socket.
2. Data plane should stay MCP.
3. Never write configs without preview, backup, and rollback.
4. Prefer read-only discovery before mutation.
5. Treat secrets as Keychain objects, not strings in JSON/YAML.
6. Be honest about ownership: agent-owned vs hub-owned servers.
7. Preserve per-agent isolation when proxying.
8. Make common breakages obvious and fixable.

## 7. Key features

### 7.1 MCP inventory

The app scans known config locations and running processes.

Initial config sources:

- `~/.claude/mcp.json`
- `~/.gemini/config/mcp_config.json`
- `~/.hermes/config.yaml`
- future: Cursor, Windsurf, Continue, Goose, OpenCode, Codex, Pi

Initial process discovery:

- process name and command line matching common MCP patterns
- child processes launched by known AI apps
- stdio servers launched through `npx`, `bun`, `uvx`, `python`, native binaries
- HTTP servers listening on localhost ports, when detectable

Displayed fields:

- server name
- config source
- transport: stdio, HTTP, SSE, streamable HTTP
- command or URL
- owning agent/app
- running status
- pid, CPU, memory when available
- exposed tools/resources/prompts when discoverable
- missing env vars or secrets
- last initialization error

### 7.2 Doctor mode

Doctor mode explains why a server is broken or risky.

Checks:

- config file exists and parses
- command exists under expected PATH
- args are valid enough to launch
- required env vars are present or mapped to Keychain
- server can initialize via MCP handshake
- tools/list succeeds
- duplicate server names
- duplicate tool names across agents/profiles
- unsafe filesystem roots
- GUI app PATH mismatch
- stale generated config compared with canonical registry

### 7.3 Config manager

The user can import existing configs into an internal registry and generate per-agent configs.

Requirements:

- diff preview before write
- automatic backups before write
- rollback UI
- per-agent enable/disable checkboxes
- comments explaining generated sections where supported
- never overwrite unknown user config without preserving it

### 7.4 Secrets manager

Secrets live in macOS Keychain and are referenced by server env bindings.

Examples:

- `GITHUB_PERSONAL_ACCESS_TOKEN` -> Keychain item `mcp-hq/github/pat`
- `OPENAI_API_KEY` -> Keychain item `mcp-hq/openai/default`

The app should show whether a secret exists without showing its value by default.

### 7.5 Server lifecycle manager

For hub-owned servers only, the app can:

- start
- stop
- restart
- tail logs
- auto-start at login
- health check
- show CPU/memory

Agent-owned servers are observed and configured, not forcibly managed, unless the user converts them to hub-owned.

### 7.6 Local control API

A local API lets CLI tools and agents inspect MCP-HQ state.

Examples:

- `GET /api/v1/servers`
- `GET /api/v1/agents`
- `GET /api/v1/agents/{agent}/config-preview`
- `POST /api/v1/servers/{id}/start`
- `POST /api/v1/doctor/run`

This API is not a replacement for MCP tool calls.

### 7.7 Optional MCP router/proxy

The hub may later expose a real MCP endpoint that aggregates downstream MCP servers.

Requirements:

- preserve MCP capabilities and semantics
- namespace downstream tools deterministically
- isolate per-upstream client sessions
- forward progress, cancellation, logging, prompts/resources, and errors correctly
- preserve or explicitly reject advanced features like sampling and roots
- enforce per-agent policies at runtime

## 8. Success metrics

MVP success:

- detects at least Claude, Gemini, and Hermes configs on the developer machine
- detects running stdio servers launched through common runtimes
- identifies at least 80% of obvious broken/missing-command/missing-env issues
- can initialize and list tools for safe test servers
- zero destructive writes in read-only mode

Beta success:

- users can add one server and enable it for multiple agents without hand-editing configs
- rollback works reliably
- secrets are not stored in plaintext generated configs unless the destination app requires it and the user approves
- server logs and status reduce debugging time

## 9. Risks

- App sandbox/TestFlight restrictions may block filesystem and process management use cases.
- MCP protocol support in Swift may require custom implementation or a Rust core.
- Proxying MCP incorrectly can break advanced servers.
- Generated configs can damage user workflows if backup/rollback is weak.
- Process detection can be noisy and heuristic-heavy.

## 10. Initial acceptance criteria

Version 0.1 should pass:

1. Launch as a macOS menu bar app.
2. Display a dashboard window.
3. Parse at least one existing MCP config file.
4. Show server cards with name, source, command/url, transport, and status.
5. Run doctor checks without writing files.
6. Save scan results to local app storage.
7. Export a human-readable diagnostic report.
