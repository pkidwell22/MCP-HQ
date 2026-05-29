import XCTest
@testable import MCPHQCore

final class ClaudeConfigParserEmptyConfigTests: XCTestCase {
    func testParseClaudeConfigWithoutMCPServersReturnsEmptyList() throws {
        let data = Data(#"{"preferences":{"sidebarMode":"expanded"}}"#.utf8)

        let servers = try ClaudeConfigParser().parse(data: data, sourcePath: "/tmp/claude.json")

        XCTAssertEqual(servers, [])
    }
}
