import XCTest
@testable import MCPHQCore

final class DefaultConfigSourceProviderTests: XCTestCase {
    func testDefaultSourcesUseInjectedHomeDirectoryAndKnownAgentPaths() {
        let provider = DefaultConfigSourceProvider(homeDirectory: "/tmp/fake-home")

        let sources = provider.sources()

        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .claude,
            path: "/tmp/fake-home/Library/Application Support/Claude/claude_desktop_config.json"
        )))
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .gemini,
            path: "/tmp/fake-home/.gemini/config/mcp_config.json"
        )))
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .hermes,
            path: "/tmp/fake-home/.hermes/config.yaml"
        )))
        XCTAssertTrue(sources.contains { $0.agent == .cursor })
        XCTAssertTrue(sources.contains { $0.agent == .windsurf })
        XCTAssertTrue(sources.contains { $0.agent == .continue })
    }

    func testDefaultSourcesAreDeterministic() {
        let provider = DefaultConfigSourceProvider(homeDirectory: "/tmp/fake-home")

        XCTAssertEqual(provider.sources(), provider.sources())
    }
}
