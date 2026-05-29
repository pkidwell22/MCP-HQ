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
                        "GITHUB_TOKEN": "ghp_abcdefghijklmnopqrstuvwxyz123456",
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
                envBindings: ["GITHUB_TOKEN": "ghp_abcdefghijklmnopqrstuvwxyz123456"],
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
        XCTAssertFalse(output.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
    }
}
