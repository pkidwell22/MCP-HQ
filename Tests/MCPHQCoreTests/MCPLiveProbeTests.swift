import XCTest
@testable import MCPHQCore

final class MCPLiveProbeTests: XCTestCase {
    func testDispatchesStdioAndHTTPServersToSpecializedProbeProviders() {
        let stdioServer = ServerDefinition(
            id: "local",
            displayName: "Local",
            transport: .stdio,
            command: "fake",
            sourcePath: "/tmp/claude.json"
        )
        let httpServer = ServerDefinition(
            id: "remote",
            displayName: "Remote",
            transport: .streamableHTTP,
            url: "http://127.0.0.1:9090/mcp",
            sourcePath: "/tmp/hermes.yaml"
        )
        let sseServer = ServerDefinition(
            id: "legacy-sse",
            displayName: "Legacy SSE",
            transport: .sse,
            url: "http://127.0.0.1:9091/sse",
            sourcePath: "/tmp/gemini.json"
        )
        var stdioIDs: [String] = []
        var httpIDs: [String] = []
        let probe = MCPLiveProbe(
            stdioProbe: { servers in
                stdioIDs = servers.map(\.id)
                return servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 1, message: "stdio ok") }
            },
            httpProbe: { servers in
                httpIDs = servers.map(\.id)
                return servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 2, message: "http ok") }
            }
        )

        let results = probe.probe(servers: [stdioServer, httpServer, sseServer])

        XCTAssertEqual(stdioIDs, ["local"])
        XCTAssertEqual(httpIDs, ["remote"])
        XCTAssertEqual(results.map(\.serverID), ["local", "remote", "legacy-sse"])
        XCTAssertEqual(results[0].message, "stdio ok")
        XCTAssertEqual(results[1].message, "http ok")
        XCTAssertEqual(results[2].status, .skipped)
        XCTAssertTrue(results[2].message.contains("Legacy SSE probing is not implemented"), results[2].message)
    }
}
