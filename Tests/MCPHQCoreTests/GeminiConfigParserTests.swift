import XCTest
@testable import MCPHQCore

final class GeminiConfigParserTests: XCTestCase {
    func testParseGeminiConfigDiscoversEnabledStdioAndRemoteServers() throws {
        let fixtureURL = Bundle.module.url(forResource: "gemini-mcp-config", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)

        let servers = try GeminiConfigParser().parse(data: data, sourcePath: fixtureURL.path)

        XCTAssertEqual(servers.map(\.displayName), ["browserbase", "context7"])

        let remote = try XCTUnwrap(servers.first { $0.displayName == "browserbase" })
        XCTAssertEqual(remote.id, ServerDefinition.canonicalID(agent: .gemini, sourcePath: fixtureURL.path, name: "browserbase"))
        XCTAssertEqual(remote.transport, .sse)
        XCTAssertEqual(remote.url, "http://127.0.0.1:8931/mcp")
        XCTAssertNil(remote.command)
        XCTAssertEqual(remote.headers["Authorization"], "Bearer fake-secret-token-1234567890")
        XCTAssertEqual(remote.redactedHeaders["Authorization"], "<redacted>")
        XCTAssertEqual(remote.envBindings, [:])

        let context7 = try XCTUnwrap(servers.first { $0.displayName == "context7" })
        XCTAssertEqual(context7.id, ServerDefinition.canonicalID(agent: .gemini, sourcePath: fixtureURL.path, name: "context7"))
        XCTAssertEqual(context7.transport, .stdio)
        XCTAssertEqual(context7.command, "npx")
        XCTAssertEqual(context7.args, ["-y", "@upstash/context7-mcp"])
        XCTAssertEqual(context7.envBindings["CONTEXT7_API_KEY"], "fake-secret-token-1234567890")
        XCTAssertEqual(context7.redactedEnvBindings["CONTEXT7_API_KEY"], "<redacted>")
        XCTAssertEqual(context7.envBindings["SAFE_REFERENCE"], "${CONTEXT7_API_KEY}")
        XCTAssertEqual(context7.sourcePath, fixtureURL.path)
    }

    func testParseGeminiConfigAcceptsSnakeCaseMCPServersContainer() throws {
        let data = Data("""
        {
          "mcp_servers": {
            "qmd": {
              "command": "qmd",
              "args": ["mcp"]
            }
          }
        }
        """.utf8)

        let servers = try GeminiConfigParser().parse(data: data, sourcePath: "/tmp/mcp_config.json")

        XCTAssertEqual(servers.map(\.displayName), ["qmd"])
        XCTAssertEqual(servers.first?.id, ServerDefinition.canonicalID(agent: .gemini, sourcePath: "/tmp/mcp_config.json", name: "qmd"))
        XCTAssertEqual(servers.first?.command, "qmd")
        XCTAssertEqual(servers.first?.args, ["mcp"])
    }

    func testParseGeminiConfigWithoutMCPServersReturnsEmptyList() throws {
        let data = Data("{\"theme\": \"dark\"}".utf8)

        let servers = try GeminiConfigParser().parse(data: data, sourcePath: "/tmp/mcp_config.json")

        XCTAssertEqual(servers, [])
    }

    func testParseGeminiConfigRejectsEnabledServerWithoutCommandOrURL() throws {
        let data = Data("""
        {
          "mcpServers": {
            "broken": {
              "timeout": 30
            }
          }
        }
        """.utf8)

        XCTAssertThrowsError(try GeminiConfigParser().parse(data: data, sourcePath: "/tmp/mcp_config.json")) { error in
            XCTAssertEqual(error as? GeminiConfigParserError, .missingTransportTarget(serverName: "broken"))
        }
    }
}
