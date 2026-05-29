import XCTest
@testable import MCPHQCore

final class DashboardStateBuilderTests: XCTestCase {
    func testBuildsDashboardSummaryRowsAndIssuesFromScanResult() {
        let claudeSource = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let hermesSource = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "github",
                    displayName: "GitHub",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-github"],
                    envBindings: [
                        "GITHUB_TOKEN": "fake-secret-token-1234567890",
                        "SAFE_REFERENCE": "${GITHUB_TOKEN}",
                    ],
                    sourcePath: claudeSource.path
                ),
                ServerDefinition(
                    id: "docs",
                    displayName: "Docs",
                    transport: .sse,
                    url: "http://localhost:8181/mcp",
                    sourcePath: hermesSource.path
                ),
            ],
            sources: [claudeSource, hermesSource],
            issues: [
                ScanIssue(source: hermesSource, severity: .warning, message: "Unsupported agent config parser: hermes")
            ]
        )

        let state = DashboardStateBuilder().build(from: result)

        XCTAssertEqual(state.summary.serverCount, 2)
        XCTAssertEqual(state.summary.sourceCount, 2)
        XCTAssertEqual(state.summary.issueCount, 1)
        XCTAssertEqual(state.summary.warningCount, 1)
        XCTAssertEqual(state.summary.errorCount, 0)
        XCTAssertEqual(state.summary.statusText, "2 servers • 2 sources • 1 warning")

        XCTAssertEqual(state.serverRows.map(\.displayName), ["Docs", "GitHub"])
        XCTAssertEqual(state.serverRows[0].connectionSummary, "sse • http://localhost:8181/mcp")
        XCTAssertEqual(state.serverRows[1].connectionSummary, "stdio • npx -y @modelcontextprotocol/server-github")
        XCTAssertEqual(state.serverRows[1].envSummary, "2 env vars")
        XCTAssertEqual(state.serverRows[1].redactedEnvBindings["GITHUB_TOKEN"], "<redacted>")
        XCTAssertEqual(state.serverRows[1].redactedEnvBindings["SAFE_REFERENCE"], "${GITHUB_TOKEN}")

        XCTAssertEqual(state.issueRows.count, 1)
        XCTAssertEqual(state.issueRows[0].agentName, "hermes")
        XCTAssertEqual(state.issueRows[0].severityLabel, "warning")
        XCTAssertEqual(state.issueRows[0].message, "Unsupported agent config parser: hermes")
    }

    func testBuildsEmptyStateWhenNoConfigsExist() {
        let state = DashboardStateBuilder().build(from: ScanResult(servers: [], sources: [], issues: []))

        XCTAssertEqual(state.summary.statusText, "No MCP configs found")
        XCTAssertEqual(state.serverRows, [])
        XCTAssertEqual(state.issueRows, [])
    }

    func testNeverExposesRawSecretValuesInDashboardRows() {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "github",
                displayName: "GitHub",
                transport: .stdio,
                command: "mcp-server-github",
                envBindings: ["GITHUB_TOKEN": "fake-secret-token-1234567890"],
                sourcePath: "/tmp/claude.json"
            )],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")]
        )

        let state = DashboardStateBuilder().build(from: result)
        let row = try! XCTUnwrap(state.serverRows.first)

        XCTAssertEqual(row.redactedEnvBindings["GITHUB_TOKEN"], "<redacted>")
        XCTAssertFalse(String(describing: state).contains("fake-secret-token-1234567890"))
    }
}
