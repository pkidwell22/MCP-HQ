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
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .antigravity,
            path: "/tmp/fake-home/.gemini/antigravity/mcp_config.json"
        )))
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .pi,
            path: "/tmp/fake-home/.config/mcp/mcp.json"
        )))
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .codex,
            path: "/tmp/fake-home/.codex/config.toml"
        )))
        XCTAssertTrue(sources.contains(ConfigSource(
            agent: .opencode,
            path: "/tmp/fake-home/.config/opencode/opencode.json"
        )))
        XCTAssertTrue(sources.contains { $0.agent == .cursor })
        XCTAssertTrue(sources.contains { $0.agent == .windsurf })
        XCTAssertTrue(sources.contains { $0.agent == .continue })
        XCTAssertTrue(sources.contains { $0.agent == .goose })
    }

    func testDefaultSourcesAreDeterministic() {
        let provider = DefaultConfigSourceProvider(homeDirectory: "/tmp/fake-home")

        XCTAssertEqual(provider.sources(), provider.sources())
    }
}
