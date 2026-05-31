# Highest-Leverage Remaining Slice After Connect All

## Recommendation

**Build the first helper-backed hub-owned lifecycle control slice.**

Turn the existing runtime/control foundations into a visible app + CLI workflow for starting, stopping, restarting, persisting, and tailing **hub-owned MCP servers** through the local control helper.

## Evidence from review

Current repo already has strong foundations:

- `docs/FULL_VISION_AUDIT.md` says **Connect All** now exists in the Config Manager.
- `Sources/MCPHQCore/AgentConfigAuthoring.swift` includes `AgentBulkConfigAuthoringPlanner.previewConnectAll/applyConnectAll`.
- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift` covers bulk connect preview/apply and desired-state breadcrumbs.
- `Sources/MCPHQCore/RuntimeSupervisor.swift` can start/stop/restart tracked hub-owned stdio processes and capture logs.
- `Sources/MCPHQCore/LocalControlAPI.swift` already exposes `runtime_start`, `runtime_stop`, and `runtime_restart`.
- `Sources/MCPHQCore/LocalControlEndpoint.swift`, `LocalControlHTTPAdapter.swift`, and `LocalControlLaunchAgent.swift` provide the loopback helper + LaunchAgent path.
- But `Sources/MCPHQApp/MCPHQApp.swift` still presents **Lifecycle & Logs** as read-only, and `MCPHQCommand.swift` exposes only `mcphq runtime explain`, not start/stop/restart.

## Proposed implementation slice

### “Helper-backed runtime controls v1”

Deliver a narrow vertical path:

1. **Make the helper the authoritative runtime supervisor**
   - Ensure `control serve` uses a `HubRuntimeSupervisor` backed by `SQLiteScanHistoryStore.applicationSupport()`.
   - Persist runtime start/stop results consistently.

2. **Expose CLI runtime actions**
   - Add:
     - `mcphq runtime start ... --endpoint-file ...`
     - `mcphq runtime stop ... --endpoint-file ...`
     - `mcphq runtime restart ... --endpoint-file ...`
   - Keep destructive controls endpoint/helper-only to avoid accidental in-process orphaning.

3. **Wire native app lifecycle buttons**
   - In Lifecycle & Logs, show guarded Start / Stop / Restart only for hub-owned runtimes.
   - Agent-owned and unknown processes stay read-only.
   - Reuse existing confirmation-dialog pattern.

4. **Recover persisted runtime state**
   - Merge persisted `registry runtimes` rows with fresh process scans.
   - Mark stale missing PIDs as stopped/degraded instead of pretending they are controllable.

5. **Keep logs useful**
   - After helper start, surface known stdout/stderr log paths in the existing bounded redacted log viewer.

## Why this is highest leverage

This slice closes two major audit gaps at once:

- **Lifecycle, Ownership, and Logs**
- **Local Control API**

It also changes MCP-HQ from “scanner/config editor” into a true **control center**, using code that already exists but is not yet connected end-to-end.

## Not the next best slice

The next-best alternative is the **canonical config authoring model** beyond scanned rows. That is important, but Connect All already moved config management forward. Runtime/helper wiring is now the larger product unlock.
