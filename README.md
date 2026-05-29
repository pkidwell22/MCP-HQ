# MCP-HQ

MCP-HQ is a proposed native macOS control center for local Model Context Protocol servers.

The product direction is: see, fix, configure, and eventually broker every MCP server on a Mac from one place.

This repo currently contains architecture and product planning documents, not implementation code.

## Planning docs

- `docs/PRD.md` — product requirements, users, scope, features, acceptance criteria.
- `docs/TECH_STACK.md` — recommended stack, alternatives, packaging and TestFlight notes.
- `docs/ARCHITECTURE.md` — system architecture, components, data model, API boundaries.
- `docs/INFRASTRUCTURE_FLOW.md` — discovery, config generation, server lifecycle, proxy flow diagrams.
- `docs/ROADMAP.md` — phased build plan from read-only scanner to MCP router.
- `docs/OPEN_QUESTIONS.md` — technical, product, and distribution questions to answer early.

## Core architectural principle

Use HTTP/Unix socket APIs for the control plane.

Keep MCP traffic as MCP for the data plane.

In other words, do not replace MCP with a custom REST abstraction. If MCP-HQ proxies tool calls, it should expose a real MCP server/router endpoint and preserve MCP semantics.
