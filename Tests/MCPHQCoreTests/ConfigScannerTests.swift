import XCTest
@testable import MCPHQCore

final class ConfigScannerTests: XCTestCase {
    func testScannerReadsClaudeConfigFromExplicitPath() throws {
        let fixtureURL = Bundle.module.url(forResource: "claude-mcp", withExtension: "json", subdirectory: "Fixtures")!
        let scanner = ConfigScanner(configSources: [
            ConfigSource(agent: .claude, path: fixtureURL.path)
        ])

        let result = scanner.scan()

        XCTAssertEqual(result.servers.count, 2)
        XCTAssertEqual(result.servers.map(\.displayName), ["github", "qmd"])
        XCTAssertEqual(result.servers.map(\.id), [
            ServerDefinition.canonicalID(agent: .claude, sourcePath: fixtureURL.path, name: "github"),
            ServerDefinition.canonicalID(agent: .claude, sourcePath: fixtureURL.path, name: "qmd"),
        ])
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources[0].agent, .claude)
        XCTAssertEqual(result.sources[0].path, fixtureURL.path)
    }

    func testScannerProducesSourceScopedIDsForDuplicateServerNames() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let claudeURL = temporaryDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }
          }
        }
        """.write(to: claudeURL, atomically: true, encoding: .utf8)
        let hermesURL = temporaryDirectory.appendingPathComponent("hermes.yaml")
        try """
        mcp_servers:
          github:
            command: npx
            args:
              - -y
              - @modelcontextprotocol/server-github
        """.write(to: hermesURL, atomically: true, encoding: .utf8)

        let result = ConfigScanner(configSources: [
            ConfigSource(agent: .claude, path: claudeURL.path),
            ConfigSource(agent: .hermes, path: hermesURL.path),
        ]).scan()

        XCTAssertEqual(result.servers.map(\.displayName), ["github", "github"])
        XCTAssertEqual(Set(result.servers.map(\.id)).count, 2)
        XCTAssertEqual(result.servers.map(\.id), [
            ServerDefinition.canonicalID(agent: .claude, sourcePath: claudeURL.path, name: "github"),
            ServerDefinition.canonicalID(agent: .hermes, sourcePath: hermesURL.path, name: "github"),
        ])
    }

    func testScannerReportsSourceHealthForParsedMissingAndNoServerConfigs() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let parsedURL = temporaryDirectory.appendingPathComponent("parsed.json")
        let emptyURL = temporaryDirectory.appendingPathComponent("empty.json")
        let missingURL = temporaryDirectory.appendingPathComponent("missing.json")
        try """
        {
          "mcpServers": {
            "github": { "command": "npx" }
          }
        }
        """.write(to: parsedURL, atomically: true, encoding: .utf8)
        try #"{"mcpServers":{}}"#.write(to: emptyURL, atomically: true, encoding: .utf8)

        let result = ConfigScanner(configSources: [
            ConfigSource(agent: .cursor, path: parsedURL.path),
            ConfigSource(agent: .cursor, path: emptyURL.path),
            ConfigSource(agent: .cursor, path: missingURL.path),
        ]).scan()

        XCTAssertEqual(result.sourceHealth.map(\.state), [.parsed, .noServers, .missing])
        XCTAssertEqual(result.sourceHealth.map(\.serverCount), [1, 0, 0])
        XCTAssertEqual(result.sources.map(\.path), [parsedURL.path, emptyURL.path])
    }
}
