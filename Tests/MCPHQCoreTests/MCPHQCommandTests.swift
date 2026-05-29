import XCTest
@testable import MCPHQCore

final class MCPHQCommandTests: XCTestCase {
    func testScanSourcePrintsParsedClaudeFixture() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "claude-mcp",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))

        let result = try MCPHQCommand().run(args: ["scan", "--source", "claude:\(fixture.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ scan"))
        XCTAssertTrue(result.stdout.contains("Servers: 2"))
        XCTAssertTrue(result.stdout.contains("github"))
        XCTAssertTrue(result.stdout.contains("qmd"))
        XCTAssertEqual(result.stderr, "")
    }

    func testScanJSONEmitsValidRedactedJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "mcp-server-github",
              "env": {
                "GITHUB_TOKEN": "ghp_abcd1234secretvalue"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["servers"] as? [[String: Any]])
        let firstServer = try XCTUnwrap(servers.first)
        let env = try XCTUnwrap(firstServer["envBindings"] as? [String: String])
        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        XCTAssertFalse(result.stdout.contains("ghp_abcd1234secretvalue"))
    }

    func testScanMalformedConfigReportsIssueAndExitsSuccessfully() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("bad.json")
        try "{ bad json".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Servers: 0"))
        XCTAssertTrue(result.stdout.contains("Issues: 1"))
        XCTAssertTrue(result.stdout.contains("error claude \(configURL.path):"))
    }

    func testUnknownCommandReturnsUsageError() throws {
        let result = try MCPHQCommand().run(args: ["bogus"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }
}
