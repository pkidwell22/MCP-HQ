import XCTest
@testable import MCPHQCore

final class ConfigScannerHermesTests: XCTestCase {
    func testScannerReadsHermesConfigWithoutUnsupportedWarning() throws {
        let fixtureURL = Bundle.module.url(forResource: "hermes-config", withExtension: "yaml", subdirectory: "Fixtures")!
        let source = ConfigSource(agent: .hermes, path: fixtureURL.path)
        let scanner = ConfigScanner(configSources: [source])

        let result = scanner.scan()

        XCTAssertEqual(result.servers.map(\.displayName), ["filesystem", "github", "twozero_td"])
        XCTAssertEqual(result.sources, [source])
        XCTAssertEqual(result.issues, [])
    }
}
