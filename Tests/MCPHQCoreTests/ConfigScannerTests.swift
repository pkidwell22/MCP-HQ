import XCTest
@testable import MCPHQCore

final class ConfigScannerTests: XCTestCase {
    func testScannerReadsClaudeConfigFromExplicitPath() throws {
        let fixtureURL = Bundle.module.url(forResource: "claude-mcp", withExtension: "json", subdirectory: "Fixtures")!
        let scanner = ConfigScanner(configSources: [
            ConfigSource(agent: .claude, path: fixtureURL.path)
        ])

        let result = try scanner.scan()

        XCTAssertEqual(result.servers.count, 2)
        XCTAssertEqual(result.servers.map(\.id), ["github", "qmd"])
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources[0].agent, .claude)
        XCTAssertEqual(result.sources[0].path, fixtureURL.path)
    }
}
