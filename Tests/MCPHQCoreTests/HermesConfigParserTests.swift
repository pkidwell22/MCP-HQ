import XCTest
@testable import MCPHQCore

final class HermesConfigParserTests: XCTestCase {
    func testParseHermesConfigDiscoversEnabledStdioAndRemoteServers() throws {
        let fixtureURL = Bundle.module.url(forResource: "hermes-config", withExtension: "yaml", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)

        let servers = try HermesConfigParser().parse(data: data, sourcePath: fixtureURL.path)

        XCTAssertEqual(servers.map(\.displayName), ["filesystem", "github", "twozero_td"])

        let filesystem = try XCTUnwrap(servers.first { $0.displayName == "filesystem" })
        XCTAssertEqual(filesystem.id, ServerDefinition.canonicalID(agent: .hermes, sourcePath: fixtureURL.path, name: "filesystem"))
        XCTAssertEqual(filesystem.transport, .stdio)
        XCTAssertEqual(filesystem.command, "npx")
        XCTAssertEqual(filesystem.args, ["-y", "@modelcontextprotocol/server-filesystem", "/Users/example"])
        XCTAssertEqual(filesystem.sourcePath, fixtureURL.path)

        let github = try XCTUnwrap(servers.first { $0.displayName == "github" })
        XCTAssertEqual(github.id, ServerDefinition.canonicalID(agent: .hermes, sourcePath: fixtureURL.path, name: "github"))
        XCTAssertEqual(github.command, "npx")
        XCTAssertEqual(github.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(github.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "fake-secret-token-1234567890")
        XCTAssertEqual(github.redactedEnvBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "<redacted>")
        XCTAssertEqual(github.envBindings["SAFE_REFERENCE"], "${GITHUB_PERSONAL_ACCESS_TOKEN}")

        let remote = try XCTUnwrap(servers.first { $0.displayName == "twozero_td" })
        XCTAssertEqual(remote.id, ServerDefinition.canonicalID(agent: .hermes, sourcePath: fixtureURL.path, name: "twozero_td"))
        XCTAssertEqual(remote.transport, .http)
        XCTAssertEqual(remote.url, "http://127.0.0.1:7000/mcp")
        XCTAssertNil(remote.command)
    }

    func testParseHermesConfigWithoutMCPServersReturnsEmptyList() throws {
        let data = Data("model:\n  provider: openrouter\n".utf8)

        let servers = try HermesConfigParser().parse(data: data, sourcePath: "/tmp/config.yaml")

        XCTAssertEqual(servers, [])
    }

    func testParseHermesConfigRejectsEnabledServerWithoutCommandOrURL() throws {
        let data = Data("""
        mcp_servers:
          broken:
            timeout: 30
        """.utf8)

        XCTAssertThrowsError(try HermesConfigParser().parse(data: data, sourcePath: "/tmp/config.yaml")) { error in
            XCTAssertEqual(error as? HermesConfigParserError, .missingTransportTarget(serverName: "broken"))
        }
    }
}
