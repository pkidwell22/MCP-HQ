import Foundation

public enum GeminiConfigParserError: Error, Equatable, LocalizedError, Sendable {
    case missingTransportTarget(serverName: String)

    public var errorDescription: String? {
        switch self {
        case .missingTransportTarget(let serverName):
            return "Gemini MCP server '\(serverName)' must define either command or url."
        }
    }
}

public struct GeminiConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        let config = try JSONDecoder().decode(GeminiMCPConfig.self, from: data)
        var servers: [ServerDefinition] = []

        for name in config.servers.keys.sorted() {
            guard let server = config.servers[name] else { continue }
            if server.disabled == true || server.enabled == false { continue }

            if let command = server.command, !command.isEmpty {
                servers.append(ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .gemini, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: .stdio,
                    command: command,
                    args: server.args ?? [],
                    envBindings: server.env ?? [:],
                    sourcePath: sourcePath
                ))
                continue
            }

            if let url = server.remoteURL, !url.isEmpty {
                servers.append(ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .gemini, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: MCPTransport(configValue: server.transport ?? server.type),
                    args: [],
                    url: url,
                    headers: server.headers ?? [:],
                    envBindings: server.env ?? [:],
                    sourcePath: sourcePath
                ))
                continue
            }

            throw GeminiConfigParserError.missingTransportTarget(serverName: name)
        }

        return servers
    }
}

private struct GeminiMCPConfig: Decodable {
    let servers: [String: GeminiMCPServer]

    private enum CodingKeys: String, CodingKey {
        case mcpServers
        case mcp_servers
        case servers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let mcpServers = try container.decodeIfPresent([String: GeminiMCPServer].self, forKey: .mcpServers) {
            self.servers = mcpServers
        } else if let snakeCase = try container.decodeIfPresent([String: GeminiMCPServer].self, forKey: .mcp_servers) {
            self.servers = snakeCase
        } else {
            self.servers = try container.decodeIfPresent([String: GeminiMCPServer].self, forKey: .servers) ?? [:]
        }
    }
}

private struct GeminiMCPServer: Decodable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let headers: [String: String]?
    let url: String?
    let httpUrl: String?
    let serverUrl: String?
    let transport: String?
    let type: String?
    let enabled: Bool?
    let disabled: Bool?

    var remoteURL: String? {
        url ?? httpUrl ?? serverUrl
    }

}
