# MCP-HQ Config Manager “Connect All” Apply Safety Review

_No files modified._

## Executive summary

Connect All has a solid safe-apply foundation: preview-first UI, explicit confirmation, per-file generated-config reparse, timestamped backups for existing files, and rollback-on-failure via snapshots. The main safety gaps are **stale preview protection**, **post-success rollback UX**, and **proof of actual agent connectivity**. Today MCP-HQ can prove configs were written and MCP servers are probeable; it cannot strictly prove every coding agent has loaded those configs.

## What is already safe

- **Pre-apply preview exists**
  - `Preview Connect All` opens target selection, then a draft sheet with per-target diffs.
  - Apply is disabled when there are no changes.
  - UI requires a confirmation dialog: `Apply connect-all draft?`
  - Relevant paths:
    - `Sources/MCPHQApp/MCPHQApp.swift:826`
    - `Sources/MCPHQApp/MCPHQApp.swift:867`
    - `Sources/MCPHQApp/MCPHQApp.swift:3857`

- **Generated config is reparsed before/after write**
  - Preview reparses generated text and verifies server count.
  - Apply writes atomically, rereads the file, reparses it, and verifies count again.
  - Relevant paths:
    - `Sources/MCPHQCore/AgentConfigRenderer.swift:255`
    - `Sources/MCPHQCore/AgentConfigRenderer.swift:278`

- **Backups exist for existing files**
  - Existing configs get `*.mcphq-backup-YYYYMMDDHHMMSS`.
  - Missing config files are created without a backup, which is expected but important for rollback UX.
  - Relevant paths:
    - `Sources/MCPHQCore/AgentConfigRenderer.swift:617`

- **Bulk failure rollback exists**
  - Connect All snapshots each target before write.
  - If any target fails, previously touched files are restored from snapshots.
  - Relevant paths:
    - `Sources/MCPHQCore/AgentConfigAuthoring.swift:417`
    - `Sources/MCPHQCore/AgentConfigAuthoring.swift:454`
    - `Sources/MCPHQCore/AgentConfigAuthoring.swift:482`

- **Backup breadcrumbs are recorded**
  - Existing-file backups are stored in the SQLite control-plane history.
  - Relevant path:
    - `Sources/MCPHQCore/AgentConfigAuthoring.swift:459`

## Safety gaps / risks

### 1. Stale preview / stale scan risk

Connect All apply recomputes from `lastScanResult.servers`, not from a fresh disk scan at apply time. `AgentConfigSafeApplier` reads current text for merging, but the desired server list can still be stale. If a user or another tool edits MCP server config between preview and apply, Connect All can overwrite or drop those MCP server changes.

**Recommendation:** capture target file hash/mtime at preview time; before apply, recheck all targets. If any changed, abort and force a new preview.

### 2. No user-facing rollback after successful bulk apply

Core can rollback failures during apply, and single-config preview has rollback affordance. Connect All success returns backup paths, but there is no obvious bulk “Rollback Connect All” UI that restores all touched files or deletes newly created files.

**Recommendation:** persist a bulk apply transaction ID containing:
- target source path
- before snapshot hash
- backup path or “created file”
- applied template binding names
- timestamp

Then expose “Rollback Connect All transaction”.

### 3. Post-apply rescan is config-only by default

After Connect All apply, the app calls `refresh()`, but `NativeAppPreferences.defaultProbeOnRefresh = false`, so default post-apply verification does **not** run live MCP probes.

Relevant paths:
- `Sources/MCPHQApp/MCPHQApp.swift:895`
- `Sources/MCPHQApp/MCPHQApp.swift:123`
- `Sources/MCPHQCore/NativeAppPreferences.swift:15`

**Recommendation:** Connect All should force a post-apply `scan(includeProbes: true)` or offer a required “Verify now” step before declaring success.

### 4. “Connected” is not fully provable today

MCP-HQ can prove:
- config files were generated and reparsed;
- fresh scan sees expected server bindings;
- live probes can initialize/list tools for MCP servers.

It cannot prove:
- each coding agent process has loaded the updated config;
- each agent chose the expected config path when multiple paths exist;
- the agent UI/runtime has actually connected to each MCP server.

**Recommendation:** label current evidence as “configured and probeable,” not “agent connected,” unless agent-native readback is added.

## How to prove all coding agents are connected

Minimum evidence matrix after Connect All:

| Agent | Source path | Expected bindings present | Config parsed | Probe status | Agent loaded config |
|---|---|---:|---|---|---|
| Pi / Hermes / Codex / OpenCode / Cursor / Windsurf / Continue / Goose / Claude / Gemini / Antigravity | known path | yes | parsed | healthy | currently not directly provable |

Practical proof sequence:

1. Apply Connect All.
2. Immediately run a fresh scan with probes enabled.
3. For every selected target source:
   - source health is `parsed`;
   - every template binding appears under that source;
   - generated server count matches expected;
   - probe result is `healthy` where probing is supported.
4. For true “agent connected” proof, add agent-specific verification:
   - query the agent’s MCP registry/status if available;
   - or run a known harmless MCP tool through each agent and record success.

## Recommended next changes

1. Surface the fresh probe result matrix inside the native Connect All result sheet after its asynchronous post-apply probe scan completes.
2. Add persisted reusable bulk-connect target profiles for repeated setup.
3. Add agent-native verification where available before using “connected” language.
4. Improve probe progress/timeout feedback now that full post-Connect-All scans can still take several seconds even with duplicate target reuse.

## Mainline follow-up

Mainline now captures target file snapshots during Connect All preview, rejects stale targets at app apply time, reports a fresh parse/binding verification matrix, exposes a guarded rollback button for the successful bulk apply while the result sheet is open, persists rollback transactions for later CLI rollback by transaction ID, shows persisted rollback transactions in native Config Manager after the result sheet is closed, labels successful app applies as “configured,” starts a live probe scan after successful app applies independent of the global Refresh probe preference, reuses probe results for identical command/URL/env/header targets across repeated agent bindings, and lets CLI/local-control `config connect-all apply --probe` include live probe evidence in the post-apply verification report. On this machine, Connect All configured the selected known-agent targets on 2026-05-30 and a fresh scan saw all selected target configs parsed with expected bindings; remaining warnings are missing `GITHUB_PERSONAL_ACCESS_TOKEN` environment references in newly generated configs, and the shared `twozero_td` HTTP binding is not probeable until the TouchDesigner/Pisang endpoint is listening on `http://localhost:40404/mcp`. That still does not prove each external coding agent has reloaded its config.
