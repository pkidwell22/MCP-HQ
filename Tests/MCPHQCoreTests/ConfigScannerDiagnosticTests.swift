import XCTest
@testable import MCPHQCore

final class ConfigScannerDiagnosticTests: XCTestCase {
    func testMalformedClaudeJSONReportsLineAndColumn() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("bad-claude.json")
        try """
        {
          "mcpServers": {
            "github": { "command": "npx"
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = ConfigScanner(configSources: [
            ConfigSource(agent: .claude, path: configURL.path)
        ]).scan()

        XCTAssertEqual(result.servers, [])
        XCTAssertEqual(result.sources, [])
        let issue = try XCTUnwrap(result.issues.first)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertTrue(issue.message.contains("Invalid JSON"), issue.message)
        XCTAssertTrue(issue.message.contains("line"), issue.message)
        XCTAssertTrue(issue.message.contains("column"), issue.message)
        XCTAssertFalse(issue.message.contains("around line"), issue.message)
    }

    func testMalformedHermesYAMLReportsLineNumber() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("bad-hermes.yaml")
        try """
        mcp_servers:
        \tgithub:
            command: npx
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = ConfigScanner(configSources: [
            ConfigSource(agent: .hermes, path: configURL.path)
        ]).scan()

        XCTAssertEqual(result.servers, [])
        XCTAssertEqual(result.sources, [])
        let issue = try XCTUnwrap(result.issues.first)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.message, "Invalid YAML at line 2: tabs are not supported for indentation; use spaces.")
    }
}
