import XCTest
@testable import MCPHQCore

final class ClaudeConfigParserTests: XCTestCase {
    func testParseClaudeConfigDiscoversStdioServers() throws {
        let fixtureURL = Bundle.module.url(forResource: "claude-mcp", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)

        let servers = try ClaudeConfigParser().parse(data: data, sourcePath: fixtureURL.path)

        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers[0].id, "github")
        XCTAssertEqual(servers[0].displayName, "github")
        XCTAssertEqual(servers[0].transport, .stdio)
        XCTAssertEqual(servers[0].command, "npx")
        XCTAssertEqual(servers[0].args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(servers[0].envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "${GITHUB_TOKEN}")
        XCTAssertEqual(servers[0].sourcePath, fixtureURL.path)

        XCTAssertEqual(servers[1].id, "qmd")
        XCTAssertEqual(servers[1].command, "bun")
        XCTAssertEqual(servers[1].args, ["/Users/patkidwell/qmd/dist/mcp.js"])
    }
}
