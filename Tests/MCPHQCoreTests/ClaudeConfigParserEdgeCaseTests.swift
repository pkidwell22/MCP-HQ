import XCTest
@testable import MCPHQCore

final class ClaudeConfigParserEdgeCaseTests: XCTestCase {
    func testParseClaudeConfigPreservesRemoteTransportTypes() throws {
        let json = """
        {
          "mcpServers": {
            "plain": { "url": "http://127.0.0.1:3000/mcp", "transport": "http" },
            "events": { "url": "http://127.0.0.1:3001/sse", "transport": "sse" },
            "streamable": { "url": "http://127.0.0.1:3002/mcp", "transport": "streamable_http" }
          }
        }
        """.data(using: .utf8)!

        let servers = try ClaudeConfigParser().parse(data: json, sourcePath: "/tmp/mcp.json")

        XCTAssertEqual(servers.map(\.id), ["events", "plain", "streamable"])
        XCTAssertEqual(servers.first { $0.id == "plain" }?.transport, .http)
        XCTAssertEqual(servers.first { $0.id == "events" }?.transport, .sse)
        XCTAssertEqual(servers.first { $0.id == "streamable" }?.transport, .streamableHTTP)
    }

    func testParseClaudeConfigRejectsServerWithoutCommandOrURL() throws {
        let json = """
        {
          "mcpServers": {
            "broken": { "args": ["--unused"] }
          }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ClaudeConfigParser().parse(data: json, sourcePath: "/tmp/mcp.json")) { error in
            XCTAssertEqual(error as? ClaudeConfigParserError, .missingTransportTarget(serverName: "broken"))
        }
    }

    func testRedactedEnvBindingsHideLiteralSecretsButKeepReferences() {
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: [
                "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_1234567890abcdef",
                "SAFE_REFERENCE": "${GITHUB_TOKEN}",
                "MODE": "readonly"
            ],
            sourcePath: "/tmp/mcp.json"
        )

        XCTAssertEqual(server.redactedEnvBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "<redacted>")
        XCTAssertEqual(server.redactedEnvBindings["SAFE_REFERENCE"], "${GITHUB_TOKEN}")
        XCTAssertEqual(server.redactedEnvBindings["MODE"], "readonly")
    }
}
