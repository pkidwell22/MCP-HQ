import Foundation

public struct ScanCoordinator: Sendable {
    private let processScanner: MCPProcessScanner
    private let probeProvider: @Sendable ([ServerDefinition]) -> [MCPProbeResult]

    public init(
        processScanner: MCPProcessScanner = MCPProcessScanner(),
        probeProvider: @escaping @Sendable ([ServerDefinition]) -> [MCPProbeResult] = { MCPStdioProbe().probe(servers: $0) }
    ) {
        self.processScanner = processScanner
        self.probeProvider = probeProvider
    }

    public func scan(sources: [ConfigSource], includeProbes: Bool = false) -> ScanResult {
        let configResult = ConfigScanner(configSources: sources).scan()
        let processes = processScanner.scan()
        let probeResults = includeProbes ? probeProvider(configResult.servers) : []
        return ScanResult(
            servers: configResult.servers,
            sources: configResult.sources,
            issues: configResult.issues + ServerDiagnosticChecker().issues(servers: configResult.servers, sources: configResult.sources),
            processes: processes,
            processMatches: ServerProcessMatcher().matches(servers: configResult.servers, processes: processes),
            probeResults: probeResults
        )
    }
}
