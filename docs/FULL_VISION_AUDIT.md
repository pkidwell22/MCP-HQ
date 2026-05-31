# MCP-HQ Full Vision Audit

Last updated: 2026-05-30

This audit compares the current repo against `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/INFRASTRUCTURE_FLOW.md`, and `docs/ROADMAP.md`.

## Current Proven State

- Native SwiftUI dashboard and menu bar extra launch from SwiftPM.
- Local `.app` bundle can be built with `scripts/package_app.sh`, ad-hoc signed with `SIGN_IDENTITY='-'`, verified with `codesign`, and launched with `open .build/MCP-HQ.app`; the bundle now includes the `mcphq` CLI helper under `Contents/MacOS/mcphq`.
- Read-only scan covers Antigravity, Pi, Hermes, Codex, OpenCode, Cursor, Windsurf, Continue, Goose, Claude, and Gemini config sources.
- Source health reports missing, parsed, unsupported, malformed, and no-server states.
- Inventory groups configured servers by agent/source in the app.
- Config parsers preserve stdio, HTTP/SSE/streamable HTTP, env, headers, disabled flags, and source paths for supported formats.
- Process scanner finds MCP-like processes and correlates common stdio targets.
- Process rows include ownership classification for configured matches plus CPU and memory fields from macOS `ps`.
- Runtime lifecycle explanations classify observed processes as agent-owned, hub-owned, or unknown and explain which start/stop/restart actions are disabled or available.
- Core has lifecycle panel state/formatting with ownership, control explanations, log hints, available hub-owned control actions, and copy-only safe actions.
- CLI exposes `mcphq runtime explain`, helper-backed `mcphq runtime start|stop|restart`, and redacted `mcphq logs --file ...` tailing; the native Lifecycle & Logs sheet can use the helper to start configured stdio servers as hub-owned runtimes, stop/restart eligible hub-owned runtimes, reconcile persisted hub-owned rows with observed processes/log paths, explain stale runtime recovery without controlling unknown PIDs, show helper availability, resolve `keychain://` and environment references into the child process environment for hub-owned launches, and load bounded redacted log tails when MCP-HQ has a known supervised log path.
- Core has a hub-owned runtime supervisor foundation that can start tracked stdio processes, capture stdout/stderr log paths, stop/restart only tracked hub-owned processes, refuse agent-owned or unknown runtimes, and expose helper-gated CLI lifecycle actions so destructive controls do not run as short-lived direct-core calls.
- Live probes initialize MCP servers, list tools/resources/prompts, run ping where supported, redact suspicious output, and reuse results for identical command/URL/env/header targets across intentionally repeated agent bindings.
- Core renderer/applier can preview generated configs, render agent-specific formats, produce compact diff text, preserve non-MCP JSON root keys plus known YAML/TOML non-MCP sections where supported, preserve unchanged Codex MCP blocks while adding/removing TOML server bindings, create timestamped backups, re-parse generated configs, support dry-run/apply, reject stale guarded bulk applies when a target file changed after preview, and roll back after write verification failure.
- CLI now exposes `mcphq doctor` with text/JSON output, severity/source/server filters, and `mcphq config preview/apply`.
- The app shows Doctor findings with source/server grouping, why-it-matters text, suggested fixes, probe/source-health failures, persisted severity/source/server filters, filtered copy/export to text or JSON, user-chosen save destinations for redacted TXT/JSON reports, and safe Open Config/Preview Config actions.
- The app has a Config Manager sheet that groups agent sources, shows canonical desired/observed/drift state and low-risk suggested actions for server bindings, opens existing config files, launches source-level preview/apply flows, previews per-agent binding enable/disable drafts for existing or missing known-agent config files, exposes a guarded multi-source binding apply action, shows a structured post-apply verification matrix for Connect All results, and supports reusable Connect All target profiles that can be saved, loaded, and immediately reused in the target picker.
- The app can preview generated config text and diff output for a selected source, then apply after confirmation using timestamped backup, non-MCP section preservation where supported, and reparse verification.
- Keychain secret models, detection, migration planning/batch migration helpers, and presence validation exist in core; the app surfaces detected literal secrets and Keychain references in the inspector.
- The Config Manager shows per-binding/per-server literal secret counts and exposes guarded binding-level secret review/migration into Keychain-backed references, with config snapshots restored and newly written references deleted if a later config write fails.
- Keychain migration write failures are represented as redacted recoverable states; failed guarded migrations record failed/pending secret references for follow-up and remove partial Keychain writes before retry guidance is shown.
- The dashboard can validate persisted secret-binding rows and current `keychain://` config references using presence-only Keychain checks, then surface missing/inaccessible/migration-write-failed references with safe recovery guidance and status-specific action labels that never reveal secret values.
- The app writes a JSON last-scan cache under Application Support and reloads it on launch before refreshing; the helper also has a redacted health-cache snapshot for scan/status summary counts keyed by requested source scope and probe mode.
- Core has a SQLite scan history store for scan runs, sources, servers, Doctor findings, runtime process snapshots, and redacted Doctor report history; the app writes this history on refresh/probe, the native app has a History sheet for recent run summaries and selected-run redacted TXT/JSON copy/export including stored Doctor reports when available, `mcphq history list` can query recent run summaries as text or JSON, `mcphq history show <run-id>` can inspect/export an individual run through redacted text or JSON, and `mcphq history doctor [run-id]` can list or inspect persisted redacted Doctor reports.
- SQLite migrations now include first control-plane tables for agents, source bindings, desired server states, runtime instances, config backups, bulk rollback transactions, reusable Connect All target profiles, and secret bindings. Saved scans sync agent/source rows, guarded binding applies record desired server state and config backup breadcrumbs, Connect All applies persist rollback transactions, hub-owned supervisor start/stop writes the latest runtime row, successful Keychain migrations record secret binding references, and `mcphq registry agents|sources|desired|backups|rollbacks|target-profiles|runtimes|secrets` exposes these rows as text or JSON.
- Core has an in-process local control API router foundation for status, scan, servers, doctor, config preview, dry-run-first config apply, config connect-all preview/apply, runtime explain, and guarded hub-owned runtime start/stop/restart responses; default non-probe status can reuse a matching redacted helper health-cache snapshot; `mcphq control status` surfaces scanned timestamp, cache age, cache source, freshness/staleness, refresh recommendation, and scan status when that metadata is available; `mcphq scan --endpoint-file ...`, `mcphq doctor --endpoint-file ...`, `mcphq control status --endpoint-file ...`, `mcphq config preview/apply --endpoint-file ...`, `mcphq config connect-all preview/apply --endpoint-file ...`, and `mcphq runtime explain|start|stop|restart --endpoint-file ...` can use the helper boundary.
- Core has a redacted JSON local-control envelope codec plus a shared in-process client; `mcphq control status` exercises that client path and can include probe-derived warning/error counts.
- Core has an HTTP-shaped `/api/v1/control` adapter for the local-control envelope with JSON responses, no-store headers, route/method validation, and optional Bearer or `X-MCPHQ-Token` enforcement.
- Core has a minimal 127.0.0.1 loopback HTTP server candidate for the control adapter, verified through `URLSession`.
- `mcphq control serve` can run the loopback control server in the foreground and write endpoint/token metadata to a discoverable JSON file.
- Core has an endpoint-backed HTTP client, and `mcphq control status --endpoint-file ...` plus `mcphq runtime explain|start|stop|restart --endpoint-file ...` can call a running foreground helper instead of calling core in-process.
- Core has shared client fallback policy for local-control routes: read-only requests may prefer an endpoint and fall back to direct core when unavailable, while guarded config apply and runtime mutation routes do not fall back.
- The native app dashboard refresh and probe refresh now prefer the configured helper endpoint for read-only scans, pass the app's explicit target sources through the local-control request, preserve direct-core fallback, and expose the dashboard client backend/availability in the Control Helper sheet.
- Core can render/install/remove the user LaunchAgent plist for the foreground helper without persisting a token in the plist by default; the plist includes a deterministic command `PATH` for LaunchAgent scans so common MCP commands installed through Homebrew or system locations are discoverable.
- `mcphq control launch-agent bootstrap`, `bootout`, and `status` wrap `launchctl` with redacted output so the helper can be managed as a login-session service.
- The native app has a Control Helper sheet that resolves the packaged `Contents/MacOS/mcphq` helper, reports plist/launchd/endpoint availability, previews exact LaunchAgent XML, writes the plist, exposes a confirmation-gated Install & Start path, and exposes confirmation-gated Start/Stop controls for the `com.mcphq.control` user LaunchAgent.
- The native app has a Settings sheet for history limit, preferred History export format, probe-on-refresh, and helper endpoint path preferences.
- The native Config Manager uses persisted desired-server-state rows as binding defaults when present, including desired-only bindings that are not present in the latest scan.
- Core has a canonical authoring model that merges scan results with persisted desired server state, distinguishes desired-enabled, desired-disabled, and observed-only source bindings, reports drift such as missing-from-scan, present-but-disabled, and payload mismatches across transport, command, args, URL, env, and headers without exposing secret values, and produces deterministic suggested actions for missing/disabled/payload drift.
- The native server inspector can search/filter tools/resources/prompts and copy redacted capability names or summaries.

## Major Remaining Gaps

### 1. Doctor UI and Report Export

Core and app Doctor views exist, including filtering, safe source/preview actions, redacted text/JSON exports to Application Support, and user-chosen save destinations. Remaining Doctor work is polish rather than a blocking product gap.

### 2. Config Manager UI and CLI Workflow

Safe apply exists in core, CLI, local API, a guarded app preview sheet, and an app Config Manager sheet. The app apply flow now exposes backup rollback after a successful write, binding draft previews can model and apply enabling/disabling a server across existing or missing known-agent config files with per-file backups and rollback snapshots if a later write fails, and the Config Manager now has a guarded Preview Connect All path that uses the largest parsed source as the template set, starts from one preferred safe-authorable config per other known agent, lets the user adjust target configs, previews the selected bulk draft before confirmed apply, rejects apply if a selected target changed after preview, reports fresh parse/binding verification, shows structured target-by-target verification in the native result sheet, exposes guarded rollback for the successful bulk apply, persists rollback transactions for later CLI rollback by transaction ID, shows persisted rollback transactions in native Config Manager after the result sheet is closed, labels the result as configured rather than agent-loaded, shows a structured redacted diff alongside the compact preview, and forces a live probe scan after successful app applies regardless of the global Refresh probe preference. The CLI can also preview or dry-run/apply explicit bulk connect-all target sets directly or through the local-control endpoint, save and reuse named Connect All target profiles, and `config connect-all apply --probe` adds live probe evidence to the post-apply verification report. The remaining work is turning this into a complete authoring surface for richer edits.

Needed:

- Add execution flows for canonical drift suggestions, especially review-required payload replacement previews.
- Broaden unknown config preservation beyond JSON roots, known YAML blocks, and unchanged Codex MCP blocks.

### 3. Keychain Secret Management

Keychain abstractions, read-only app visibility, guarded server-level migration, guarded Config Manager binding-level migration, partial-write rollback, and migration-write-failed recovery rows with retry/review labels exist.

Needed:

- Add a dedicated cleanup/retry executor and richer validation UX around Keychain write failures beyond the current recovery panel labels.

### 4. Local Persistence

The app now has a JSON last-scan cache plus SQLite scan-run/Doctor-report history, first-pass control-plane tables, CLI registry views, scan-synced agent/source rows, desired-state/backup breadcrumbs for guarded binding applies, a canonical authoring model that merges desired state with the latest scan and detects secret-safe payload drift, native Config Manager canonical state display with low-risk suggestion text, persisted bulk rollback transactions for Connect All with native Config Manager review/rollback UI, persisted latest hub-owned runtime rows after supervisor start/stop, stale persisted hub-owned runtime reconciliation in runtime explain/Lifecycle & Logs surfaces, and secret-binding reference rows after successful or failed Keychain migrations. The remaining persistence work is turning those rows into the full canonical control-plane database and expanding beyond scan-shaped details into historical trends and richer runtime/secret state.

Needed:

- Extend persisted runtime rows beyond latest-state recovery into richer history and drift analysis.
- Wire canonical drift suggestions into richer edit execution, payload drift resolution, and stale-intent cleanup.
- Add richer Doctor-history comparison/trend views across runs.
- Broaden individual-run exports beyond current redacted scan TXT/JSON into relational source/finding/process snapshots and trend views.

### 5. Lifecycle, Ownership, and Logs

Process visibility, observed ownership, lifecycle explanations, manual redacted log tailing, bounded native log loading for known supervised log paths, automatic safe lookup of hub-owned supervisor logs from a requested log directory, a core hub-owned supervisor foundation, persisted hub-runtime reconciliation/recovery messaging, helper availability gating, child-process-only Keychain/env reference injection for hub-owned launches, in-process local API runtime actions, helper-backed CLI start/stop/restart for hub-owned runtimes, and guarded native Start/Stop/Restart controls for helper-owned runtimes exist.

Needed:

- Improve native app lifecycle controls with richer process status updates and live status refresh cadence.
- Expand automatic server-bound log lookup beyond hub-owned supervised log naming.
- Native app lifecycle/log controls beyond current helper-backed start/stop/restart plus bounded log viewing.

### 6. Local Control API

The app still has some direct-core read paths, and some CLI commands still call core directly, but a redacted in-process control API router foundation exists and now covers runtime explain/start/stop/restart in addition to scan/doctor/config routes. A JSON envelope codec, shared in-process client, endpoint-backed HTTP client, HTTP-shaped adapter, minimal 127.0.0.1 server candidate, foreground `control serve` command with endpoint-file metadata, redacted helper health-cache snapshots for default status, CLI status metadata for cache age/state, LaunchAgent install/bootstrap/bootout/status commands, and a native Control Helper status/install-prep sheet exist. The CLI can call a running helper endpoint for scan, doctor, control status, config preview/apply, config connect-all preview/apply, runtime explain, and helper-gated runtime start/stop/restart. The native dashboard refresh/probe refresh now use the endpoint-preferring client path for read-only scans.

Needed:

- Decide Unix socket vs localhost HTTP for early helper.
- Wire remaining CLI/app paths through the shared client.
- Decide whether the production helper uses the current loopback HTTP server, a Unix socket sibling, or both.
- Extend helper-backed client usage into more CLI routes and more app read paths beyond dashboard/probe scan refresh.
- Decide production token generation/storage if using HTTP.
- Background scan cadence and richer app-visible health-cache age/state.

### 7. App Polish and Native Distribution

The app is now bundle-able with version metadata, atomic bundle replacement, staged bundle validation, optional `.icns` icon embedding, `plutil` validation, signing hooks, persisted sidebar visibility, first-run/empty-state guidance, and AppKit-backed dashboard window size/position autosave. It is not yet production-distributed.

Needed:

- Branded app icon asset.
- Notarizable release workflow.
- Better first-run and empty states.
- Optional login item.
- Visual/UI snapshot tests.

### 8. Optional MCP-Native Router

No router exists yet, and it should remain later-phase work.

Needed:

- Real MCP server endpoint, not REST-shaped tools.
- Downstream stdio/SSE/streamable HTTP forwarding.
- Correct session semantics.
- Notifications, roots, cancellation, progress, sampling behavior.
- Per-agent isolation and auth/token policy.

## Best Next Parallel Workstreams

1. **Config manager UI workstream:** evolve the native Config Manager sheet from canonical state display into guided edit and drift-resolution flows.
2. **Secrets UI workstream:** add retry/cleanup affordances on top of migration-write-failed recovery rows.
3. **Lifecycle/logs workstream:** implement hub-owned supervision, log capture, and read-only explanations for externally owned processes.
4. **Local control API workstream:** introduce a helper API and shared app/CLI client.
5. **Persistence workstream:** evolve SQLite scan history into the canonical registry and query surface.
6. **Packaging workstream:** add icon, release signing/notarization, settings, and login item polish.

## Completion Bar

The full vision is not complete until the app can:

- Launch as a packaged macOS app.
- Persist and reload scan state.
- Export Doctor reports and attach safe actions.
- Apply, back up, and roll back agent configs from user-facing app flows.
- Migrate secrets through Keychain without exposing values across the full config-manager flow.
- Manage lifecycle/logs for hub-owned servers.
- Expose the local control API over the chosen IPC transport for CLI/app parity.
- Optionally route MCP traffic through a faithful MCP-native proxy in a later phase.
