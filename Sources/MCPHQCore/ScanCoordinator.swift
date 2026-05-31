import Foundation

public struct ScanCoordinator: Sendable {
    private let processScanner: MCPProcessScanner
    private let probeProvider: @Sendable ([ServerDefinition]) -> [MCPProbeResult]
    private let secretStore: SecretStore?

    public init(
        processScanner: MCPProcessScanner = MCPProcessScanner(),
        probeProvider: @escaping @Sendable ([ServerDefinition]) -> [MCPProbeResult] = { MCPLiveProbe().probe(servers: $0) },
        secretStore: SecretStore? = nil
    ) {
        self.processScanner = processScanner
        self.probeProvider = probeProvider
        self.secretStore = secretStore
    }

    public func scan(sources: [ConfigSource], includeProbes: Bool = false) -> ScanResult {
        let configResult = ConfigScanner(configSources: sources).scan()
        let processes = processScanner.scan()
        let probeResults = includeProbes ? probeProvider(configResult.servers) : []
        return ScanResult(
            servers: configResult.servers,
            sources: configResult.sources,
            sourceHealth: configResult.sourceHealth,
            issues: configResult.issues + ServerDiagnosticChecker(secretStore: secretStore).issues(servers: configResult.servers, sources: configResult.sources),
            processes: processes,
            processMatches: ServerProcessMatcher().matches(servers: configResult.servers, processes: processes),
            probeResults: probeResults
        )
    }
}
