# MCP-HQ

MCP-HQ is a proposed native macOS control center for local Model Context Protocol servers.

The product direction is: see, fix, configure, and eventually broker every MCP server on a Mac from one place.

This repo contains architecture/product planning documents plus a Swift package for the app, CLI, and core library. The CLI can scan, diagnose, and safely preview/apply generated MCP configs for known coding agents. MCP-HQ inventories Antigravity, Pi, Hermes, Codex, OpenCode, Cursor, Windsurf, Continue, Goose, Claude, and Gemini, detects running MCP-like processes, and redacts sensitive values in text and JSON output. The SwiftUI app launches into an inventory and Doctor dashboard backed by the same scanner, JSON cache, and SQLite scan history.

## Planning docs

- `docs/PRD.md` — product requirements, users, scope, features, acceptance criteria.
- `docs/TECH_STACK.md` — recommended stack, alternatives, packaging and TestFlight notes.
- `docs/ARCHITECTURE.md` — system architecture, components, data model, API boundaries.
- `docs/INFRASTRUCTURE_FLOW.md` — discovery, config generation, server lifecycle, proxy flow diagrams.
- `docs/ROADMAP.md` — phased build plan from read-only scanner to MCP router.
- `docs/OPEN_QUESTIONS.md` — technical, product, and distribution questions to answer early.

## CLI

Run a safe MCP inventory scan:

```bash
swift run mcphq scan
swift run mcphq scan --json
swift run mcphq scan --source claude:/path/to/claude_desktop_config.json
swift run mcphq scan --source gemini:/path/to/mcp_config.json
swift run mcphq scan --source hermes:/path/to/config.yaml
swift run mcphq scan --source codex:/path/to/config.toml
swift run mcphq scan --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
```

`scan` reports each known source as missing, parsed, malformed, unsupported, or present-without-servers; detects running MCP-like processes via macOS `ps`; and uses redacted env bindings, headers, URLs, and process command lines for both terminal and JSON output. JSON-style agents read `mcpServers`, `mcp_servers`, or `servers` containers, including stdio servers (`command`, `args`, `env`) and remote servers (`url`, `httpUrl`, or `serverUrl`). Hermes and Goose support read `mcp_servers` YAML blocks. Codex support reads TOML tables under `[mcp_servers.<name>]`.

Run actionable diagnostics:

```bash
swift run mcphq doctor
swift run mcphq doctor --json
swift run mcphq doctor --probe
swift run mcphq doctor --severity warning --server github
swift run mcphq doctor --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
```

Preview or safely apply generated agent configs:

```bash
swift run mcphq config preview --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json
swift run mcphq config apply --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json --dry-run
swift run mcphq config connect-all preview --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json --target-source codex:/tmp/config.toml
swift run mcphq config connect-all apply --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json --target-source codex:/tmp/config.toml --dry-run
swift run mcphq config connect-all apply --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json --probe
swift run mcphq config preview --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json" --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json
swift run mcphq config connect-all preview --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json" --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json
```

Explain runtime ownership/control limits and tail local logs safely:

```bash
swift run mcphq control status
swift run mcphq control status --json --probe
swift run mcphq control status --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
swift run mcphq control serve --port 37373
swift run mcphq control launch-agent install --dry-run
swift run mcphq control launch-agent status
swift run mcphq control launch-agent bootstrap
swift run mcphq control launch-agent bootout
swift run mcphq history list --limit 5
swift run mcphq history show <run-id> --json
swift run mcphq history doctor --limit 5
swift run mcphq history doctor <run-id> --json
swift run mcphq registry sources
swift run mcphq registry desired --json
swift run mcphq registry rollbacks
swift run mcphq registry runtimes
swift run mcphq registry secrets --json
swift run mcphq runtime explain
swift run mcphq runtime explain --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
swift run mcphq runtime start --source hermes:"$HOME/.hermes/config.yaml" --server memory --log-directory "$HOME/Library/Application Support/MCP-HQ/logs" --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
swift run mcphq runtime stop --runtime-id "hub:<server-id-from-start-output>" --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
swift run mcphq runtime restart --runtime-id "hub:<server-id-from-start-output>" --source hermes:"$HOME/.hermes/config.yaml" --server memory --log-directory "$HOME/Library/Application Support/MCP-HQ/logs" --endpoint-file "$HOME/Library/Application Support/MCP-HQ/control-endpoint.json"
swift run mcphq logs --file /path/to/server.log --runtime-id server-id --lines 50
```

`control serve` runs a foreground loopback helper and writes its URL/token metadata to `~/Library/Application Support/MCP-HQ/control-endpoint.json` by default. `control status --endpoint-file ...` uses that metadata to call the helper over HTTP and reports health-cache timestamp, age, cache source, freshness/staleness, refresh recommendation, and scan status when the helper can serve a matching cached status. `control launch-agent install` renders or writes a user LaunchAgent plist for the helper without persisting a token in the plist by default; the plist carries a deterministic `PATH` with current, Homebrew, and system locations so LaunchAgent scans can find common MCP commands such as `npx`. `bootstrap`, `bootout`, and `status` wrap `launchctl` so the helper can be managed as a login-session service. The native app also includes a Control Helper sheet that resolves the bundled helper path, reports plist/launchd/endpoint status, previews or writes the plist, offers a confirmation-gated Install & Start path, uses confirmation-gated Start/Stop controls for the `com.mcphq.control` user LaunchAgent, and includes helper cache freshness in the endpoint availability message when available.

`history list` reads the local SQLite scan history and prints recent run timestamps, IDs, and source/server/finding/process/probe counts. Add `--json` for machine-readable run summaries. `history show <run-id>` prints a redacted scan report for an individual run; add `--json` for a redacted machine-readable wrapper with scan details. `history doctor` lists persisted redacted Doctor report summaries, and `history doctor <run-id>` prints or exports the stored report for a run. `registry agents|sources|desired|backups|runtimes|secrets` queries the emerging local control-plane tables for known agents, source bindings, desired server states, config backup records, persisted runtime rows, and Keychain secret binding references; add `--json` for automation or `--source agent:/path` to filter source-scoped views. The native app exposes recent-run summary counts in a History sheet and can open, copy, or export an individual run as redacted TXT or JSON, including the stored Doctor report when one exists.

The core library also includes a config generation/safe-apply foundation: agent-specific renderers, binding draft previews and apply support for enabling/disabling a server across existing or missing known-agent configs, a canonical authoring model that merges persisted desired state with the latest scan and reports secret-safe binding and payload drift, a Config Manager snapshot adapter for native canonical state display, bulk connect-all previews and applies that spread a template server set into selected known-agent configs with one write per target file, CLI bulk connect-all preview/apply dry-run support for explicit target sets, named reusable Connect All target profiles, stale-preview file snapshot checks for guarded app bulk applies, compact diff preview text, dry-run/apply behavior, timestamped backups, generated-config reparse verification, rollback on write verification failure, multi-source binding rollback snapshots, persisted bulk rollback transactions with CLI rollback by transaction ID, preservation of non-MCP JSON root keys plus known YAML/TOML non-MCP sections where supported, preservation of unchanged Codex MCP blocks during TOML authoring, Keychain secret reference models, secret migration planning/batch migration helpers, secret presence validation, migration-write-failed recovery state with partial-write rollback guidance, lifecycle/control explanations, bounded redacted log loading for known supervised log paths, a hub-owned runtime supervisor foundation that only controls processes it started, helper-backed CLI `runtime start|stop|restart` actions, redacted log tailing and supervised stdout/stderr log paths, live-probe result reuse for identical command/URL/env/header targets across repeated agent bindings, a SQLite scan-history/Doctor-report history store with CLI run summaries, control-plane tables for agents/source bindings/desired server states/runtime instances/config backups/bulk rollback transactions/Connect All target profiles/secret bindings, persisted desired-state and backup breadcrumbs after guarded binding applies, persisted hub-owned runtime visibility in CLI/app lifecycle views with stale PID reconciliation, a redacted in-process local control API router for status/scan/servers/doctor/config preview/config apply/config connect-all preview/config connect-all apply/runtime explain/runtime start/runtime stop/runtime restart, redacted helper health-cache snapshots and freshness metadata for matching default status requests, a JSON envelope codec plus shared local-control client for the future IPC boundary, endpoint-backed CLI dispatch for scan/doctor/control status/config preview/config apply/config connect-all preview/config connect-all apply/runtime explain/runtime start/runtime stop/runtime restart, an endpoint-backed HTTP client, an HTTP-shaped `/api/v1/control` adapter with optional local token enforcement, a minimal 127.0.0.1 loopback HTTP server and endpoint-file launcher for that adapter, LaunchAgent plist/launchctl management for the helper, and secret-safe rendering that emits references/redactions instead of plaintext-looking secrets.

## App

Launch the read-only dashboard:

```bash
swift run MCPHQApp
```

Build a local `.app` bundle that can be launched independently of the terminal:

```bash
scripts/package_app.sh
open .build/MCP-HQ.app
```

Set `SIGN_IDENTITY='-'` for ad-hoc signing, or pass a Developer ID identity for distribution builds. The bundle embeds the `mcphq` CLI helper in `Contents/MacOS/mcphq` so LaunchAgent-managed control helpers do not depend on a SwiftPM checkout.

The dashboard shows server/process/source/issue counts, first-run guidance when no inventory is found, agent source health, Doctor findings with why/fix explanations, persisted filters, filtered copy/export to text or JSON, and safe Open Config/Preview Config actions, grouped inventory rows by agent/source, a searchable/copyable server inspector for tools/resources/prompts, a History sheet with recent scan timestamps, run IDs, source/server/finding/process/probe counts, and selected-run redacted TXT/JSON copy/export from SQLite, a Lifecycle & Logs sheet with ownership/control explanations, guarded Start/Stop/Restart controls for helper-owned runtimes, copy-only safe actions, automatic lookup of hub-owned supervised logs when a log directory is supplied, and bounded redacted log loading when MCP-HQ knows a supervised log path, a Settings sheet for history/export/probe/helper endpoint preferences, a Control Helper sheet for installing and starting/stopping the packaged local-control helper LaunchAgent, a Config Manager sheet with agent-source readiness, canonical desired/observed/drift state, low-risk suggested action text for canonical drift, persisted desired-state binding defaults, server binding coverage, per-agent binding checkboxes for existing config files, per-binding/per-server literal secret counts, guarded secret review/migration into Keychain-backed references, draft previews for enabling/disabling a binding, a guarded multi-source binding apply flow, and a guarded Preview Connect All flow that uses the largest parsed source as the template set, lets the user choose target configs, previews creating/updating safe-authorable known-agent configs, rejects stale target files at apply time, shows a structured post-write verification matrix, exposes a guarded rollback for the successful bulk apply, shows persisted Connect All rollback transactions after the result sheet is closed, and forces a live probe scan after successful app applies. It also shows running MCP-like process rows with ownership and CPU/memory visibility, warning/error details, secret-safe config previews with diff text, guarded apply, backup rollback after apply, plaintext-secret migration to Keychain-backed references, detected secret/reference rows, migration-write-failed recovery rows with status-specific review/retry labels, and redacted environment variables. Refreshes persist `last-scan.json` plus `history.sqlite3` under Application Support, and the dashboard window uses macOS frame autosave to remember size and position. Use `⌘R` or the Refresh button to rescan known macOS config locations and running processes.

## Core architectural principle

Use HTTP/Unix socket APIs for the control plane.

Keep MCP traffic as MCP for the data plane.

In other words, do not replace MCP with a custom REST abstraction. If MCP-HQ proxies tool calls, it should expose a real MCP server/router endpoint and preserve MCP semantics.
