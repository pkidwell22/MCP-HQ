import Foundation

public struct ScanOutputFormatter: Sendable {
    public init() {}

    private func probeSummary(for result: MCPProbeResult) -> String {
        let toolText = result.toolCount.map { "\($0) \($0 == 1 ? "tool" : "tools")" } ?? "tool count unknown"
        var parts = [result.status.rawValue, toolText]
        if let resourceCount = result.resourceCount {
            parts.append("\(resourceCount) \(resourceCount == 1 ? "resource" : "resources")")
        }
        if let promptCount = result.promptCount {
            parts.append("\(promptCount) \(promptCount == 1 ? "prompt" : "prompts")")
        }
        if result.pingSucceeded == true {
            parts.append("ping ok")
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

        if !result.sourceHealth.isEmpty {
            lines.append("")
            lines.append("Sources:")
            for health in result.sourceHealth {
                lines.append("  \(AgentRegistry.displayName(for: health.source.agent)) \(sourceStateText(health.state)): \(health.message)")
                lines.append("    path: \(health.source.path)")
            }
        }

        if !result.servers.isEmpty {
            lines.append("")
            let probesByServer = Dictionary(result.probeResults.map { ($0.serverID, $0) }, uniquingKeysWith: { first, _ in first })
            for server in result.servers {
                lines.append(server.displayName)
                lines.append("  transport: \(server.transport.rawValue)")
                if let command = server.command, !command.isEmpty {
                    let redactedParts = SecretRedactor.redactCommandArguments([command] + server.args)
                    lines.append("  command: \(redactedParts.first ?? "")")
                    lines.append("  args: \(redactedParts.dropFirst().isEmpty ? "—" : redactedParts.dropFirst().joined(separator: " "))")
                }
                if let url = server.url, !url.isEmpty {
                    lines.append("  url: \(SecretRedactor.redactText(url))")
                }
                let headers = server.redactedHeaders
                if !headers.isEmpty {
                    lines.append("  headers:")
                    for key in headers.keys.sorted() {
                        lines.append("    \(key)=\(headers[key] ?? "")")
                    }
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

    private func sourceStateText(_ state: ConfigSourceState) -> String {
        switch state {
        case .missing:
            return "missing"
        case .found:
            return "found"
        case .parsed:
            return "parsed"
        case .unsupported:
            return "unsupported"
        case .malformed:
            return "malformed"
        case .noServers:
            return "no servers"
        }
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
    let sourceHealth: [ConfigSourceHealth]
    let issues: [ScanIssue]
    let processes: [MCPProcessSnapshot]
    let processMatches: [ServerProcessMatch]
    let probeResults: [MCPProbeResult]

    init(result: ScanResult) {
        self.servers = result.servers.map(SafeServerDefinition.init(server:))
        self.sources = result.sources
        self.sourceHealth = result.sourceHealth
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
    let headers: [String: String]
    let envBindings: [String: String]
    let sourcePath: String

    init(server: ServerDefinition) {
        self.id = server.id
        self.displayName = server.displayName
        self.transport = server.transport
        if let command = server.command {
            let commandParts = SecretRedactor.redactCommandArguments([command] + server.args)
            self.command = commandParts.first
            self.args = Array(commandParts.dropFirst())
        } else {
            self.command = nil
            self.args = SecretRedactor.redactCommandArguments(server.args)
        }
        self.url = server.url.map(SecretRedactor.redactText)
        self.headers = server.redactedHeaders
        self.envBindings = server.redactedEnvBindings
        self.sourcePath = server.sourcePath
    }
}
