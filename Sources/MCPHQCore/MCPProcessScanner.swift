import Foundation

public struct RawProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let commandLine: String

    public init(pid: Int32, commandLine: String) {
        self.pid = pid
        self.commandLine = commandLine
    }
}

public struct MCPProcessSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let executableName: String
    public let commandLine: String
    public let matchReason: String

    public init(pid: Int32, executableName: String, commandLine: String, matchReason: String) {
        self.pid = pid
        self.executableName = executableName
        self.commandLine = commandLine
        self.matchReason = matchReason
    }
}

public struct MCPProcessScanner: Sendable {
    private let processProvider: @Sendable () -> [RawProcessSnapshot]

    public init() {
        self.processProvider = MCPProcessScanner.defaultProcessProvider
    }

    public init(processProvider: @escaping @Sendable () -> [RawProcessSnapshot]) {
        self.processProvider = processProvider
    }

    public func scan() -> [MCPProcessSnapshot] {
        processProvider().compactMap { raw in
            guard let reason = matchReason(for: raw.commandLine) else { return nil }
            return MCPProcessSnapshot(
                pid: raw.pid,
                executableName: executableName(from: raw.commandLine),
                commandLine: redactCommandLine(raw.commandLine),
                matchReason: reason
            )
        }
    }

    public static func parsePSOutput(_ output: String) -> [RawProcessSnapshot] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let pid = Int32(parts[0]) else { return nil }
            return RawProcessSnapshot(pid: pid, commandLine: String(parts[1]))
        }
    }

    private static func defaultProcessProvider() -> [RawProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return parsePSOutput(output)
        } catch {
            return []
        }
    }

    private func matchReason(for commandLine: String) -> String? {
        let lowercased = commandLine.lowercased()
        if lowercased.contains("mcphq") { return nil }
        if lowercased.contains("@modelcontextprotocol/server-") { return "mcp command pattern" }
        if lowercased.contains("mcp-server") { return "mcp command pattern" }
        if lowercased.contains("-m ") && lowercased.contains("mcp") { return "mcp command pattern" }
        if lowercased.contains(" mcp") || lowercased.contains("mcp ") || lowercased.hasSuffix("mcp") { return "mcp command pattern" }
        if lowercased.contains("-mcp") || lowercased.contains("_mcp") { return "mcp command pattern" }
        return nil
    }

    private func executableName(from commandLine: String) -> String {
        guard let firstPart = commandLine.split(separator: " ").first else { return "" }
        return URL(fileURLWithPath: String(firstPart)).lastPathComponent
    }

    private func redactCommandLine(_ commandLine: String) -> String {
        var tokens = commandLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let sensitiveFlags = Set(["--token", "--api-key", "--api_key", "--key", "--secret", "--password", "--auth", "--authorization"])
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            let lowercased = token.lowercased()
            if sensitiveFlags.contains(lowercased), index + 1 < tokens.endIndex {
                tokens[index + 1] = "<redacted>"
                index += 2
                continue
            }
            if let equalsIndex = token.firstIndex(of: "=") {
                let key = token[..<equalsIndex].lowercased()
                let sensitiveKeyParts = ["token", "api_key", "apikey", "secret", "password", "authorization", "auth"]
                if sensitiveKeyParts.contains(where: { key.contains($0) }) {
                    tokens[index] = String(token[..<token.index(after: equalsIndex)]) + "<redacted>"
                } else {
                    tokens[index] = SecretRedactor.redactIfSensitive(token)
                }
            } else {
                tokens[index] = SecretRedactor.redactIfSensitive(token)
            }
            index += 1
        }
        return tokens.joined(separator: " ")
    }
}
