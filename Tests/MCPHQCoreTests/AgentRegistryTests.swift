import XCTest
@testable import MCPHQCore

final class AgentRegistryTests: XCTestCase {
    func testDefaultRegistryIncludesActiveAndCompatibilityCodingAgents() {
        let registry = AgentRegistry.default(homeDirectory: "/tmp/home")
        let agents = registry.agents.map(\.agent)

        XCTAssertEqual(agents, [
            .antigravity,
            .pi,
            .hermes,
            .codex,
            .opencode,
            .cursor,
            .windsurf,
            .continue,
            .goose,
            .claude,
            .gemini,
        ])
        XCTAssertTrue(registry.sources().contains(ConfigSource(agent: .codex, path: "/tmp/home/.codex/config.toml")))
        XCTAssertTrue(registry.sources().contains(ConfigSource(agent: .hermes, path: "/tmp/home/.hermes/config.yaml")))
        XCTAssertTrue(registry.sources().contains(ConfigSource(agent: .opencode, path: "/tmp/home/.config/opencode/config.json")))
    }

    func testReadinessExplainsCreatableAndReadyKnownAgentConfigs() {
        let registry = AgentRegistry.default(homeDirectory: "/tmp/home")
        let codex = ConfigSource(agent: .codex, path: "/tmp/home/.codex/config.toml")

        let missing = registry.readiness(for: codex, fileExists: false)
        let existing = registry.readiness(for: codex, fileExists: true)

        XCTAssertEqual(missing.kind, .creatable)
        XCTAssertEqual(missing.label, "Can create")
        XCTAssertTrue(missing.canCreateWithBindingDraft)
        XCTAssertTrue(missing.detail.contains("TOML"))
        XCTAssertEqual(existing.kind, .ready)
        XCTAssertEqual(existing.label, "Ready")
        XCTAssertTrue(existing.canCreateWithBindingDraft)
    }

    func testReadinessExplainsUnsupportedSources() {
        let registry = AgentRegistry.default(homeDirectory: "/tmp/home")
        let source = ConfigSource(agent: .unknown, path: "/tmp/unknown.conf")

        let readiness = registry.readiness(for: source, fileExists: false)

        XCTAssertEqual(readiness.kind, .unsupported)
        XCTAssertEqual(readiness.label, "Unsupported")
        XCTAssertFalse(readiness.canCreateWithBindingDraft)
    }

    func testReadinessExplainsManualSetupWhenAuthoringIsUnavailable() {
        let registry = AgentRegistry(agents: [
            AgentDefinition(
                agent: .claude,
                displayName: "Claude",
                configFormat: .json,
                configPaths: ["/tmp/claude.json"],
                parserStatus: .supported,
                rendererStatus: .planned,
                launchContextNotes: "fixture"
            )
        ])

        let readiness = registry.readiness(for: ConfigSource(agent: .claude, path: "/tmp/claude.json"), fileExists: false)

        XCTAssertEqual(readiness.kind, .manualSetup)
        XCTAssertEqual(readiness.label, "Manual setup")
        XCTAssertFalse(readiness.canCreateWithBindingDraft)
    }
}
