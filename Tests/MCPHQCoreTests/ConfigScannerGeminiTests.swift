import XCTest
@testable import MCPHQCore

final class ConfigScannerGeminiTests: XCTestCase {
    func testScannerReadsGeminiConfigWithoutUnsupportedWarning() throws {
        let fixtureURL = Bundle.module.url(forResource: "gemini-mcp-config", withExtension: "json", subdirectory: "Fixtures")!
        let source = ConfigSource(agent: .gemini, path: fixtureURL.path)
        let scanner = ConfigScanner(configSources: [source])

        let result = scanner.scan()

        XCTAssertEqual(result.servers.map(\.id), ["browserbase", "context7"])
        XCTAssertEqual(result.sources, [source])
        XCTAssertEqual(result.issues, [])
    }
}
