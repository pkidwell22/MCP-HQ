import Foundation

public struct MCPHQCommand: Sendable {
    private let defaultSourceProvider: DefaultConfigSourceProvider
    private let formatter: ScanOutputFormatter
    private let processScanner: MCPProcessScanner

    public init(
        defaultSourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        formatter: ScanOutputFormatter = ScanOutputFormatter(),
        processScanner: MCPProcessScanner = MCPProcessScanner()
    ) {
        self.defaultSourceProvider = defaultSourceProvider
        self.formatter = formatter
        self.processScanner = processScanner
    }

    public func run(args: [String]) throws -> MCPHQCommandResult {
        guard args.first == "scan" else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: usage())
        }

        return try runScan(args: Array(args.dropFirst()))
    }

    private func runScan(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var explicitSources: [ConfigSource] = []
        var index = 0

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                explicitSources.append(source)
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown scan option: \(argument)\n\(usage())")
            }
        }

        let sources = explicitSources.isEmpty ? defaultSourceProvider.sources() : explicitSources
        let configResult = ConfigScanner(configSources: sources).scan()
        let processes = processScanner.scan()
        let result = ScanResult(
            servers: configResult.servers,
            sources: configResult.sources,
            issues: configResult.issues,
            processes: processes,
            processMatches: ServerProcessMatcher().matches(servers: configResult.servers, processes: processes)
        )
        let stdout = outputJSON ? try formatter.formatJSON(result) : formatter.formatText(result)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func parseSource(_ value: String) -> ConfigSource? {
        guard let separatorIndex = value.firstIndex(of: ":") else { return nil }
        let agentValue = String(value[..<separatorIndex])
        let pathStart = value.index(after: separatorIndex)
        let path = String(value[pathStart...])
        guard !path.isEmpty, let agent = AgentID(rawValue: agentValue) else { return nil }
        return ConfigSource(agent: agent, path: path)
    }

    private func usage() -> String {
        """
        Usage:
          mcphq scan [--json] [--source agent:/path/to/config]

        Examples:
          mcphq scan
          mcphq scan --json
          mcphq scan --source claude:/Users/me/.config/claude.json
        """
    }
}

public struct MCPHQCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
