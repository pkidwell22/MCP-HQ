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
        let representatives = probeRepresentatives(for: servers)
        let representativeServers = representatives.map(\.server)
        let stdioServers = representativeServers.filter { $0.transport == .stdio }
        let httpServers = representativeServers.filter { $0.transport == .http || $0.transport == .streamableHTTP }
        let stdioResults = stdioProbe(stdioServers)
        let httpResults = httpProbe(httpServers)
        var resultsByServerID: [String: MCPProbeResult] = [:]
        for result in stdioResults + httpResults {
            resultsByServerID[result.serverID] = result
        }
        let representativeIDByKey = Dictionary(uniqueKeysWithValues: representatives.map { ($0.key, $0.server.id) })

        return servers.map { server in
            let key = probeReuseKey(for: server)
            if let representativeID = representativeIDByKey[key],
               let result = resultsByServerID[representativeID] {
                return retarget(result, to: server.id)
            }
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

    private func probeRepresentatives(for servers: [ServerDefinition]) -> [(key: String, server: ServerDefinition)] {
        var seen: Set<String> = []
        var representatives: [(key: String, server: ServerDefinition)] = []
        for server in servers {
            let key = probeReuseKey(for: server)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            representatives.append((key, server))
        }
        return representatives
    }

    private func retarget(_ result: MCPProbeResult, to serverID: String) -> MCPProbeResult {
        MCPProbeResult(
            serverID: serverID,
            status: result.status,
            toolCount: result.toolCount,
            toolNames: result.toolNames,
            toolDetails: result.toolDetails,
            resourceCount: result.resourceCount,
            resourceNames: result.resourceNames,
            resourceDetails: result.resourceDetails,
            pingSucceeded: result.pingSucceeded,
            promptCount: result.promptCount,
            promptNames: result.promptNames,
            promptDetails: result.promptDetails,
            message: result.message
        )
    }

    private func probeReuseKey(for server: ServerDefinition) -> String {
        let environment = server.envBindings
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let headers = server.headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return ([
            server.transport.rawValue,
            server.command ?? "",
            server.url ?? "",
        ] + server.args + environment + headers).joined(separator: "\u{0}")
    }
}
