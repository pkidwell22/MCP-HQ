import Foundation

public struct ScanOutputFormatter: Sendable {
    public init() {}

    private func probeSummary(for result: MCPProbeResult) -> String {
        let toolText = result.toolCount.map { "\($0) \($0 == 1 ? "tool" : "tools")" } ?? "tool count unknown"
        var parts = [result.status.rawValue, toolText]
        if let resourceCount = result.resourceCount {
            parts.append("\(resourceCount) \(resourceCount == 1 ? "resource" : "resources")")
        }
        parts.append(result.message)
        return parts.joined(separator: " • ")
    }

    public func formatText(_ result: ScanResult) -> String {
        var lines: [String] = []
        lines.append("MCP-HQ scan")
        lines.append("")
        lines.append("Servers: \(result.servers.count)")
        lines.append("Processes: \(result.processes.count)")
        lines.append("Issues: \(result.issues.count)")

        if !result.servers.isEmpty {
            lines.append("")
            let probesByServer = Dictionary(uniqueKeysWithValues: result.probeResults.map { ($0.serverID, $0) })
            for server in result.servers {
                lines.append(server.displayName)
                lines.append("  transport: \(server.transport.rawValue)")
                if let command = server.command, !command.isEmpty {
                    lines.append("  command: \(command)")
                    lines.append("  args: \(server.args.isEmpty ? "—" : server.args.joined(separator: " "))")
                }
                if let url = server.url, !url.isEmpty {
                    lines.append("  url: \(url)")
                }
                let env = server.redactedEnvBindings
                if !env.isEmpty {
                    lines.append("  env:")
                    for key in env.keys.sorted() {
                        lines.append("    \(key)=\(env[key] ?? "")")
                    }
                }
                lines.append("  source: \(server.sourcePath)")
                if let probe = probesByServer[server.id] {
                    lines.append("  probe: \(probeSummary(for: probe))")
                }
                lines.append("")
            }
            if lines.last == "" { lines.removeLast() }
        }

        if !result.processes.isEmpty {
            lines.append("")
            lines.append("Running processes:")
            for process in result.processes.sorted(by: { $0.pid < $1.pid }) {
                lines.append("  \(process.pid) \(process.executableName): \(process.commandLine)")
                lines.append("    match: \(process.matchReason)")
            }
        }

        if !result.processMatches.isEmpty {
            lines.append("")
            lines.append("Process matches:")
            for match in result.processMatches.sorted(by: { lhs, rhs in
                if lhs.serverID != rhs.serverID { return lhs.serverID < rhs.serverID }
                return lhs.processID < rhs.processID
            }) {
                lines.append("  \(match.serverID) -> pid \(match.processID) (\(match.confidence.rawValue)): \(match.reason)")
            }
        }

        if !result.issues.isEmpty {
            lines.append("")
            lines.append("Issues:")
            for issue in result.issues {
                lines.append("  \(issue.severity.rawValue) \(issue.source.agent.rawValue) \(issue.source.path): \(issue.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func formatJSON(_ result: ScanResult) throws -> String {
        let safeResult = SafeScanResult(result: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(safeResult)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScanOutputFormatterError.invalidUTF8
        }
        return json
    }
}

public enum ScanOutputFormatterError: Error, Equatable, Sendable {
    case invalidUTF8
}

private struct SafeScanResult: Codable {
    let servers: [SafeServerDefinition]
    let sources: [ConfigSource]
    let issues: [ScanIssue]
    let processes: [MCPProcessSnapshot]
    let processMatches: [ServerProcessMatch]
    let probeResults: [MCPProbeResult]

    init(result: ScanResult) {
        self.servers = result.servers.map(SafeServerDefinition.init(server:))
        self.sources = result.sources
        self.issues = result.issues
        self.processes = result.processes
        self.processMatches = result.processMatches
        self.probeResults = result.probeResults
    }
}

private struct SafeServerDefinition: Codable {
    let id: String
    let displayName: String
    let transport: MCPTransport
    let command: String?
    let args: [String]
    let url: String?
    let envBindings: [String: String]
    let sourcePath: String

    init(server: ServerDefinition) {
        self.id = server.id
        self.displayName = server.displayName
        self.transport = server.transport
        self.command = server.command
        self.args = server.args
        self.url = server.url
        self.envBindings = server.redactedEnvBindings
        self.sourcePath = server.sourcePath
    }
}
