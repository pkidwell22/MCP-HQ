import Foundation

public struct MCPLiveProbe {
    private let stdioProbe: ([ServerDefinition]) -> [MCPProbeResult]
    private let httpProbe: ([ServerDefinition]) -> [MCPProbeResult]

    public init(
        stdioProbe: @escaping ([ServerDefinition]) -> [MCPProbeResult] = { MCPStdioProbe().probe(servers: $0) },
        httpProbe: @escaping ([ServerDefinition]) -> [MCPProbeResult] = { MCPHTTPProbe().probe(servers: $0) }
    ) {
        self.stdioProbe = stdioProbe
        self.httpProbe = httpProbe
    }

    public func probe(servers: [ServerDefinition]) -> [MCPProbeResult] {
        let stdioServers = servers.filter { $0.transport == .stdio }
        let httpServers = servers.filter { $0.transport == .http || $0.transport == .streamableHTTP }
        let stdioResults = stdioProbe(stdioServers)
        let httpResults = httpProbe(httpServers)
        var resultsByServerID: [String: MCPProbeResult] = [:]
        for result in stdioResults + httpResults {
            resultsByServerID[result.serverID] = result
        }

        return servers.map { server in
            if let result = resultsByServerID[server.id] { return result }
            if server.transport == .sse {
                return MCPProbeResult(
                    serverID: server.id,
                    status: .skipped,
                    message: "Legacy SSE probing is not implemented yet."
                )
            }
            return MCPProbeResult(
                serverID: server.id,
                status: .skipped,
                message: "No live probe is available for \(server.transport.rawValue)."
            )
        }
    }
}
