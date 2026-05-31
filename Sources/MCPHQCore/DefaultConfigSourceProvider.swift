import Foundation

public struct DefaultConfigSourceProvider: Sendable {
    private let registry: AgentRegistry

    public init(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.registry = AgentRegistry.default(homeDirectory: homeDirectory)
    }

    public init(registry: AgentRegistry) {
        self.registry = registry
    }

    public func sources() -> [ConfigSource] {
        registry.sources()
    }
}
