# MCP-HQ Bulk Connect All Parity Report

## Current state

Bulk **Connect All** already exists in core/app, but not CLI/local-control:

- Core bulk authoring: `Sources/MCPHQCore/AgentConfigAuthoring.swift`
  - `AgentBulkConfigAuthoringPlanner.previewConnectAll(...)`
  - `AgentBulkConfigAuthoringPlanner.applyConnectAll(...)`
- App UI flow: `Sources/MCPHQApp/MCPHQApp.swift`
  - `bulkConnectDraftPreview(...)`
  - `applyBulkConnectDraft(...)`
  - private template/target selection helpers
- Tests already cover planner behavior:
  - `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
- Missing parity:
  - no `LocalControlRoute` for bulk connect-all
  - no local-control response models for multi-target previews/applies
  - no CLI command for bulk connect-all
  - app selection logic is private in the app, so CLI/local-control would risk diverging if copied

## Cleanest implementation path

### 1. Move Connect All selection into core

Add a small core coordinator/selector instead of duplicating app logic.

**New file**

- `Sources/MCPHQCore/BulkConnectAllCoordinator.swift`

**Responsibilities**

- Choose template source:
  - largest parsed source by server count
  - tie-break Hermes first
  - then agent display name
  - then path
- Choose default targets:
  - safe-authorable sources only
  - exclude template source
  - exclude `.unknown`
  - one preferred config per agent by `AgentRegistry.configPaths`
- Support explicit target sources for CLI/API.
- Call `AgentBulkConfigAuthoringPlanner`.

**Why**

This makes app, CLI, and local-control use the same rules.

### 2. Extend local-control API

**Edit**

- `Sources/MCPHQCore/LocalControlAPI.swift`

**Add routes**

```swift
case configConnectAllPreview = "config_connect_all_preview"
case configConnectAllApply = "config_connect_all_apply"
```

**Extend `LocalControlRequest`**

```swift
public let templateSource: ConfigSource?
public let targetSources: [ConfigSource]?
public let includeAllAuthorableTargets: Bool
```

Defaults:

- `templateSource: nil` means auto-select primary template from scan.
- `targetSources: nil` means use default target selection.
- `includeAllAuthorableTargets: true` means use all eligible target paths, not one per agent.
- `dryRun` continues to apply only to apply routes.

**Add response models**

```swift
public struct LocalControlConnectAllTargetPreview: Codable, Equatable, Sendable {
    public let source: ConfigSource
    public let agentName: String
    public let bindingCount: Int
    public let serverCount: Int
    public let wouldChange: Bool
    public let renderedText: String
    public let diffText: String
    public let reparsedServerCount: Int
}

public struct LocalControlConnectAllPreview: Codable, Equatable, Sendable {
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let targetPreviews: [LocalControlConnectAllTargetPreview]
    public let changedTargetCount: Int
    public let summaryText: String
}

public struct LocalControlConnectAllApplyTarget: Codable, Equatable, Sendable {
    public let source: ConfigSource
    public let agentName: String
    public let bindingCount: Int
    public let serverCount: Int
    public let backupPath: String?
}

public struct LocalControlConnectAllApply: Codable, Equatable, Sendable {
    public let dryRun: Bool
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let appliedTargets: [LocalControlConnectAllApplyTarget]
    public let preview: LocalControlConnectAllPreview?
    public let summaryText: String
}
```

**Extend `LocalControlResponse`**

```swift
public let connectAllPreview: LocalControlConnectAllPreview?
public let connectAllApply: LocalControlConnectAllApply?
```

**Important implementation detail**

Bulk routes must use the raw scanned `ServerDefinition`s for planning/writing, then redact only the response. Do not feed already-redacted scan output into config rendering, or secrets may be written as `<redacted>` instead of safe env/keychain-style references.

### 3. Add control-plane store injection to router

**Edit**

- `Sources/MCPHQCore/LocalControlAPI.swift`
- `Sources/MCPHQCore/MCPHQCommand.swift`

`AgentBulkConfigAuthoringPlanner` can record desired states/backups, but `LocalControlRouter` currently has no `SQLiteScanHistoryStore`.

Add optional router init dependency:

```swift
private let controlPlaneStore: SQLiteScanHistoryStore?
```

Then bulk apply route can use:

```swift
AgentBulkConfigAuthoringPlanner(controlPlaneStore: controlPlaneStore)
```

CLI direct-core local-control should pass existing `scanHistoryStore`.

### 4. Add CLI command

**Edit**

- `Sources/MCPHQCore/MCPHQCommand.swift`

Recommended syntax:

```bash
mcphq config connect-all preview \
  [--template-source agent:/path] \
  [--target-source agent:/path ...] \
  [--all-targets] \
  [--json] \
  [--endpoint-file path]

mcphq config connect-all apply \
  [--template-source agent:/path] \
  [--target-source agent:/path ...] \
  [--all-targets] \
  [--dry-run] \
  [--json] \
  [--endpoint-file path]
```

Behavior:

- `preview`: never writes.
- `apply --dry-run`: returns apply-shaped dry-run response with preview details, writes nothing.
- `apply` without `--dry-run`: writes changed targets, creates backups, records desired-state breadcrumbs.
- With `--endpoint-file`: use HTTP helper.
- Without `--endpoint-file`: still dispatch through `LocalControlClientStateHelper` / in-process `LocalControlRouter` for parity.

Avoid overloading existing `--source` / `--server-source`; use clearer bulk-specific names.

### 5. Update app to use shared selector

**Edit**

- `Sources/MCPHQApp/MCPHQApp.swift`

Replace app-private selection logic with the new core coordinator where practical:

- `primaryBulkTemplateSelection()`
- `defaultBulkTargetSources(...)`
- `selectedBulkTargetSources(...)`

This is not strictly required for CLI/local-control functionality, but it is the cleanest way to guarantee ongoing parity.

### 6. Docs

**Edit**

- `README.md`
- possibly `docs/pi-team/wave5-cli-bulk-connect-result.md`

Document command examples and safety behavior.

## Test plan

### Core selection/coordinator tests

**File**

- `Tests/MCPHQCoreTests/AgentConfigAuthoringTests.swift`
  - or new `Tests/MCPHQCoreTests/BulkConnectAllCoordinatorTests.swift`

Add tests:

1. Auto-selects largest parsed template source.
2. Tie-breaks Hermes before other agents.
3. Default targets exclude template, unknown, and unsupported/manual sources.
4. Default targets pick one preferred path per agent.
5. Explicit target sources are honored.
6. `--all-targets` equivalent includes every safe-authorable target path.

### Local-control API tests

**File**

- `Tests/MCPHQCoreTests/LocalControlAPITests.swift`

Add tests:

1. `config_connect_all_preview` returns multi-target redacted previews and writes nothing.
2. `config_connect_all_apply` with `dryRun: true` writes nothing.
3. `config_connect_all_apply` with `dryRun: false` writes changed target configs, creates backups, records desired-state rows.
4. Missing template / no targets returns redacted `error`.
5. Response never exposes literal token values in `renderedText`, `diffText`, `backupPath`, or `error`.

### Transport tests

**File**

- `Tests/MCPHQCoreTests/LocalControlTransportTests.swift`

Add a round-trip test proving request/response envelopes encode/decode new bulk fields.

### CLI tests

**File**

- `Tests/MCPHQCoreTests/MCPHQCommandTests.swift`

Add tests:

1. Direct CLI preview:

```bash
mcphq config connect-all preview --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json
```

2. Endpoint-backed preview returns same redacted output.
3. `apply --dry-run` writes nothing.
4. Real `apply` writes all changed targets and reports backups.
5. `--json` shape is stable and redacted.
6. Invalid option combinations return exit code `2`.

## Main risks

- **Selection drift:** avoid copying app-private target/template rules into CLI/local-control; centralize them in core.
- **Secret safety:** response redaction must cover rendered configs, diffs, errors, and backup paths.
- **Writing redacted secrets:** route internals must plan from raw scanned servers, not redacted response models.
- **Partial writes:** use existing bulk snapshot rollback; add tests around multi-target failure.
- **Concurrent writers:** app and CLI can race writing same config. File locking is not present today.
- **Large responses:** multi-target rendered config output can be big; CLI text should prefer summaries/diffs, JSON can include full redacted previews.
- **Endpoint authority:** authenticated local helper can write arbitrary passed config paths. This matches current config apply behavior, but keep token enforcement and localhost-only assumptions intact.
