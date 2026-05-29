import Foundation

public enum HermesConfigParserError: Error, Equatable, LocalizedError, Sendable {
    case missingTransportTarget(serverName: String)

    public var errorDescription: String? {
        switch self {
        case .missingTransportTarget(let serverName):
            return "Hermes MCP server '\(serverName)' must define either command or url."
        }
    }
}

public struct HermesConfigParser: Sendable {
    public init() {}

    public func parse(data: Data, sourcePath: String) throws -> [ServerDefinition] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        guard let mcpBlock = YAMLSubset.block(named: "mcp_servers", in: text) else { return [] }

        var servers: [ServerDefinition] = []
        for serverBlock in YAMLSubset.childBlocks(in: mcpBlock.lines, parentIndent: mcpBlock.indent).sorted(by: { $0.name < $1.name }) {
            let fields = YAMLSubset.fields(in: serverBlock.lines, parentIndent: serverBlock.indent)
            if fields.scalarValue(for: "enabled")?.lowercased() == "false" { continue }

            let command = fields.scalarValue(for: "command")
            let url = fields.scalarValue(for: "url")
            let args = fields.listValue(for: "args")
            let envBindings = fields.mapValue(for: "env")

            if let command, !command.isEmpty {
                servers.append(ServerDefinition(
                    id: serverBlock.name,
                    displayName: serverBlock.name,
                    transport: .stdio,
                    command: command,
                    args: args,
                    envBindings: envBindings,
                    sourcePath: sourcePath
                ))
                continue
            }

            if let url, !url.isEmpty {
                servers.append(ServerDefinition(
                    id: serverBlock.name,
                    displayName: serverBlock.name,
                    transport: MCPTransport(configValue: fields.scalarValue(for: "transport") ?? fields.scalarValue(for: "type")),
                    url: url,
                    envBindings: envBindings,
                    sourcePath: sourcePath
                ))
                continue
            }

            throw HermesConfigParserError.missingTransportTarget(serverName: serverBlock.name)
        }

        return servers
    }
}

private enum YAMLSubset {
    struct Line: Equatable {
        let number: Int
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
        guard let startIndex = lines.firstIndex(where: { line in
            line.text == "\(blockName):"
        }) else { return nil }

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
        let headerIndexes = lines.indices.filter { index in
            let line = lines[index]
            return line.indent == childIndent && line.text.hasSuffix(":") && !line.text.hasPrefix("-")
        }

        return headerIndexes.enumerated().compactMap { offset, headerIndex in
            let header = lines[headerIndex]
            let name = String(header.text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let nextHeaderIndex = offset + 1 < headerIndexes.count ? headerIndexes[offset + 1] : lines.endIndex
            let childLines = Array(lines[(headerIndex + 1)..<nextHeaderIndex])
            return NamedBlock(name: unquote(name), indent: header.indent, lines: childLines)
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
            if key == "args" {
                while nestedEnd < lines.endIndex,
                      lines[nestedEnd].indent >= fieldIndent,
                      lines[nestedEnd].text.hasPrefix("-") {
                    nestedEnd += 1
                }
            } else if key == "env" {
                while nestedEnd < lines.endIndex,
                      lines[nestedEnd].indent >= fieldIndent,
                      isEnvContinuation(lines[nestedEnd].text) {
                    nestedEnd += 1
                }
            } else {
                while nestedEnd < lines.endIndex, lines[nestedEnd].indent > fieldIndent {
                    nestedEnd += 1
                }
            }
            let nestedLines = Array(lines[nestedStart..<nestedEnd])
            if nestedLines.contains(where: { $0.text.hasPrefix("-") }) {
                lists[key] = nestedLines.compactMap { line in
                    guard line.text.hasPrefix("-") else { return nil }
                    return unquote(String(line.text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                var nestedMap: [String: String] = [:]
                for nested in nestedLines {
                    guard let (nestedKey, nestedValue) = keyValue(from: nested.text), !nestedValue.isEmpty else { continue }
                    nestedMap[nestedKey] = unquote(nestedValue)
                }
                maps[key] = nestedMap
            }
            index = nestedEnd
        }

        return ParsedFields(scalars: scalars, lists: lists, maps: maps)
    }

    private static func parseLines(_ text: String) -> [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, rawLine in
            let withoutComment = stripComment(String(rawLine))
            guard !withoutComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let indent = withoutComment.prefix { $0 == " " }.count
            let text = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            return Line(number: offset + 1, indent: indent, text: text)
        }
    }

    private static func keyValue(from text: String) -> (String, String)? {
        guard let separator = text.firstIndex(of: ":") else { return nil }
        let key = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStart = text.index(after: separator)
        let value = String(text[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (unquote(key), value)
    }

    private static func isEnvContinuation(_ text: String) -> Bool {
        guard let (key, value) = keyValue(from: text), !value.isEmpty else { return false }
        let serverFieldKeys: Set<String> = [
            "args", "command", "connect_timeout", "enabled", "env", "timeout", "transport", "type", "url",
        ]
        return !serverFieldKeys.contains(key)
    }

    private static func stripComment(_ line: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        var previous: Character?
        for (index, character) in line.enumerated() {
            if character == "'", !inDoubleQuote { inSingleQuote.toggle() }
            if character == "\"", !inSingleQuote, previous != "\\" { inDoubleQuote.toggle() }
            if character == "#", !inSingleQuote, !inDoubleQuote {
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
