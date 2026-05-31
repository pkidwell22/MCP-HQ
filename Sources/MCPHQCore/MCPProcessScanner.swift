import Foundation

public struct RawProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let commandLine: String
    public let cpuPercent: Double?
    public let memoryBytes: UInt64?

    public init(pid: Int32, commandLine: String, cpuPercent: Double? = nil, memoryBytes: UInt64? = nil) {
        self.pid = pid
        self.commandLine = commandLine
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct MCPProcessSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let executableName: String
    public let commandLine: String
    public let matchReason: String
    public let cpuPercent: Double?
    public let memoryBytes: UInt64?

    public init(
        pid: Int32,
        executableName: String,
        commandLine: String,
        matchReason: String,
        cpuPercent: Double? = nil,
        memoryBytes: UInt64? = nil
    ) {
        self.pid = pid
        self.executableName = executableName
        self.commandLine = commandLine
        self.matchReason = matchReason
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
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
                matchReason: reason,
                cpuPercent: raw.cpuPercent,
                memoryBytes: raw.memoryBytes
            )
        }
    }

    public static func parsePSOutput(_ output: String) -> [RawProcessSnapshot] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let parts = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let pid = Int32(parts[0]) else { return nil }

            if parts.count == 4,
               let cpuPercent = Double(parts[1]),
               let residentSetKilobytes = UInt64(parts[2]) {
                return RawProcessSnapshot(
                    pid: pid,
                    commandLine: String(parts[3]),
                    cpuPercent: cpuPercent,
                    memoryBytes: residentSetKilobytes * 1024
                )
            }

            let legacyParts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard legacyParts.count == 2 else { return nil }
            return RawProcessSnapshot(pid: pid, commandLine: String(legacyParts[1]))
        }
    }

    private static func defaultProcessProvider() -> [RawProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,command="]

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
        if lowercased.contains("mcphq") || lowercased.contains("mcp-hq") { return nil }
        if lowercased.contains("swift-test") { return nil }
        if lowercased.contains("swift test") { return nil }
        if isDiagnosticSearchCommand(lowercased) { return nil }
        if lowercased.contains("@modelcontextprotocol/server-") { return "mcp command pattern" }
        if lowercased.contains("mcp-server") { return "mcp command pattern" }
        if lowercased.contains("-m ") && lowercased.contains("mcp") { return "mcp command pattern" }
        if lowercased.contains(" mcp") || lowercased.contains("mcp ") || lowercased.hasSuffix("mcp") { return "mcp command pattern" }
        if lowercased.contains("-mcp") || lowercased.contains("_mcp") { return "mcp command pattern" }
        return nil
    }

    private func isDiagnosticSearchCommand(_ lowercasedCommandLine: String) -> Bool {
        if lowercasedCommandLine.contains("ps aux | rg") { return true }
        if lowercasedCommandLine.contains("ps aux | grep") { return true }
        if lowercasedCommandLine.contains(" rg ") && lowercasedCommandLine.contains("mcp") { return true }
        if lowercasedCommandLine.contains("/rg ") && lowercasedCommandLine.contains("mcp") { return true }
        if lowercasedCommandLine.contains(" grep ") && lowercasedCommandLine.contains("mcp") { return true }
        if lowercasedCommandLine.contains("/grep ") && lowercasedCommandLine.contains("mcp") { return true }
        return false
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
                let normalizedKey = key.replacingOccurrences(of: "-", with: "_")
                let sensitiveKeyParts = ["token", "api_key", "apikey", "key", "secret", "password", "authorization", "auth"]
                if sensitiveKeyParts.contains(where: { normalizedKey.contains($0) }) {
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
