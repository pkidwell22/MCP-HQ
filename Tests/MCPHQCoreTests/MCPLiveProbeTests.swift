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

    func testReusesProbeResultsForSameTargetAcrossDifferentSources() {
        let claudeServer = ServerDefinition(
            id: "claude-memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/claude.json"
        )
        let codexServer = ServerDefinition(
            id: "codex-memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/codex.toml"
        )
        var probedIDs: [String] = []
        let probe = MCPLiveProbe(
            stdioProbe: { servers in
                probedIDs = servers.map(\.id)
                return servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 9, message: "memory ok") }
            },
            httpProbe: { _ in [] }
        )

        let results = probe.probe(servers: [claudeServer, codexServer])

        XCTAssertEqual(probedIDs, ["claude-memory"])
        XCTAssertEqual(results.map(\.serverID), ["claude-memory", "codex-memory"])
        XCTAssertEqual(results.map(\.status), [.healthy, .healthy])
        XCTAssertEqual(results.map(\.toolCount), [9, 9])
    }

    func testDoesNotReuseProbeResultWhenEnvironmentDiffers() {
        let first = ServerDefinition(
            id: "first-github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"],
            sourcePath: "/tmp/first.json"
        )
        let second = ServerDefinition(
            id: "second-github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": "${OTHER_GITHUB_TOKEN}"],
            sourcePath: "/tmp/second.json"
        )
        var probedIDs: [String] = []
        let probe = MCPLiveProbe(
            stdioProbe: { servers in
                probedIDs = servers.map(\.id)
                return servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 26, message: "github ok") }
            },
            httpProbe: { _ in [] }
        )

        _ = probe.probe(servers: [first, second])

        XCTAssertEqual(probedIDs, ["first-github", "second-github"])
    }
}
