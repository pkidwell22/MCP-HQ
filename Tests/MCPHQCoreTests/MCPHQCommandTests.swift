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

    func testScanCorrelatesConfiguredServersWithRunningProcesses() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(processScanner: MCPProcessScanner(processProvider: {
            [RawProcessSnapshot(pid: 4201, commandLine: "npx -y @modelcontextprotocol/server-github --token ghp_ab...3456")]
        }))

        let result = try command.run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let matches = try XCTUnwrap(object["processMatches"] as? [[String: Any]])
        let firstMatch = try XCTUnwrap(matches.first)
        XCTAssertEqual(firstMatch["serverID"] as? String, "github")
        XCTAssertEqual(firstMatch["processID"] as? Int, 4201)
        XCTAssertEqual(firstMatch["confidence"] as? String, "high")
        XCTAssertFalse(result.stdout.contains("ghp_ab...3456"))
    }

    func testScanReportsMissingConfiguredCommandAsWarning() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "broken": {
              "command": "definitely-not-installed-mcp"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let warning = try XCTUnwrap(issues.first)
        XCTAssertEqual(warning["severity"] as? String, "warning")
        XCTAssertTrue((warning["message"] as? String)?.contains("Command not found for broken: definitely-not-installed-mcp") == true)
    }

    func testScanReportsMissingSensitiveEnvAsWarning() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "env": {
                "GITHUB_TOKEN": ""
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let warning = try XCTUnwrap(issues.first)
        XCTAssertEqual(warning["severity"] as? String, "warning")
        XCTAssertTrue((warning["message"] as? String)?.contains("Missing env var for github: GITHUB_TOKEN") == true)
        XCTAssertTrue((warning["message"] as? String)?.contains("Keychain") == true)
    }

    func testScanIncludesInjectedProbeResults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(probeProvider: { servers in
            servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 9, message: "tools/list succeeded") }
        })

        let result = try command.run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let probes = try XCTUnwrap(object["probeResults"] as? [[String: Any]])
        XCTAssertEqual(probes.first?["serverID"] as? String, "memory")
        XCTAssertEqual(probes.first?["toolCount"] as? Int, 9)
    }

    func testUnknownCommandReturnsUsageError() throws {
        let result = try MCPHQCommand().run(args: ["bogus"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }
}
