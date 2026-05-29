import Foundation

public struct ClaudeConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        let config = try JSONDecoder().decode(ClaudeMCPConfig.self, from: data)
        return config.mcpServers
            .keys
            .sorted()
            .compactMap { name in
                guard let server = config.mcpServers[name] else { return nil }
                if let command = server.command {
                    return ServerDefinition(
                        id: name,
                        displayName: name,
                        transport: .stdio,
                        command: command,
                        args: server.args ?? [],
                        envBindings: server.env ?? [:],
                        sourcePath: sourcePath
                    )
                }
                if let url = server.url {
                    return ServerDefinition(
                        id: name,
                        displayName: name,
                        transport: .http,
                        args: [],
                        url: url,
                        envBindings: server.env ?? [:],
                        sourcePath: sourcePath
                    )
                }
                return ServerDefinition(
                    id: name,
                    displayName: name,
                    transport: .stdio,
                    args: server.args ?? [],
                    envBindings: server.env ?? [:],
                    sourcePath: sourcePath
                )
            }
    }
}

private struct ClaudeMCPConfig: Decodable {
    let mcpServers: [String: ClaudeMCPServer]
}

private struct ClaudeMCPServer: Decodable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
}
