import Foundation

public enum ClaudeConfigParserError: Error, Equatable, LocalizedError, Sendable {
    case missingTransportTarget(serverName: String)

    public var errorDescription: String? {
        switch self {
        case .missingTransportTarget(let serverName):
            return "Claude MCP server '\(serverName)' must define either command or url."
        }
    }
}

public struct ClaudeConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        let config = try JSONDecoder().decode(ClaudeMCPConfig.self, from: data)
        var servers: [ServerDefinition] = []

        for name in config.mcpServers.keys.sorted() {
            guard let server = config.mcpServers[name] else { continue }
            if let command = server.command, !command.isEmpty {
                servers.append(ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .claude, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: .stdio,
                    command: command,
                    args: server.args ?? [],
                    envBindings: server.env ?? [:],
                    sourcePath: sourcePath
                ))
                continue
            }
            if let url = server.url, !url.isEmpty {
                servers.append(ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .claude, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: MCPTransport(configValue: server.transport ?? server.type),
                    args: [],
                    url: url,
                    envBindings: server.env ?? [:],
                    sourcePath: sourcePath
                ))
                continue
            }
            throw ClaudeConfigParserError.missingTransportTarget(serverName: name)
        }

        return servers
    }
}

private struct ClaudeMCPConfig: Decodable {
    let mcpServers: [String: ClaudeMCPServer]

    private enum CodingKeys: String, CodingKey {
        case mcpServers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mcpServers = try container.decodeIfPresent([String: ClaudeMCPServer].self, forKey: .mcpServers) ?? [:]
    }
}

private struct ClaudeMCPServer: Decodable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
    let transport: String?
    let type: String?
}
