import Foundation

public struct DefaultConfigSourceProvider: Sendable {
    private let homeDirectory: String

    public init(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.homeDirectory = homeDirectory
    }

    public func sources() -> [ConfigSource] {
        [
            ConfigSource(
                agent: .claude,
                path: path("Library/Application Support/Claude/claude_desktop_config.json")
            ),
            ConfigSource(
                agent: .gemini,
                path: path(".gemini/config/mcp_config.json")
            ),
            ConfigSource(
                agent: .hermes,
                path: path(".hermes/config.yaml")
            ),
            ConfigSource(
                agent: .cursor,
                path: path(".cursor/mcp.json")
            ),
            ConfigSource(
                agent: .windsurf,
                path: path(".codeium/windsurf/mcp_config.json")
            ),
            ConfigSource(
                agent: .continue,
                path: path(".continue/config.json")
            ),
            ConfigSource(
                agent: .goose,
                path: path(".config/goose/config.yaml")
            ),
        ]
    }

    private func path(_ relativePath: String) -> String {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(relativePath)
            .path
    }
}
