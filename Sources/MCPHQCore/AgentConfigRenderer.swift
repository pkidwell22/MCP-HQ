import Foundation

public enum AgentConfigRenderError: Error, Equatable, CustomStringConvertible {
    case unsupportedAgent(AgentID)
    case invalidGeneratedUTF8
    case parseVerificationFailed(String)

    public var description: String {
        switch self {
        case .unsupportedAgent(let agent):
            return "Config rendering is not supported for \(agent.rawValue)"
        case .invalidGeneratedUTF8:
            return "Generated config was not valid UTF-8"
        case .parseVerificationFailed(let message):
            return "Generated config failed parse verification: \(message)"
        }
    }
}

public enum ConfigVisualDiffLineKind: String, Equatable, Sendable {
    case added
    case removed
    case context
}

public struct ConfigVisualDiffLine: Equatable, Sendable {
    public let kind: ConfigVisualDiffLineKind
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(kind: ConfigVisualDiffLineKind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }

    public func replacingContent(_ content: String) -> ConfigVisualDiffLine {
        ConfigVisualDiffLine(kind: kind, content: content, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber)
    }
}

public enum ConfigDiffFormatter {
    public static func compactDiff(old: String, new: String) -> String {
        let oldLines = lines(in: old)
        let newLines = lines(in: new)
        if oldLines == newLines { return "No changes\n" }

        var commonPrefix = 0
        while commonPrefix < oldLines.count,
              commonPrefix < newLines.count,
              oldLines[commonPrefix] == newLines[commonPrefix] {
            commonPrefix += 1
        }

        var commonSuffix = 0
        while commonSuffix + commonPrefix < oldLines.count,
              commonSuffix + commonPrefix < newLines.count,
              oldLines[oldLines.count - 1 - commonSuffix] == newLines[newLines.count - 1 - commonSuffix] {
            commonSuffix += 1
        }

        let context = 3
        let oldChangeStart = commonPrefix
        let newChangeStart = commonPrefix
        let oldChangeEnd = oldLines.count - commonSuffix
        let newChangeEnd = newLines.count - commonSuffix
        let oldStart = max(0, oldChangeStart - context)
        let newStart = max(0, newChangeStart - context)
        let oldEnd = min(oldLines.count, oldChangeEnd + context)
        let newEnd = min(newLines.count, newChangeEnd + context)

        var lines = ["--- current", "+++ generated"]
        if oldStart > 0 || newStart > 0 {
            lines.append("... \(max(oldStart, newStart)) unchanged line\(max(oldStart, newStart) == 1 ? "" : "s") before")
        }
        lines.append("@@ current:\(oldStart + 1)-\(oldEnd) generated:\(newStart + 1)-\(newEnd) @@")
        for line in oldLines[oldStart..<oldEnd] {
            lines.append("-\(line)")
        }
        for line in newLines[newStart..<newEnd] {
            lines.append("+\(line)")
        }
        let omittedAfter = min(oldLines.count - oldEnd, newLines.count - newEnd)
        if omittedAfter > 0 {
            lines.append("... \(omittedAfter) unchanged line\(omittedAfter == 1 ? "" : "s") after")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func visualDiff(old: String, new: String) -> [ConfigVisualDiffLine] {
        let oldLines = lines(in: old)
        let newLines = lines(in: new)
        if oldLines == newLines { return [] }

        let table = longestCommonSubsequenceTable(oldLines: oldLines, newLines: newLines)
        var output: [ConfigVisualDiffLine] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count, newIndex < newLines.count {
            if oldLines[oldIndex] == newLines[newIndex] {
                output.append(ConfigVisualDiffLine(
                    kind: .context,
                    content: oldLines[oldIndex],
                    oldLineNumber: oldIndex + 1,
                    newLineNumber: newIndex + 1
                ))
                oldIndex += 1
                newIndex += 1
            } else if table[oldIndex + 1][newIndex] >= table[oldIndex][newIndex + 1] {
                output.append(ConfigVisualDiffLine(
                    kind: .removed,
                    content: oldLines[oldIndex],
                    oldLineNumber: oldIndex + 1,
                    newLineNumber: nil
                ))
                oldIndex += 1
            } else {
                output.append(ConfigVisualDiffLine(
                    kind: .added,
                    content: newLines[newIndex],
                    oldLineNumber: nil,
                    newLineNumber: newIndex + 1
                ))
                newIndex += 1
            }
        }

        while oldIndex < oldLines.count {
            output.append(ConfigVisualDiffLine(
                kind: .removed,
                content: oldLines[oldIndex],
                oldLineNumber: oldIndex + 1,
                newLineNumber: nil
            ))
            oldIndex += 1
        }

        while newIndex < newLines.count {
            output.append(ConfigVisualDiffLine(
                kind: .added,
                content: newLines[newIndex],
                oldLineNumber: nil,
                newLineNumber: newIndex + 1
            ))
            newIndex += 1
        }

        return output
    }

    private static func lines(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func longestCommonSubsequenceTable(oldLines: [String], newLines: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )
        guard !oldLines.isEmpty, !newLines.isEmpty else { return table }

        for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                if oldLines[oldIndex] == newLines[newIndex] {
                    table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(table[oldIndex + 1][newIndex], table[oldIndex][newIndex + 1])
                }
            }
        }
        return table
    }
}

public struct GeneratedConfigPreview: Equatable, Sendable {
    public let source: ConfigSource
    public let renderedText: String
    public let diffText: String
    public let visualDiffLines: [ConfigVisualDiffLine]
    public let reparsedServers: [ServerDefinition]

    public init(
        source: ConfigSource,
        renderedText: String,
        diffText: String,
        visualDiffLines: [ConfigVisualDiffLine] = [],
        reparsedServers: [ServerDefinition]
    ) {
        self.source = source
        self.renderedText = renderedText
        self.diffText = diffText
        self.visualDiffLines = visualDiffLines
        self.reparsedServers = reparsedServers
    }
}

public struct ConfigApplyResult: Equatable, Sendable {
    public let preview: GeneratedConfigPreview
    public let didWrite: Bool
    public let backupPath: String?

    public init(preview: GeneratedConfigPreview, didWrite: Bool, backupPath: String?) {
        self.preview = preview
        self.didWrite = didWrite
        self.backupPath = backupPath
    }
}

public struct AgentConfigRenderer {
    public init() {}

    public func render(servers: [ServerDefinition], for source: ConfigSource) throws -> String {
        switch source.agent {
        case .antigravity, .claude, .gemini, .pi, .cursor, .windsurf, .continue:
            return try renderStandardJSON(servers: servers, source: source)
        case .opencode:
            return try renderOpenCodeJSON(servers: servers, source: source)
        case .codex:
            return renderCodexTOML(servers: servers)
        case .hermes, .goose:
            return renderYAML(servers: servers)
        case .unknown:
            throw AgentConfigRenderError.unsupportedAgent(source.agent)
        }
    }

    private func renderStandardJSON(servers: [ServerDefinition], source: ConfigSource) throws -> String {
        var mcpServers: [String: Any] = [:]
        for server in servers {
            var object: [String: Any] = [:]
            if server.transport == .stdio, let command = server.command, !command.isEmpty {
                object["command"] = SecretRedactor.redactText(command)
                if !server.args.isEmpty { object["args"] = SecretRedactor.redactCommandArguments(server.args) }
            } else if let url = server.url, !url.isEmpty {
                let urlKey = server.transport == .streamableHTTP ? "serverUrl" : "url"
                object[urlKey] = SecretRedactor.redactText(url)
                object["transport"] = server.transport.rawValue
            }
            if !server.envBindings.isEmpty {
                object["env"] = safeMap(server.envBindings)
            }
            if !server.headers.isEmpty {
                object["headers"] = safeMap(server.headers)
            }
            mcpServers[server.displayName] = object
        }
        return try jsonString(["mcpServers": mcpServers])
    }

    private func renderOpenCodeJSON(servers: [ServerDefinition], source: ConfigSource) throws -> String {
        var mcp: [String: Any] = [:]
        for server in servers {
            var object: [String: Any] = [:]
            if server.transport == .stdio, let command = server.command, !command.isEmpty {
                object["type"] = "local"
                object["command"] = SecretRedactor.redactCommandArguments([command] + server.args)
            } else if let url = server.url, !url.isEmpty {
                object["type"] = "remote"
                object["url"] = SecretRedactor.redactText(url)
            }
            if !server.envBindings.isEmpty {
                object["environment"] = safeMap(server.envBindings)
            }
            if !server.headers.isEmpty {
                object["headers"] = safeMap(server.headers)
            }
            mcp[server.displayName] = object
        }
        return try jsonString(["mcp": mcp])
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgentConfigRenderError.invalidGeneratedUTF8
        }
        return text + "\n"
    }

    private func renderCodexTOML(servers: [ServerDefinition]) -> String {
        var lines: [String] = []
        for server in servers.sorted(by: { $0.displayName < $1.displayName }) {
            let serverKey = tomlKey(server.displayName)
            lines.append("[mcp_servers.\(serverKey)]")
            if server.transport == .stdio, let command = server.command, !command.isEmpty {
                lines.append("command = \(tomlString(SecretRedactor.redactText(command)))")
                if !server.args.isEmpty {
                    lines.append("args = [\(SecretRedactor.redactCommandArguments(server.args).map(tomlString).joined(separator: ", "))]")
                }
            } else if let url = server.url, !url.isEmpty {
                lines.append("url = \(tomlString(SecretRedactor.redactText(url)))")
                lines.append("transport = \(tomlString(server.transport.rawValue))")
            }
            appendTOMLMap(section: "[mcp_servers.\(serverKey).env]", values: safeMap(server.envBindings), to: &lines)
            appendTOMLMap(section: "[mcp_servers.\(serverKey).headers]", values: safeMap(server.headers), to: &lines)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func appendTOMLMap(section: String, values: [String: String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append(section)
        for key in values.keys.sorted() {
            lines.append("\(tomlKey(key)) = \(tomlString(values[key] ?? ""))")
        }
    }

    private func renderYAML(servers: [ServerDefinition]) -> String {
        var lines = ["mcp_servers:"]
        for server in servers.sorted(by: { $0.displayName < $1.displayName }) {
            lines.append("  \(yamlKey(server.displayName)):")
            if server.transport == .stdio, let command = server.command, !command.isEmpty {
                lines.append("    command: \(yamlScalar(SecretRedactor.redactText(command)))")
                if !server.args.isEmpty {
                    lines.append("    args:")
                    for arg in SecretRedactor.redactCommandArguments(server.args) {
                        lines.append("      - \(yamlScalar(arg))")
                    }
                }
            } else if let url = server.url, !url.isEmpty {
                lines.append("    url: \(yamlScalar(SecretRedactor.redactText(url)))")
                lines.append("    transport: \(yamlScalar(server.transport.rawValue))")
            }
            appendYAMLMap(named: "env", values: safeMap(server.envBindings), to: &lines)
            appendYAMLMap(named: "headers", values: safeMap(server.headers), to: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendYAMLMap(named name: String, values: [String: String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("    \(name):")
        for key in values.keys.sorted() {
            lines.append("      \(yamlKey(key)): \(yamlScalar(values[key] ?? ""))")
        }
    }

    private func safeMap(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, pair in
            result[pair.key] = safeValue(pair.value, key: pair.key)
        }
    }

    private func safeValue(_ value: String, key: String) -> String {
        if isReference(value) { return value }
        if looksSensitive(value) {
            let reference = "${\(referenceName(for: key))}"
            if value.lowercased().hasPrefix("bearer ") {
                return "Bearer \(reference)"
            }
            return reference
        }
        return value
    }

    private func isReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$")
            || trimmed.contains("${")
            || KeychainSecretReference.parse(from: trimmed) != nil
    }

    private func looksSensitive(_ value: String) -> Bool {
        SecretRedactor.redactText(value) != value || SecretRedactor.redactIfSensitive(value) == "<redacted>"
    }

    private func referenceName(for key: String) -> String {
        let scalars = key.uppercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars).split(separator: "_").joined(separator: "_")
        return collapsed.isEmpty ? "MCP_SECRET" : collapsed
    }

    private func tomlKey(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return tomlString(value)
    }

    private func tomlString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func yamlKey(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return yamlScalar(value)
    }

    private func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public struct AgentConfigSafeApplier {
    private let renderer: AgentConfigRenderer
    private let parser: AgentConfigParser
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        renderer: AgentConfigRenderer = AgentConfigRenderer(),
        parser: AgentConfigParser = AgentConfigParser(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.renderer = renderer
        self.parser = parser
        self.fileManager = fileManager
        self.now = now
    }

    public func preview(source: ConfigSource, servers: [ServerDefinition], existingData: Data? = nil) throws -> GeneratedConfigPreview {
        let existingText = existingData.flatMap { String(data: $0, encoding: .utf8) } ?? readExistingText(at: source.path)
        let renderedText = try Self.mergedRenderedText(
            baseRenderedText: renderer.render(servers: servers, for: source),
            existingText: existingText,
            source: source,
            servers: servers
        )
        guard let renderedData = renderedText.data(using: .utf8) else {
            throw AgentConfigRenderError.invalidGeneratedUTF8
        }
        let reparsed = try parser.parse(data: renderedData, source: source)
        guard reparsed.count == servers.count else {
            throw AgentConfigRenderError.parseVerificationFailed("expected \(servers.count) servers, reparsed \(reparsed.count)")
        }
        let currentText = existingText ?? ""
        let compactDiff = ConfigDiffFormatter.compactDiff(old: currentText, new: renderedText)
        let visualDiffLines = ConfigDiffFormatter.visualDiff(old: currentText, new: renderedText)
            .map { $0.replacingContent(SecretRedactor.redactConfigText($0.content)) }
        return GeneratedConfigPreview(
            source: source,
            renderedText: renderedText,
            diffText: SecretRedactor.redactConfigText(compactDiff),
            visualDiffLines: visualDiffLines,
            reparsedServers: reparsed
        )
    }

    public func apply(source: ConfigSource, servers: [ServerDefinition], dryRun: Bool = false) throws -> ConfigApplyResult {
        let preview = try preview(source: source, servers: servers)
        if dryRun {
            return ConfigApplyResult(preview: preview, didWrite: false, backupPath: nil)
        }

        let url = URL(fileURLWithPath: source.path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backupURL = try createBackupIfNeeded(for: url)

        do {
            try preview.renderedText.write(to: url, atomically: true, encoding: .utf8)
            let writtenData = try Data(contentsOf: url)
            let reparsed = try parser.parse(data: writtenData, source: source)
            guard reparsed.count == servers.count else {
                throw AgentConfigRenderError.parseVerificationFailed("expected \(servers.count) servers after write, reparsed \(reparsed.count)")
            }
            return ConfigApplyResult(preview: preview, didWrite: true, backupPath: backupURL?.path)
        } catch {
            try rollback(writtenURL: url, backupURL: backupURL)
            throw error
        }
    }

    private func readExistingText(at path: String) -> String? {
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func mergedRenderedText(
        baseRenderedText: String,
        existingText: String?,
        source: ConfigSource,
        servers: [ServerDefinition]
    ) throws -> String {
        guard let existingText, !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseRenderedText
        }

        switch source.agent {
        case .antigravity, .claude, .gemini, .pi, .cursor, .windsurf, .continue:
            return try mergedJSON(existingText: existingText, renderedText: baseRenderedText, mcpKey: "mcpServers")
        case .opencode:
            return try mergedJSON(existingText: existingText, renderedText: baseRenderedText, mcpKey: "mcp")
        case .codex:
            return mergedTOML(existingText: existingText, renderedText: baseRenderedText, source: source, servers: servers)
        case .hermes, .goose:
            return mergedYAML(existingText: existingText, renderedText: baseRenderedText, source: source, servers: servers)
        case .unknown:
            return baseRenderedText
        }
    }

    private static func mergedJSON(existingText: String, renderedText: String, mcpKey: String) throws -> String {
        guard let existingData = existingText.data(using: .utf8),
              let renderedData = renderedText.data(using: .utf8),
              var existingObject = try JSONSerialization.jsonObject(with: existingData) as? [String: Any],
              let renderedObject = try JSONSerialization.jsonObject(with: renderedData) as? [String: Any],
              let renderedMCP = renderedObject[mcpKey] else {
            return renderedText
        }
        existingObject[mcpKey] = renderedMCP
        let data = try JSONSerialization.data(withJSONObject: existingObject, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgentConfigRenderError.invalidGeneratedUTF8
        }
        return text + "\n"
    }

    private static func mergedYAML(
        existingText: String,
        renderedText: String,
        source: ConfigSource,
        servers: [ServerDefinition]
    ) -> String {
        let replacement = mergedYAMLReplacement(
            existingText: existingText,
            renderedText: renderedText,
            source: source,
            servers: servers
        )
        return replaceTopLevelYAMLBlock(named: "mcp_servers", in: existingText, with: replacement)
    }

    private static func replaceTopLevelYAMLBlock(named blockName: String, in existingText: String, with renderedText: String) -> String {
        var lines = existingText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "\(blockName):" }) else {
            return appendBlock(renderedText, to: existingText)
        }

        var end = start + 1
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            let isTopLevelContent = !lines[end].isEmpty
                && lines[end].first?.isWhitespace != true
                && !trimmed.hasPrefix("#")
            if isTopLevelContent { break }
            end += 1
        }

        let replacement = renderedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.replaceSubrange(start..<end, with: replacement)
        return normalizedText(lines.joined(separator: "\n"))
    }

    private static func mergedYAMLReplacement(
        existingText: String,
        renderedText: String,
        source: ConfigSource,
        servers: [ServerDefinition]
    ) -> String {
        let renderedBlocks = yamlMCPServerBlockList(in: renderedText)
        guard !renderedBlocks.isEmpty,
              let existingData = existingText.data(using: .utf8),
              let existingServers = try? AgentConfigParser().parse(data: existingData, source: source) else {
            return renderedText
        }

        let existingBlocks = yamlMCPServerBlocks(in: existingText)
        let existingServersByName = Dictionary(uniqueKeysWithValues: existingServers.map { ($0.displayName, $0) })
        let desiredServersByName = Dictionary(uniqueKeysWithValues: servers.map { ($0.displayName, $0) })
        var lines = ["mcp_servers:"]

        for block in renderedBlocks {
            if let existingServer = existingServersByName[block.name],
               let desiredServer = desiredServersByName[block.name],
               semanticallyEqual(existingServer, desiredServer),
               let existingBlock = existingBlocks[block.name] {
                lines.append(contentsOf: existingBlock.lines)
            } else {
                lines.append(contentsOf: block.lines)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private struct YAMLServerBlock {
        let name: String
        let lines: [String]
    }

    private static func yamlMCPServerBlocks(in text: String) -> [String: YAMLServerBlock] {
        Dictionary(uniqueKeysWithValues: yamlMCPServerBlockList(in: text).map { ($0.name, $0) })
    }

    private static func yamlMCPServerBlockList(in text: String) -> [YAMLServerBlock] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "mcp_servers:" }) else {
            return []
        }

        let parentIndent = leadingSpaceCount(lines[start])
        let childIndent = parentIndent + 2
        var childHeaderIndexes: [Int] = []
        var index = start + 1

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTopLevelContent = !line.isEmpty
                && leadingSpaceCount(line) <= parentIndent
                && !trimmed.hasPrefix("#")
            if isTopLevelContent { break }

            if leadingSpaceCount(line) == childIndent,
               trimmed.hasSuffix(":"),
               !trimmed.hasPrefix("-") {
                childHeaderIndexes.append(index)
            }
            index += 1
        }

        let blockEnd = index
        return childHeaderIndexes.enumerated().compactMap { offset, headerIndex in
            let nextHeaderIndex = offset + 1 < childHeaderIndexes.count ? childHeaderIndexes[offset + 1] : blockEnd
            let trimmed = lines[headerIndex].trimmingCharacters(in: .whitespaces)
            let name = unquoteYAMLScalar(String(trimmed.dropLast()))
            guard !name.isEmpty else { return nil }
            return YAMLServerBlock(name: name, lines: Array(lines[headerIndex..<nextHeaderIndex]))
        }
    }

    private static func mergedTOML(
        existingText: String,
        renderedText: String,
        source: ConfigSource,
        servers: [ServerDefinition]
    ) -> String {
        let lines = existingText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let replacement = mergedTOMLReplacement(existingText: existingText, renderedText: renderedText, source: source, servers: servers)
        var output: [String] = []
        var index = 0
        var inserted = false

        while index < lines.count {
            if isMCPServersTOMLHeader(lines[index]) {
                if !inserted {
                    output.append(contentsOf: replacement)
                    inserted = true
                }
                index += 1
                while index < lines.count, !isNonMCPTableHeader(lines[index]) {
                    index += 1
                }
            } else {
                output.append(lines[index])
                index += 1
            }
        }

        if !inserted {
            return appendBlock(renderedText, to: existingText)
        }
        return normalizedText(output.joined(separator: "\n"))
    }

    private static func mergedTOMLReplacement(
        existingText: String,
        renderedText: String,
        source: ConfigSource,
        servers: [ServerDefinition]
    ) -> [String] {
        let renderedBlocks = tomlMCPServerBlockList(in: renderedText)
        guard !renderedBlocks.isEmpty,
              let existingData = existingText.data(using: .utf8),
              let existingServers = try? AgentConfigParser().parse(data: existingData, source: source) else {
            return renderedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }

        let existingBlocks = tomlMCPServerBlocks(in: existingText)
        let existingServersByName = Dictionary(uniqueKeysWithValues: existingServers.map { ($0.displayName, $0) })
        let desiredServersByName = Dictionary(uniqueKeysWithValues: servers.map { ($0.displayName, $0) })
        var lines: [String] = []

        for block in renderedBlocks {
            if let existingServer = existingServersByName[block.name],
               let desiredServer = desiredServersByName[block.name],
               semanticallyEqual(existingServer, desiredServer),
               let existingBlock = existingBlocks[block.name] {
                lines.append(contentsOf: existingBlock.lines)
            } else {
                lines.append(contentsOf: block.lines)
            }
        }

        return lines
    }

    private struct TOMLServerBlock {
        let name: String
        let lines: [String]
    }

    private static func tomlMCPServerBlocks(in text: String) -> [String: TOMLServerBlock] {
        Dictionary(uniqueKeysWithValues: tomlMCPServerBlockList(in: text).map { ($0.name, $0) })
    }

    private static func tomlMCPServerBlockList(in text: String) -> [TOMLServerBlock] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [TOMLServerBlock] = []
        var index = 0

        while index < lines.count {
            guard let name = tomlMCPRootServerName(lines[index]) else {
                index += 1
                continue
            }

            let start = index
            index += 1
            while index < lines.count {
                if tomlMCPRootServerName(lines[index]) != nil || isNonMCPTableHeader(lines[index]) {
                    break
                }
                index += 1
            }
            blocks.append(TOMLServerBlock(name: name, lines: Array(lines[start..<index])))
        }

        return blocks
    }

    private static func tomlMCPRootServerName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[mcp_servers."), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[mcp_servers.\"") else {
            return nil
        }
        let prefix = "[mcp_servers."
        let rawName = String(trimmed.dropFirst(prefix.count).dropLast())
        return rawName.contains(".") ? nil : rawName
    }

    private static func semanticallyEqual(_ lhs: ServerDefinition, _ rhs: ServerDefinition) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.transport == rhs.transport
            && lhs.command == rhs.command
            && lhs.args == rhs.args
            && lhs.url == rhs.url
            && lhs.headers == rhs.headers
            && lhs.envBindings == rhs.envBindings
    }

    private static func isMCPServersTOMLHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "[mcp_servers]" || trimmed.hasPrefix("[mcp_servers.")
    }

    private static func isNonMCPTableHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && !isMCPServersTOMLHeader(line)
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func unquoteYAMLScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              first == last,
              first == "\"" || first == "'" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func appendBlock(_ block: String, to text: String) -> String {
        let separator = text.hasSuffix("\n") ? "\n" : "\n\n"
        return normalizedText(text + separator + block)
    }

    private static func normalizedText(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private func createBackupIfNeeded(for url: URL) throws -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let timestamp = Self.backupTimestampFormatter.string(from: now())
        let backupURL = URL(fileURLWithPath: "\(url.path).mcphq-backup-\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func rollback(writtenURL: URL, backupURL: URL?) throws {
        if let backupURL {
            if fileManager.fileExists(atPath: writtenURL.path) {
                try fileManager.removeItem(at: writtenURL)
            }
            try fileManager.copyItem(at: backupURL, to: writtenURL)
        } else if fileManager.fileExists(atPath: writtenURL.path) {
            try fileManager.removeItem(at: writtenURL)
        }
    }

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

}
