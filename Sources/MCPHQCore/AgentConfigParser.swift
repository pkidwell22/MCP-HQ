import Foundation

public struct AgentConfigParser: Sendable {
    public init() {}

    public func supports(_ agent: AgentID) -> Bool {
        switch agent {
        case .unknown:
            return false
        case .antigravity, .claude, .codex, .gemini, .hermes, .opencode, .pi, .cursor, .windsurf, .continue, .goose:
            return true
        }
    }

    public func parse(data: Data, source: ConfigSource) throws -> [ServerDefinition] {
        switch source.agent {
        case .claude:
            return try ClaudeConfigParser().parse(data: data, sourcePath: source.path)
        case .gemini:
            return try GeminiConfigParser().parse(data: data, sourcePath: source.path)
        case .hermes:
            return try HermesConfigParser().parse(data: data, sourcePath: source.path)
        case .antigravity:
            return try JSONMCPConfigParser(agent: .antigravity, containers: ["mcpServers"], remoteURLKeys: ["serverUrl", "url", "httpUrl"]).parse(data: data, sourcePath: source.path)
        case .pi:
            return try JSONMCPConfigParser(agent: .pi, containers: ["mcpServers", "mcp_servers", "servers"]).parse(data: data, sourcePath: source.path)
        case .cursor:
            return try JSONMCPConfigParser(agent: .cursor, containers: ["mcpServers", "mcp_servers"]).parse(data: data, sourcePath: source.path)
        case .windsurf:
            return try JSONMCPConfigParser(agent: .windsurf, containers: ["mcpServers", "mcp_servers"]).parse(data: data, sourcePath: source.path)
        case .continue:
            return try JSONMCPConfigParser(agent: .continue, containers: ["mcpServers", "mcp_servers", "servers"]).parse(data: data, sourcePath: source.path)
        case .goose:
            return try YAMLMCPConfigParser(agent: .goose).parse(data: data, sourcePath: source.path)
        case .codex:
            return try CodexTOMLMCPConfigParser().parse(data: data, sourcePath: source.path)
        case .opencode:
            return try OpenCodeConfigParser().parse(data: data, sourcePath: source.path)
        case .unknown:
            return []
        }
    }
}

public struct JSONMCPConfigParser: Sendable {
    private let agent: AgentID
    private let containers: [String]
    private let remoteURLKeys: [String]

    public init(agent: AgentID, containers: [String], remoteURLKeys: [String] = ["url", "httpUrl", "serverUrl"]) {
        self.agent = agent
        self.containers = containers
        self.remoteURLKeys = remoteURLKeys
    }

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        guard !data.isEmpty else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        for key in containers {
            if let servers = object[key] as? [String: Any] {
                return parseServers(servers, sourcePath: sourcePath)
            }
        }
        return []
    }

    fileprivate func parseServers(_ servers: [String: Any], sourcePath: String) -> [ServerDefinition] {
        servers.keys.sorted().compactMap { name in
            guard let server = servers[name] as? [String: Any], isEnabled(server) else { return nil }

            let env = stringMap(server["env"]) ?? stringMap(server["environment"]) ?? [:]
            let headers = stringMap(server["headers"]) ?? [:]
            if let commandParts = commandParts(from: server["command"]), !commandParts.isEmpty {
                return ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: agent, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: .stdio,
                    command: commandParts[0],
                    args: Array(commandParts.dropFirst()) + stringArray(server["args"]),
                    headers: headers,
                    envBindings: env,
                    sourcePath: sourcePath
                )
            }

            if let url = remoteURL(in: server) {
                return ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: agent, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: transport(in: server, remoteURLKey: url.key),
                    url: url.value,
                    headers: headers,
                    envBindings: env,
                    sourcePath: sourcePath
                )
            }
            return nil
        }
    }

    fileprivate func isEnabled(_ server: [String: Any]) -> Bool {
        if server["disabled"] as? Bool == true { return false }
        if server["enabled"] as? Bool == false { return false }
        return true
    }

    fileprivate func commandParts(from value: Any?) -> [String]? {
        if let command = value as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [command]
        }
        if let command = value as? [String] {
            return command.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let command = value as? [Any] {
            return command.compactMap { $0 as? String }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return nil
    }

    fileprivate func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    fileprivate func stringMap(_ value: Any?) -> [String: String]? {
        guard let raw = value as? [String: Any] else { return nil }
        return raw.reduce(into: [:]) { result, pair in
            if let value = pair.value as? String {
                result[pair.key] = value
            }
        }
    }

    fileprivate func remoteURL(in server: [String: Any]) -> (key: String, value: String)? {
        for key in remoteURLKeys {
            if let value = server[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (key, value)
            }
        }
        return nil
    }

    fileprivate func transport(in server: [String: Any], remoteURLKey: String) -> MCPTransport {
        if let value = server["transport"] as? String ?? server["type"] as? String {
            if value == "remote" { return .streamableHTTP }
            return MCPTransport(configValue: value)
        }
        return remoteURLKey == "serverUrl" ? .streamableHTTP : .http
    }
}

public struct OpenCodeConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        guard !data.isEmpty else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcp = object["mcp"] as? [String: Any] else { return [] }

        return mcp.keys.sorted().compactMap { name in
            guard let server = mcp[name] as? [String: Any] else { return nil }
            if server["enabled"] as? Bool == false || server["disabled"] as? Bool == true { return nil }
            let env = stringMap(server["environment"]) ?? stringMap(server["env"]) ?? [:]
            let headers = stringMap(server["headers"]) ?? [:]
            if (server["type"] as? String)?.lowercased() == "remote",
               let url = server["url"] as? String {
                return ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .opencode, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: .streamableHTTP,
                    url: url,
                    headers: headers,
                    envBindings: env,
                    sourcePath: sourcePath
                )
            }
            let command = commandParts(from: server["command"]) ?? []
            guard !command.isEmpty else { return nil }
            return ServerDefinition(
                id: ServerDefinition.canonicalID(agent: .opencode, sourcePath: sourcePath, name: name),
                displayName: name,
                transport: .stdio,
                command: command[0],
                args: Array(command.dropFirst()),
                headers: headers,
                envBindings: env,
                sourcePath: sourcePath
            )
        }
    }

    private func commandParts(from value: Any?) -> [String]? {
        JSONMCPConfigParser(agent: .opencode, containers: []).commandParts(from: value)
    }

    private func stringMap(_ value: Any?) -> [String: String]? {
        JSONMCPConfigParser(agent: .opencode, containers: []).stringMap(value)
    }
}

public struct CodexTOMLMCPConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var builders: [String: TOMLServerBuilder] = [:]
        var currentName: String?
        var currentSubtable: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast())
                let parts = section.split(separator: ".").map(String.init)
                guard parts.count >= 2, parts[0] == "mcp_servers" else {
                    currentName = nil
                    currentSubtable = nil
                    continue
                }
                currentName = parseString(parts[1])
                currentSubtable = parts.count > 2 ? parts[2] : nil
                if builders[currentName!] == nil {
                    builders[currentName!] = TOMLServerBuilder()
                }
                continue
            }
            guard let currentName, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            var builder = builders[currentName, default: TOMLServerBuilder()]
            switch currentSubtable {
            case "env":
                builder.env[key] = parseString(value)
            case "headers":
                builder.headers[key] = parseString(value)
            default:
                builder.set(key: key, value: value)
            }
            builders[currentName] = builder
        }

        return builders.keys.sorted().compactMap { name in
            builders[name]?.server(name: name, sourcePath: sourcePath)
        }
    }

    fileprivate func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character?
        for (index, character) in line.enumerated() {
            if character == "'", !inDouble { inSingle.toggle() }
            if character == "\"", !inSingle, previous != "\\" { inDouble.toggle() }
            if character == "#", !inSingle, !inDouble {
                return String(line.prefix(index))
            }
            previous = character
        }
        return line
    }

    fileprivate func parseString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        let first = trimmed.first
        let last = trimmed.last
        if first == "\"" && last == "\"" || first == "'" && last == "'" {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    fileprivate func parseStringArray(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        var values: [String] = []
        var current = ""
        var inQuote: Character?
        var previous: Character?
        for character in inner {
            if let quote = inQuote {
                if character == quote, previous != "\\" {
                    values.append(current)
                    current = ""
                    inQuote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                inQuote = character
            }
            previous = character
        }
        return values
    }

    fileprivate struct TOMLServerBuilder {
        var command: String?
        var args: [String] = []
        var url: String?
        var transport: MCPTransport?
        var enabled: Bool?
        var disabled: Bool?
        var env: [String: String] = [:]
        var headers: [String: String] = [:]

        mutating func set(key: String, value: String) {
            let parser = CodexTOMLMCPConfigParser()
            switch key {
            case "command":
                command = parser.parseString(value)
            case "args":
                args = parser.parseStringArray(value)
            case "url", "server_url", "serverUrl":
                url = parser.parseString(value)
            case "transport", "type":
                transport = MCPTransport(configValue: parser.parseString(value))
            case "enabled":
                enabled = value.lowercased().contains("true")
            case "disabled":
                disabled = value.lowercased().contains("true")
            default:
                break
            }
        }

        func server(name: String, sourcePath: String) -> ServerDefinition? {
            if enabled == false || disabled == true { return nil }
            if let command, !command.isEmpty {
                return ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .codex, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: .stdio,
                    command: command,
                    args: args,
                    headers: headers,
                    envBindings: env,
                    sourcePath: sourcePath
                )
            }
            if let url, !url.isEmpty {
                return ServerDefinition(
                    id: ServerDefinition.canonicalID(agent: .codex, sourcePath: sourcePath, name: name),
                    displayName: name,
                    transport: transport ?? .streamableHTTP,
                    url: url,
                    headers: headers,
                    envBindings: env,
                    sourcePath: sourcePath
                )
            }
            return nil
        }
    }
}

public struct YAMLMCPConfigParser: Sendable {
    private let agent: AgentID

    public init(agent: AgentID) {
        self.agent = agent
    }

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        guard let mcpBlock = YAMLMCPSubset.block(named: "mcp_servers", in: text) ?? YAMLMCPSubset.block(named: "mcpServers", in: text) else { return [] }

        return YAMLMCPSubset.childBlocks(in: mcpBlock.lines, parentIndent: mcpBlock.indent)
            .sorted(by: { $0.name < $1.name })
            .compactMap { block in
                let fields = YAMLMCPSubset.fields(in: block.lines, parentIndent: block.indent)
                if fields.scalarValue(for: "enabled")?.lowercased() == "false" { return nil }
                if fields.scalarValue(for: "disabled")?.lowercased() == "true" { return nil }
                let env = fields.mapValue(for: "env")
                let headers = fields.mapValue(for: "headers")
                if let command = fields.scalarValue(for: "command"), !command.isEmpty {
                    return ServerDefinition(
                        id: ServerDefinition.canonicalID(agent: agent, sourcePath: sourcePath, name: block.name),
                        displayName: block.name,
                        transport: .stdio,
                        command: command,
                        args: fields.listValue(for: "args"),
                        headers: headers,
                        envBindings: env,
                        sourcePath: sourcePath
                    )
                }
                if let url = fields.scalarValue(for: "url") ?? fields.scalarValue(for: "serverUrl"), !url.isEmpty {
                    return ServerDefinition(
                        id: ServerDefinition.canonicalID(agent: agent, sourcePath: sourcePath, name: block.name),
                        displayName: block.name,
                        transport: MCPTransport(configValue: fields.scalarValue(for: "transport") ?? fields.scalarValue(for: "type")),
                        url: url,
                        headers: headers,
                        envBindings: env,
                        sourcePath: sourcePath
                    )
                }
                return nil
            }
    }
}

private enum YAMLMCPSubset {
    struct Line: Equatable {
        let indent: Int
        let text: String
    }

    struct NamedBlock: Equatable {
        let name: String
        let indent: Int
        let lines: [Line]
    }

    struct RootBlock: Equatable {
        let indent: Int
        let lines: [Line]
    }

    struct ParsedFields: Equatable {
        let scalars: [String: String]
        let lists: [String: [String]]
        let maps: [String: [String: String]]

        func scalarValue(for key: String) -> String? { scalars[key] }
        func listValue(for key: String) -> [String] { lists[key] ?? [] }
        func mapValue(for key: String) -> [String: String] { maps[key] ?? [:] }
    }

    static func block(named blockName: String, in text: String) -> RootBlock? {
        let lines = parseLines(text)
        guard let startIndex = lines.firstIndex(where: { $0.text == "\(blockName):" }) else { return nil }
        let start = lines[startIndex]
        var blockLines: [Line] = []
        for line in lines.dropFirst(startIndex + 1) {
            if line.indent <= start.indent { break }
            blockLines.append(line)
        }
        return RootBlock(indent: start.indent, lines: blockLines)
    }

    static func childBlocks(in lines: [Line], parentIndent: Int) -> [NamedBlock] {
        let childIndent = parentIndent + 2
        let headerIndexes = lines.indices.filter {
            lines[$0].indent == childIndent && lines[$0].text.hasSuffix(":") && !lines[$0].text.hasPrefix("-")
        }
        return headerIndexes.enumerated().compactMap { offset, index in
            let header = lines[index]
            let name = String(header.text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let next = offset + 1 < headerIndexes.count ? headerIndexes[offset + 1] : lines.endIndex
            return NamedBlock(name: unquote(name), indent: header.indent, lines: Array(lines[(index + 1)..<next]))
        }
    }

    static func fields(in lines: [Line], parentIndent: Int) -> ParsedFields {
        let fieldIndent = parentIndent + 2
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var maps: [String: [String: String]] = [:]
        var index = lines.startIndex
        while index < lines.endIndex {
            let line = lines[index]
            guard line.indent == fieldIndent, let (key, value) = keyValue(from: line.text) else {
                index += 1
                continue
            }
            if !value.isEmpty {
                scalars[key] = unquote(value)
                index += 1
                continue
            }
            let nestedStart = index + 1
            var nestedEnd = nestedStart
            while nestedEnd < lines.endIndex, lines[nestedEnd].indent > fieldIndent {
                nestedEnd += 1
            }
            let nestedLines = Array(lines[nestedStart..<nestedEnd])
            if nestedLines.contains(where: { $0.text.hasPrefix("-") }) {
                lists[key] = nestedLines.compactMap {
                    guard $0.text.hasPrefix("-") else { return nil }
                    return unquote(String($0.text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                maps[key] = nestedLines.reduce(into: [:]) { result, nested in
                    guard let (nestedKey, nestedValue) = keyValue(from: nested.text), !nestedValue.isEmpty else { return }
                    result[nestedKey] = unquote(nestedValue)
                }
            }
            index = nestedEnd
        }
        return ParsedFields(scalars: scalars, lists: lists, maps: maps)
    }

    private static func parseLines(_ text: String) -> [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let withoutComment = stripComment(String(raw))
            guard !withoutComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Line(
                indent: withoutComment.prefix { $0 == " " }.count,
                text: withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func keyValue(from text: String) -> (String, String)? {
        guard let separator = text.firstIndex(of: ":") else { return nil }
        let key = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (unquote(key), value)
    }

    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character?
        for (index, character) in line.enumerated() {
            if character == "'", !inDouble { inSingle.toggle() }
            if character == "\"", !inSingle, previous != "\\" { inDouble.toggle() }
            if character == "#", !inSingle, !inDouble {
                return String(line.prefix(index))
            }
            previous = character
        }
        return line
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "\"" && last == "\"" || first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
