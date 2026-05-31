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
            sourceHealth: [
                ConfigSourceHealth(
                    source: ConfigSource(agent: .claude, path: "/tmp/claude.json"),
                    state: .parsed,
                    serverCount: 1,
                    message: "Found config • parsed 1 server"
                )
            ],
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
        XCTAssertTrue(output.contains("Sources:"))
        XCTAssertTrue(output.contains("Claude parsed: Found config • parsed 1 server"))
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
        XCTAssertNotNil(object?["sourceHealth"])
        XCTAssertNotNil(object?["issues"])
        XCTAssertNotNil(object?["processMatches"])
        XCTAssertFalse(output.contains("ghp_ab...3456"))
    }

    func testFormatterRedactsSecretsInCommandArgumentsAndURLs() throws {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "remote",
                displayName: "remote",
                transport: .streamableHTTP,
                command: "mcp-server-example",
                args: ["--token", "sk-config-secret-1234567890", "--mode", "readonly", "api_key=shortsecret"],
                url: "https://example.test/mcp?token=sk-url-secret-1234567890",
                headers: ["Authorization": "Bearer sk-header-secret-1234567890"],
                sourcePath: "/tmp/config.json"
            )],
            sources: [ConfigSource(agent: .gemini, path: "/tmp/config.json")]
        )

        let text = ScanOutputFormatter().formatText(result)
        XCTAssertTrue(text.contains("args: --token <redacted> --mode readonly api_key=<redacted>"), text)
        XCTAssertTrue(text.contains("url: https://example.test/mcp?token=<redacted>"), text)
        XCTAssertTrue(text.contains("Authorization=Bearer <redacted>"), text)
        XCTAssertFalse(text.contains("sk-config-secret"), text)
        XCTAssertFalse(text.contains("shortsecret"), text)
        XCTAssertFalse(text.contains("sk-url-secret"), text)
        XCTAssertFalse(text.contains("sk-header-secret"), text)

        let json = try ScanOutputFormatter().formatJSON(result)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.first?["args"] as? [String], ["--token", "<redacted>", "--mode", "readonly", "api_key=<redacted>"])
        XCTAssertEqual(servers.first?["url"] as? String, "https://example.test/mcp?token=<redacted>")
        XCTAssertEqual((servers.first?["headers"] as? [String: String])?["Authorization"], "Bearer <redacted>")
        XCTAssertFalse(json.contains("sk-config-secret"), json)
        XCTAssertFalse(json.contains("shortsecret"), json)
        XCTAssertFalse(json.contains("sk-url-secret"), json)
        XCTAssertFalse(json.contains("sk-header-secret"), json)
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
