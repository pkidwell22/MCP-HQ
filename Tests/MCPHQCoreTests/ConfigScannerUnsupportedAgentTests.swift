import XCTest
@testable import MCPHQCore

final class ConfigScannerUnsupportedAgentTests: XCTestCase {
    func testScannerReportsUnsupportedExistingAgentConfigAsWarning() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("mcp.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        let result = ConfigScanner(configSources: [
            ConfigSource(agent: .unknown, path: configURL.path),
        ]).scan()

        XCTAssertEqual(result.servers, [])
        XCTAssertEqual(result.sources, [ConfigSource(agent: .unknown, path: configURL.path)])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.severity, .warning)
        XCTAssertTrue(result.issues.first?.message.contains("Unsupported agent") == true)
    }
}
