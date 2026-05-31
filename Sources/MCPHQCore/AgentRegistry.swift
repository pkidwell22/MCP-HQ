import Foundation

public enum AgentConfigFormat: String, Codable, Equatable, Sendable {
    case json
    case toml
    case yaml
}

public enum AgentCapabilityStatus: String, Codable, Equatable, Sendable {
    case supported
    case planned
    case unsupported
}

public struct AgentDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: AgentID { agent }
    public let agent: AgentID
    public let displayName: String
    public let configFormat: AgentConfigFormat
    public let configPaths: [String]
    public let parserStatus: AgentCapabilityStatus
    public let rendererStatus: AgentCapabilityStatus
    public let launchContextNotes: String

    public init(
        agent: AgentID,
        displayName: String,
        configFormat: AgentConfigFormat,
        configPaths: [String],
        parserStatus: AgentCapabilityStatus,
        rendererStatus: AgentCapabilityStatus,
        launchContextNotes: String
    ) {
        self.agent = agent
        self.displayName = displayName
        self.configFormat = configFormat
        self.configPaths = configPaths
        self.parserStatus = parserStatus
        self.rendererStatus = rendererStatus
        self.launchContextNotes = launchContextNotes
    }
}

public enum AgentConfigSourceReadinessKind: String, Codable, Equatable, Sendable {
    case ready
    case creatable
    case manualSetup
    case unsupported
}

public struct AgentConfigSourceReadiness: Codable, Equatable, Sendable {
    public let kind: AgentConfigSourceReadinessKind
    public let label: String
    public let detail: String
    public let canCreateWithBindingDraft: Bool

    public init(
        kind: AgentConfigSourceReadinessKind,
        label: String,
        detail: String,
        canCreateWithBindingDraft: Bool
    ) {
        self.kind = kind
        self.label = label
        self.detail = detail
        self.canCreateWithBindingDraft = canCreateWithBindingDraft
    }
}

public struct AgentRegistry: Sendable {
    public let agents: [AgentDefinition]

    public init(agents: [AgentDefinition]) {
        self.agents = agents
    }

    public func sources() -> [ConfigSource] {
        agents.flatMap { definition in
            definition.configPaths.map { ConfigSource(agent: definition.agent, path: $0) }
        }
    }

    public func definition(for agent: AgentID) -> AgentDefinition? {
        agents.first { $0.agent == agent }
    }

    public func readiness(for source: ConfigSource, fileExists: Bool) -> AgentConfigSourceReadiness {
        guard let definition = definition(for: source.agent) else {
            return AgentConfigSourceReadiness(
                kind: .unsupported,
                label: "Unsupported",
                detail: "MCP-HQ does not know how to author this agent's config yet.",
                canCreateWithBindingDraft: false
            )
        }

        guard definition.parserStatus == .supported, definition.rendererStatus == .supported else {
            return AgentConfigSourceReadiness(
                kind: .manualSetup,
                label: "Manual setup",
                detail: "MCP-HQ can list this source, but safe config authoring is not available for \(definition.displayName) yet.",
                canCreateWithBindingDraft: false
            )
        }

        if fileExists {
            return AgentConfigSourceReadiness(
                kind: .ready,
                label: "Ready",
                detail: "\(definition.displayName) config exists and can be previewed or updated with safe binding drafts.",
                canCreateWithBindingDraft: true
            )
        }

        return AgentConfigSourceReadiness(
            kind: .creatable,
            label: "Can create",
            detail: "MCP-HQ can create this \(definition.configFormat.rawValue.uppercased()) config when you apply a binding draft for \(definition.displayName).",
            canCreateWithBindingDraft: true
        )
    }

    public static func displayName(for agent: AgentID) -> String {
        `default`().definition(for: agent)?.displayName ?? agent.rawValue
    }

    public static func `default`(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> AgentRegistry {
        func path(_ relativePath: String) -> String {
            URL(fileURLWithPath: homeDirectory).appendingPathComponent(relativePath).path
        }

        return AgentRegistry(agents: [
            AgentDefinition(
                agent: .antigravity,
                displayName: "Antigravity",
                configFormat: .json,
                configPaths: [path(".gemini/antigravity/mcp_config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Antigravity manages MCP servers from its agent panel and stores custom servers in a Gemini-scoped JSON config."
            ),
            AgentDefinition(
                agent: .pi,
                displayName: "Pi",
                configFormat: .json,
                configPaths: [path(".config/mcp/mcp.json"), path(".pi/agent/mcp.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Pi can consume shared MCP files plus Pi-owned override files; project-local .mcp.json and .pi/mcp.json are handled later when project scanning exists."
            ),
            AgentDefinition(
                agent: .hermes,
                displayName: "Hermes",
                configFormat: .yaml,
                configPaths: [path(".hermes/config.yaml")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Hermes reads an mcp_servers YAML block and is one of this machine's active agents."
            ),
            AgentDefinition(
                agent: .codex,
                displayName: "Codex",
                configFormat: .toml,
                configPaths: [path(".codex/config.toml")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Codex stores MCP servers as TOML tables under [mcp_servers]."
            ),
            AgentDefinition(
                agent: .opencode,
                displayName: "OpenCode",
                configFormat: .json,
                configPaths: [path(".config/opencode/opencode.json"), path(".config/opencode/config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "OpenCode stores MCP definitions under a top-level mcp object when configured globally."
            ),
            AgentDefinition(
                agent: .cursor,
                displayName: "Cursor",
                configFormat: .json,
                configPaths: [path(".cursor/mcp.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Cursor uses a Claude-style mcpServers JSON file."
            ),
            AgentDefinition(
                agent: .windsurf,
                displayName: "Windsurf",
                configFormat: .json,
                configPaths: [path(".codeium/windsurf/mcp_config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Windsurf uses a JSON MCP config similar to other desktop coding agents."
            ),
            AgentDefinition(
                agent: .continue,
                displayName: "Continue",
                configFormat: .json,
                configPaths: [path(".continue/config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Continue config may include MCP server blocks alongside other assistant settings."
            ),
            AgentDefinition(
                agent: .goose,
                displayName: "Goose",
                configFormat: .yaml,
                configPaths: [path(".config/goose/config.yaml")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Goose YAML support covers mcp_servers-style blocks for read-only inventory and safe generated output."
            ),
            AgentDefinition(
                agent: .claude,
                displayName: "Claude",
                configFormat: .json,
                configPaths: [path("Library/Application Support/Claude/claude_desktop_config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Supported for compatibility, though this machine is not using Claude as a primary coding agent."
            ),
            AgentDefinition(
                agent: .gemini,
                displayName: "Gemini",
                configFormat: .json,
                configPaths: [path(".gemini/config/mcp_config.json")],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "Supported for compatibility and as Antigravity's config family."
            ),
        ])
    }
}
