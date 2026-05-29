# MCP-HQ Infrastructure Flow

Last updated: 2026-05-28

## 1. Discovery flow

```mermaid
sequenceDiagram
    participant UI as MCP-HQ.app
    participant API as Local API
    participant Core as Helper/Core
    participant FS as Filesystem
    participant PS as Process Table
    participant DB as SQLite

    UI->>API: POST /api/v1/scan
    API->>Core: run scan
    Core->>FS: read known config files
    Core->>FS: parse JSON/YAML configs
    Core->>PS: inspect running processes
    Core->>Core: correlate configs to processes
    Core->>Core: classify transport and ownership
    Core->>DB: upsert server definitions and runtime instances
    Core-->>API: scan result summary
    API-->>UI: updated inventory
```

Inputs:

- known agent config paths
- process table
- known command/runtime patterns
- optional catalog metadata

Outputs:

- canonical server definitions
- config source records
- runtime instances
- initial doctor findings

## 2. Doctor flow

```mermaid
flowchart TD
    Start[Run Doctor] --> Parse[Validate config parse]
    Parse --> Cmd[Check command/url]
    Cmd --> Env[Check env and secret bindings]
    Env --> Launch{Safe to initialize?}
    Launch -- No --> Findings[Record findings]
    Launch -- Yes --> Init[Launch temp MCP session]
    Init --> ListTools[Call initialize + tools/list]
    ListTools --> Cap[Capture tools/resources/prompts]
    Cap --> Conflicts[Detect conflicts and policy issues]
    Conflicts --> Findings
    Findings --> Report[User-facing doctor report]
```

Safe initialize rules:

- do not run unknown destructive commands
- prefer servers already configured by user
- use short timeout
- use sanitized environment
- avoid calling actual tools during doctor MVP

## 3. Config generation flow

```mermaid
sequenceDiagram
    participant User
    participant UI as MCP-HQ.app
    participant API as Local API
    participant Core as Helper/Core
    participant KC as Keychain
    participant FS as Config Files

    User->>UI: enable server for agent
    UI->>API: GET config preview
    API->>Core: render target agent config
    Core->>KC: resolve secret presence metadata
    Core->>FS: read current config
    Core->>Core: compute merge + diff
    Core-->>UI: diff preview + warnings
    User->>UI: approve write
    UI->>API: POST write-config
    API->>Core: write config transaction
    Core->>FS: backup existing config
    Core->>FS: write generated config
    Core->>FS: verify parse
    Core-->>UI: success + rollback id
```

Hard requirements:

- backup before write
- parse verification after write
- rollback id returned
- preserve unknown config where possible
- never silently drop user-managed entries

## 4. Hub-owned server lifecycle flow

```mermaid
stateDiagram-v2
    [*] --> Stopped
    Stopped --> Starting: user/startup/API start
    Starting --> Healthy: initialize + ping/list succeeds
    Starting --> Error: launch or initialize fails
    Healthy --> Degraded: ping/list fails
    Degraded --> Healthy: recovery succeeds
    Degraded --> Restarting: policy auto-restart
    Restarting --> Healthy: restart succeeds
    Restarting --> Error: restart fails
    Healthy --> Stopping: user/API stop
    Error --> Stopped: user stop
    Stopping --> Stopped
```

For each hub-owned server, collect:

- stdout/stderr logs
- launch timestamp
- exit code
- restart count
- last health check
- CPU/memory

## 5. Direct-agent mode

This is the recommended early mode.

```mermaid
flowchart LR
    App[MCP-HQ] --> Gen[Generate Agent Config]
    Gen --> Claude[Claude Config]
    Gen --> Hermes[Hermes Config]
    Gen --> Gemini[Gemini Config]

    Claude --> S1[MCP Server]
    Hermes --> S2[MCP Server]
    Gemini --> S3[MCP Server]

    App -. observes .-> S1
    App -. observes .-> S2
    App -. observes .-> S3
```

Benefits:

- no MCP functionality loss
- agents retain native behavior
- app still provides visibility and config sanity

Tradeoff:

- no runtime policy enforcement unless configs are regenerated

## 6. MCP router mode

Later optional mode.

```mermaid
flowchart TB
    Agent[Agent MCP Client] --> Router[MCP-HQ Router
MCP Server Endpoint]
    Router --> Policy[Policy Engine]
    Policy --> NS[Tool Namespace Mapper]
    NS --> GH[github MCP Server]
    NS --> QMD[qmd MCP Server]
    NS --> FS[filesystem MCP Server]

    Router --> Audit[(Audit Log)]
```

The router exposes merged capabilities:

- `github__list_issues`
- `github__create_pull_request`
- `qmd__query`
- `filesystem__read_file`

It must preserve:

- request ids
- cancellation
- progress notifications
- error semantics
- resources/prompts
- roots where applicable
- sampling behavior or explicit unsupported errors

## 7. Permissions flow

```mermaid
flowchart TD
    Request[Agent calls tool] --> Identify[Identify agent/session]
    Identify --> Policy[Evaluate policy]
    Policy --> Allowed{Allowed?}
    Allowed -- No --> Deny[Return MCP error]
    Allowed -- Yes --> Approval{Needs approval?}
    Approval -- Yes --> Prompt[Prompt user]
    Prompt --> UserChoice{Approved?}
    UserChoice -- No --> Deny
    UserChoice -- Yes --> Forward[Forward to downstream server]
    Approval -- No --> Forward
    Forward --> Audit[Write audit event]
    Audit --> Response[Return response]
```

Policy dimensions:

- agent
- profile
- server
- tool
- resource URI
- filesystem root
- read/write classification
- destructive operation flag

## 8. Local development infrastructure

Suggested repo structure:

```text
MCP-HQ/
  README.md
  docs/
    PRD.md
    TECH_STACK.md
    ARCHITECTURE.md
    INFRASTRUCTURE_FLOW.md
    ROADMAP.md
    OPEN_QUESTIONS.md
  app/
    MCPHQApp/              # future SwiftUI app
  core/
    MCPHQCore/             # future helper/core package
  fixtures/
    configs/
      claude/
      gemini/
      hermes/
    mcp-servers/
  tests/
    config-parser-tests/
    doctor-tests/
    golden-generated-configs/
```

## 9. Observability

Local logs:

- helper log
- scan log
- per-server stdout/stderr logs
- config write audit log
- doctor run history

User-visible events:

- server became unhealthy
- config write succeeded/failed
- secret missing
- restart loop detected
- generated config drifted from registry

## 10. Failure recovery

Every mutating operation should be transactional where possible.

Config write transaction:

1. read current file
2. compute hash
3. write backup with timestamp and hash
4. write candidate file
5. parse candidate
6. if parse fails, restore backup
7. record audit event

Server launch recovery:

1. capture command/env snapshot with secrets redacted
2. stream logs
3. initialize with timeout
4. mark healthy or error
5. avoid infinite restart loops
