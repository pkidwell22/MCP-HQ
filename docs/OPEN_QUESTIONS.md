# MCP-HQ Open Questions

Last updated: 2026-05-28

## Distribution

1. Is TestFlight required for the first external beta, or is Developer ID notarized distribution acceptable?
2. Can a sandboxed Mac app read/write the needed config files after user consent without a bad UX?
3. Can the app install and manage a helper/login item under TestFlight constraints?
4. Will App Review tolerate a tool that launches arbitrary local MCP server commands?
5. Should there be two builds: full-power Developer ID and reduced App Store/TestFlight?

## MCP protocol

1. Is there a mature Swift MCP client/server library worth using?
2. If not, should the router/core be Rust?
3. Which advanced MCP features are required for v1 router support?
   - sampling
   - roots
   - progress
   - cancellation
   - resources
   - prompts
   - logging
4. How do Claude, Hermes, Gemini, and other agents behave with an aggregator MCP server?
5. What is the best namespacing scheme for aggregated tools?

## Config formats

1. What exact MCP config paths and shapes should v0 support?
2. How should MCP-HQ preserve unknown fields and comments?
3. Which agents support environment variable references versus requiring literal env values?
4. Which agents can consume generated configs from a separate include file?
5. How should config drift be detected and resolved?

## Secrets

1. Should generated configs ever contain plaintext secrets?
2. Can agents consume secrets indirectly, or only env vars?
3. Should MCP-HQ run hub-owned servers with secrets injected while agent-owned servers get literal env values?
4. How should secret sharing/export/import work, if at all?

## Process discovery

1. What process metadata is available without elevated permissions?
2. How reliable is command-line capture under sandboxing?
3. How should MCP-HQ distinguish MCP stdio servers from ordinary node/python/bun processes?
4. Can MCP-HQ map a running stdio process back to the agent that launched it?

## Product scope

1. Is the MVP a menu bar utility, a full dashboard app, or both?
2. Should the first product promise be visibility/doctor rather than management?
3. Should router/proxy be hidden behind an Advanced/Beta section?
4. Are profiles central to v1 or later?
5. Should this include a curated MCP catalog early?

## Naming

Current working names:

- MCP-HQ
- MCP Hub
- MCP Radar
- MCP Doctor
- MCP Desktop
- MCP Control Center

Positioning to test:

- Docker Desktop for MCP
- The Mac control center for MCP
- See and fix every MCP server on your Mac
