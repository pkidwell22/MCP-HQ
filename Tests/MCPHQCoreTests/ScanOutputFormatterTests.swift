import XCTest
@testable import MCPHQCore

final class ScanOutputFormatterTests: XCTestCase {
    func testTextFormatterPrintsSafeInventoryAndIssues() {
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "github",
                    displayName: "github",
                    transport: .stdio,
                    command: "mcp-server-github",
                    args: ["--verbose"],
                    envBindings: [
                        "GITHUB_TOKEN": "ghp_ab...3456",
                        "SAFE_REFERENCE": "${SAFE_REFERENCE}",
                    ],
                    sourcePath: "/tmp/claude.json"
                ),
                ServerDefinition(
                    id: "docs",
                    displayName: "docs",
                    transport: .sse,
                    url: "http://localhost:8181/mcp",
                    sourcePath: "/tmp/remote.json"
                ),
            ],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")],
            issues: [ScanIssue(
                source: ConfigSource(agent: .gemini, path: "/tmp/bad.json"),
                severity: .error,
                message: "bad JSON"
            )],
            processes: [MCPProcessSnapshot(
                pid: 1201,
                executableName: "npx",
                commandLine: "npx -y @modelcontextprotocol/server-github --token <redacted>",
                matchReason: "mcp command pattern"
            )],
            processMatches: [ServerProcessMatch(
                serverID: "github",
                processID: 1201,
                confidence: .high,
                reason: "command and MCP-specific argument matched"
            )]
        )

        let output = ScanOutputFormatter().formatText(result)

        XCTAssertTrue(output.contains("MCP-HQ scan"))
        XCTAssertTrue(output.contains("Servers: 2"))
        XCTAssertTrue(output.contains("Processes: 1"))
        XCTAssertTrue(output.contains("Issues: 1"))
        XCTAssertTrue(output.contains("github"))
        XCTAssertTrue(output.contains("transport: stdio"))
        XCTAssertTrue(output.contains("command: mcp-server-github"))
        XCTAssertTrue(output.contains("args: --verbose"))
        XCTAssertTrue(output.contains("GITHUB_TOKEN=<redacted>"))
        XCTAssertTrue(output.contains("SAFE_REFERENCE=${SAFE_REFERENCE}"))
        XCTAssertTrue(output.contains("docs"))
        XCTAssertTrue(output.contains("transport: sse"))
        XCTAssertTrue(output.contains("url: http://localhost:8181/mcp"))
        XCTAssertTrue(output.contains("Running processes:"))
        XCTAssertTrue(output.contains("1201 npx: npx -y @modelcontextprotocol/server-github --token <redacted>"))
        XCTAssertTrue(output.contains("Process matches:"))
        XCTAssertTrue(output.contains("github -> pid 1201 (high): command and MCP-specific argument matched"))
        XCTAssertTrue(output.contains("error gemini /tmp/bad.json: bad JSON"))
        XCTAssertFalse(output.contains("ghp_ab...3456"))
    }

    func testJSONFormatterEmitsStableRedactedJSON() throws {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "github",
                displayName: "github",
                transport: .stdio,
                command: "mcp-server-github",
                envBindings: ["GITHUB_TOKEN": "ghp_ab...3456"],
                sourcePath: "/tmp/claude.json"
            )],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")],
            issues: []
        )

        let output = try ScanOutputFormatter().formatJSON(result)
        let data = try XCTUnwrap(output.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = try XCTUnwrap(object?["servers"] as? [[String: Any]])
        let firstServer = try XCTUnwrap(servers.first)
        let env = try XCTUnwrap(firstServer["envBindings"] as? [String: String])

        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        XCTAssertNotNil(object?["sources"])
        XCTAssertNotNil(object?["issues"])
        XCTAssertNotNil(object?["processMatches"])
        XCTAssertFalse(output.contains("ghp_ab...3456"))
    }

    func testFormatterPrintsProbeToolCounts() throws {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "memory",
                displayName: "memory",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                sourcePath: "/tmp/claude.json"
            )],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")],
            probeResults: [MCPProbeResult(
                serverID: "memory",
                status: .healthy,
                toolCount: 9,
                resourceCount: 2,
                resourceNames: ["Project docs", "secret-ghp_1234567890abcdef"],
                pingSucceeded: true,
                promptCount: 1,
                promptNames: ["secret-ghp_1234567890abcdef"],
                message: "capability discovery succeeded"
            )]
        )

        let text = ScanOutputFormatter().formatText(result)
        XCTAssertTrue(text.contains("probe: healthy • 9 tools • 2 resources • 1 prompt • ping ok • capability discovery succeeded"), text)

        let json = try ScanOutputFormatter().formatJSON(result)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let probes = try XCTUnwrap(object["probeResults"] as? [[String: Any]])
        XCTAssertEqual(probes.first?["serverID"] as? String, "memory")
        XCTAssertEqual(probes.first?["status"] as? String, "healthy")
        XCTAssertEqual(probes.first?["toolCount"] as? Int, 9)
        XCTAssertEqual(probes.first?["resourceCount"] as? Int, 2)
        XCTAssertEqual(probes.first?["resourceNames"] as? [String], ["Project docs", "secret-<redacted>"])
        XCTAssertEqual(probes.first?["promptCount"] as? Int, 1)
        XCTAssertEqual(probes.first?["promptNames"] as? [String], ["secret-<redacted>"])
        XCTAssertEqual(probes.first?["pingSucceeded"] as? Bool, true)
    }
}
