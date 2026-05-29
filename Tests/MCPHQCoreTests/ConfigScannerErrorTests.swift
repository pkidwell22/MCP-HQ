import XCTest
@testable import MCPHQCore

final class ConfigScannerErrorTests: XCTestCase {
    func testScannerContinuesAfterMalformedSourceAndReturnsIssue() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let badURL = temporaryDirectory.appendingPathComponent("bad.json")
        try "{ invalid json".write(to: badURL, atomically: true, encoding: .utf8)

        let goodURL = Bundle.module.url(forResource: "claude-mcp", withExtension: "json", subdirectory: "Fixtures")!
        let scanner = ConfigScanner(configSources: [
            ConfigSource(agent: .claude, path: badURL.path),
            ConfigSource(agent: .claude, path: goodURL.path)
        ])

        let result = scanner.scan()

        XCTAssertEqual(result.servers.map(\.id), ["github", "qmd"])
        XCTAssertEqual(result.sources, [ConfigSource(agent: .claude, path: goodURL.path)])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].source, ConfigSource(agent: .claude, path: badURL.path))
        XCTAssertEqual(result.issues[0].severity, .error)
    }
}
