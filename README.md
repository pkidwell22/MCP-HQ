# MCP-HQ

MCP-HQ is a proposed native macOS control center for local Model Context Protocol servers.

The product direction is: see, fix, configure, and eventually broker every MCP server on a Mac from one place.

This repo contains architecture/product planning documents plus a Swift package for the app, CLI, and core library. The first usable CLI command is `mcphq scan`, which safely inventories Claude, Gemini, and Hermes MCP config sources, detects running MCP-like processes, and redacts sensitive values in text and JSON output. The SwiftUI app now launches into a read-only inventory dashboard backed by the same scanner.

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
```

`scan` skips missing default config paths, reports malformed or unsupported existing configs as issues, detects running MCP-like processes via macOS `ps`, and uses redacted env bindings/process command lines for both terminal and JSON output. Gemini support reads JSON `mcpServers`, `mcp_servers`, or `servers` containers, including stdio servers (`command`, `args`, `env`) and remote servers (`url`, `httpUrl`, or `serverUrl`). Hermes support reads the `mcp_servers` block from `~/.hermes/config.yaml`, including stdio servers (`command`, `args`, `env`) and remote servers (`url`).

## App

Launch the read-only dashboard:

```bash
swift run MCPHQApp
```

The dashboard shows server/process/source/issue counts, inventory rows, running MCP-like process rows, warning/error details, and redacted environment variables. Use `⌘R` or the Refresh button to rescan known macOS config locations and running processes.

## Core architectural principle

Use HTTP/Unix socket APIs for the control plane.

Keep MCP traffic as MCP for the data plane.

In other words, do not replace MCP with a custom REST abstraction. If MCP-HQ proxies tool calls, it should expose a real MCP server/router endpoint and preserve MCP semantics.
