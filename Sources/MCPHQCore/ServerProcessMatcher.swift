import Foundation

public enum ServerProcessMatchConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct ServerProcessMatch: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(serverID):\(processID)" }
    public let serverID: String
    public let processID: Int32
    public let confidence: ServerProcessMatchConfidence
    public let reason: String

    public init(serverID: String, processID: Int32, confidence: ServerProcessMatchConfidence, reason: String) {
        self.serverID = serverID
        self.processID = processID
        self.confidence = confidence
        self.reason = reason
    }
}

public struct ServerProcessMatcher: Sendable {
    private let genericRunners: Set<String> = [
        "node", "npx", "npm", "pnpm", "yarn", "bun", "uv", "uvx", "python", "python3", "ruby", "deno", "tsx"
    ]

    public init() {}

    public func matches(servers: [ServerDefinition], processes: [MCPProcessSnapshot]) -> [ServerProcessMatch] {
        servers.flatMap { server in
            processes.compactMap { process in
                match(server: server, process: process)
            }
        }
        .sorted { lhs, rhs in
            if lhs.serverID != rhs.serverID { return lhs.serverID < rhs.serverID }
            return lhs.processID < rhs.processID
        }
    }

    private func match(server: ServerDefinition, process: MCPProcessSnapshot) -> ServerProcessMatch? {
        if let url = normalized(server.url), !url.isEmpty {
            let normalizedCommandLine = normalizeProcessText(process.commandLine)
            if normalizedCommandLine.contains(url) {
                return ServerProcessMatch(serverID: server.id, processID: process.pid, confidence: .high, reason: "URL matched")
            }
        }

        guard server.transport == .stdio, let command = server.command, !command.isEmpty else {
            return nil
        }

        let commandName = executableName(from: command)
        let processCommandName = executableName(from: process.executableName)
        let processText = normalizeProcessText(process.commandLine)
        let commandMatches = commandMatches(commandName: commandName, processCommandName: processCommandName, processText: processText)
        let significantArgs = significantArguments(for: server)
        let significantArgMatches = significantArgs.contains(where: { processText.contains($0) })

        if commandMatches, significantArgMatches {
            return ServerProcessMatch(
                serverID: server.id,
                processID: process.pid,
                confidence: .high,
                reason: "command and MCP-specific argument matched"
            )
        }

        if significantArgMatches, serverIdentityMatches(server: server, commandName: commandName, processText: processText) {
            return ServerProcessMatch(
                serverID: server.id,
                processID: process.pid,
                confidence: .high,
                reason: "server identity and MCP-specific argument matched"
            )
        }

        guard commandMatches else { return nil }

        if !genericRunners.contains(commandName) {
            return ServerProcessMatch(
                serverID: server.id,
                processID: process.pid,
                confidence: .medium,
                reason: "command matched"
            )
        }

        return nil
    }

    private func commandMatches(commandName: String, processCommandName: String, processText: String) -> Bool {
        if processCommandName == commandName { return true }
        if processText.hasPrefix(commandName + " ") { return true }
        if processText.contains("/" + commandName + " ") { return true }
        if commandName == "npx", processCommandName == "npm", processText.hasPrefix("npm exec ") { return true }
        return false
    }

    private func serverIdentityMatches(server: ServerDefinition, commandName: String, processText: String) -> Bool {
        identityTokens(server: server, commandName: commandName).contains { token in
            processText.contains(token)
        }
    }

    private func identityTokens(server: ServerDefinition, commandName: String) -> [String] {
        [server.id, server.displayName, commandName]
            .map(normalizeProcessText)
            .filter { token in
                token.count > 2 && !genericRunners.contains(token)
            }
    }

    private func significantArguments(for server: ServerDefinition) -> [String] {
        let normalizedArgs = server.args
            .map(normalizeProcessText)
            .filter { !$0.isEmpty }

        let mcpSpecificArgs = normalizedArgs.filter { arg in
            arg.contains("mcp") || arg.contains("modelcontextprotocol")
        }
        if !mcpSpecificArgs.isEmpty { return mcpSpecificArgs }

        return normalizedArgs.filter { arg in
            !arg.hasPrefix("-") && arg.count > 2
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        return normalizeProcessText(value)
    }

    private func normalizeProcessText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func executableName(from command: String) -> String {
        let firstToken = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? command
        return URL(fileURLWithPath: firstToken).lastPathComponent.lowercased()
    }
}
