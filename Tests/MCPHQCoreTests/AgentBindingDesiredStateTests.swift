import XCTest
@testable import MCPHQCore

final class AgentBindingDesiredStateTests: XCTestCase {
    func testDesiredStateOverridesCurrentScanSelection() {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let pi = ConfigSource(agent: .pi, path: "/tmp/pi.json")
        let server = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/template.yaml"
        )
        let states = [
            SQLiteDesiredServerState(source: cursor, serverName: "memory", enabled: true, server: server, updatedAt: Date(timeIntervalSince1970: 10)),
            SQLiteDesiredServerState(source: claude, serverName: "memory", enabled: false, server: server, updatedAt: Date(timeIntervalSince1970: 20)),
        ]

        let index = AgentBindingDesiredStateIndex(states: states)
        let enabled = index.enabledSourceIDs(named: "Memory", currentSourceIDs: [claude.id, pi.id])

        XCTAssertEqual(enabled, [cursor.id, pi.id])
        XCTAssertEqual(index.enabledDesiredSourceIDs(named: "memory"), [cursor.id])
        XCTAssertTrue(index.hasDesiredState(named: "memory"))
    }

    func testDesiredStateCanSupplyTemplateForDesiredOnlyBinding() throws {
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let server = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: "/tmp/template.yaml"
        )
        let index = AgentBindingDesiredStateIndex(states: [
            SQLiteDesiredServerState(source: cursor, serverName: "github", enabled: true, server: server, updatedAt: Date(timeIntervalSince1970: 10))
        ])

        XCTAssertEqual(index.normalizedBindingNames, ["github"])
        XCTAssertEqual(try XCTUnwrap(index.templateServer(named: "GitHub")).displayName, "github")
        XCTAssertEqual(index.enabledSourceIDs(named: "github", currentSourceIDs: []), [cursor.id])
    }

    func testCanonicalAuthoringModelCombinesScanAndDesiredStateWithDrift() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let pi = ConfigSource(agent: .pi, path: "/tmp/pi.json")
        let memoryClaude = server(name: "Memory", source: claude)
        let githubClaude = server(name: "github", source: claude)
        let filesystemPi = server(name: "filesystem", source: pi)
        let memoryTemplate = server(name: "memory", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))
        let githubTemplate = server(name: "github", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(
                servers: [memoryClaude, githubClaude, filesystemPi],
                sources: [claude, cursor, pi]
            ),
            desiredStates: [
                SQLiteDesiredServerState(source: claude, serverName: "memory", enabled: true, server: memoryTemplate, updatedAt: Date(timeIntervalSince1970: 10)),
                SQLiteDesiredServerState(source: cursor, serverName: "memory", enabled: true, server: memoryTemplate, updatedAt: Date(timeIntervalSince1970: 11)),
                SQLiteDesiredServerState(source: claude, serverName: "github", enabled: false, server: githubTemplate, updatedAt: Date(timeIntervalSince1970: 12)),
            ]
        )

        XCTAssertEqual(model.bindingCount, 3)
        XCTAssertEqual(model.desiredEnabledCount, 2)
        XCTAssertEqual(model.observedOnlyCount, 1)
        XCTAssertEqual(model.driftCount, 2)
        XCTAssertTrue(model.summaryText.contains("3 canonical bindings"))

        let memory = try XCTUnwrap(model.bindings.first { $0.identity.normalizedName == "memory" })
        XCTAssertEqual(memory.identity.displayName, "memory")
        XCTAssertEqual(memory.desiredEnabledCount, 2)
        XCTAssertEqual(memory.driftCount, 1)
        XCTAssertEqual(binding(memory, source: claude)?.intent, .desiredEnabled)
        XCTAssertEqual(binding(memory, source: claude)?.driftStatus, .inSync)
        XCTAssertEqual(binding(memory, source: claude)?.scannedServerID, memoryClaude.id)
        XCTAssertEqual(binding(memory, source: cursor)?.intent, .desiredEnabled)
        XCTAssertEqual(binding(memory, source: cursor)?.driftStatus, .missingFromScan)
        XCTAssertFalse(binding(memory, source: cursor)?.isPresentInScan ?? true)

        let github = try XCTUnwrap(model.bindings.first { $0.identity.normalizedName == "github" })
        XCTAssertEqual(github.desiredDisabledCount, 1)
        XCTAssertEqual(binding(github, source: claude)?.intent, .desiredDisabled)
        XCTAssertEqual(binding(github, source: claude)?.driftStatus, .presentButDisabled)

        let filesystem = try XCTUnwrap(model.bindings.first { $0.identity.normalizedName == "filesystem" })
        XCTAssertEqual(filesystem.observedOnlyCount, 1)
        XCTAssertEqual(binding(filesystem, source: pi)?.intent, .observedOnly)
        XCTAssertEqual(binding(filesystem, source: pi)?.driftStatus, .observedOnly)
    }

    func testCanonicalAuthoringModelKeepsDesiredOnlyBindingIndependentOfLatestScan() throws {
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let template = server(name: "GitHub", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))
        let updatedAt = Date(timeIntervalSince1970: 20)

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [], sources: []),
            desiredStates: [
                SQLiteDesiredServerState(source: cursor, serverName: "github", enabled: true, server: template, updatedAt: updatedAt)
            ]
        )

        let github = try XCTUnwrap(model.bindings.first)
        XCTAssertEqual(github.identity.normalizedName, "github")
        XCTAssertEqual(github.identity.displayName, "GitHub")
        XCTAssertEqual(github.templateServer, template)
        XCTAssertEqual(github.sourceBindings.count, 1)
        XCTAssertEqual(github.sourceBindings.first?.source, cursor)
        XCTAssertEqual(github.sourceBindings.first?.intent, .desiredEnabled)
        XCTAssertEqual(github.sourceBindings.first?.driftStatus, .missingFromScan)
        XCTAssertEqual(github.sourceBindings.first?.desiredUpdatedAt, updatedAt)
    }

    func testCanonicalConfigManagerSnapshotSummarizesBindingDriftForUI() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let memoryClaude = server(name: "Memory", source: claude)
        let githubClaude = server(name: "github", source: claude)
        let memoryTemplate = server(name: "memory", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))
        let githubTemplate = server(name: "github", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [memoryClaude, githubClaude], sources: [claude, cursor]),
            desiredStates: [
                SQLiteDesiredServerState(source: cursor, serverName: "memory", enabled: true, server: memoryTemplate, updatedAt: Date(timeIntervalSince1970: 10)),
                SQLiteDesiredServerState(source: claude, serverName: "github", enabled: false, server: githubTemplate, updatedAt: Date(timeIntervalSince1970: 11)),
            ]
        )

        let snapshot = AgentCanonicalConfigManagerSnapshot(model: model)

        XCTAssertEqual(snapshot.bindingCount, 2)
        XCTAssertEqual(snapshot.driftCount, 2)
        XCTAssertTrue(snapshot.summaryText.contains("2 canonical bindings"))

        let memory = try XCTUnwrap(snapshot.binding(named: "Memory"))
        XCTAssertEqual(memory.summaryText, "1 desired on | 0 desired off | 1 observed only")
        XCTAssertEqual(memory.driftText, "1 drift: 1 missing")
        XCTAssertEqual(memory.enabledSourceIDs, [claude.id, cursor.id])
        XCTAssertEqual(memory.desiredStateSourceIDs, [cursor.id])
        XCTAssertEqual(memory.sourceRows.first { $0.sourceID == cursor.id }?.intentLabel, "desired on")
        XCTAssertEqual(memory.sourceRows.first { $0.sourceID == cursor.id }?.driftLabel, "missing")

        let github = try XCTUnwrap(snapshot.binding(named: "github"))
        XCTAssertEqual(github.summaryText, "0 desired on | 1 desired off | 0 observed only")
        XCTAssertEqual(github.driftText, "1 drift: 1 disabled but present")
        XCTAssertEqual(github.enabledSourceIDs, [])
        XCTAssertTrue(github.hasPersistedDesiredState)
    }

    func testCanonicalAuthoringModelDetectsPayloadDriftWithoutExposingSecrets() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let scanned = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: claude.agent, sourcePath: claude.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_scannedSecret1234567890"],
            headers: ["Authorization": "Bearer ghp_scannedSecret1234567890"],
            envBindings: ["GITHUB_TOKEN": "ghp_scannedSecret1234567890"],
            sourcePath: claude.path
        )
        let desired = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "node",
            args: ["server.js", "--token", "ghp_desiredSecret1234567890"],
            headers: ["Authorization": "Bearer keychain://MCP-HQ/github"],
            envBindings: ["GITHUB_TOKEN": "keychain://MCP-HQ/github"],
            sourcePath: "/tmp/template.yaml"
        )

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [scanned], sources: [claude]),
            desiredStates: [
                SQLiteDesiredServerState(source: claude, serverName: "github", enabled: true, server: desired, updatedAt: Date(timeIntervalSince1970: 30))
            ]
        )

        let github = try XCTUnwrap(model.bindings.first)
        let sourceBinding = try XCTUnwrap(binding(github, source: claude))
        XCTAssertEqual(sourceBinding.driftStatus, AgentCanonicalBindingDriftStatus.payloadMismatch)
        XCTAssertTrue(sourceBinding.payloadDriftDetails.contains { $0.contains("command differs") })
        XCTAssertTrue(sourceBinding.payloadDriftDetails.contains { $0.contains("args differ") })
        XCTAssertTrue(sourceBinding.payloadDriftDetails.contains { $0.contains("environment differs") })
        XCTAssertTrue(sourceBinding.payloadDriftDetails.contains { $0.contains("headers differ") })
        XCTAssertFalse(String(describing: sourceBinding).contains("ghp_scannedSecret"))
        XCTAssertFalse(String(describing: sourceBinding).contains("ghp_desiredSecret"))
    }

    func testCanonicalAuthoringModelDoesNotReportPayloadDriftForMatchingDesiredBinding() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let scanned = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: claude.agent, sourcePath: claude.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            headers: [:],
            envBindings: ["PATH": "/usr/bin:/bin"],
            sourcePath: claude.path
        )
        let desired = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            headers: [:],
            envBindings: ["PATH": "/usr/bin:/bin"],
            sourcePath: "/tmp/template.yaml"
        )

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [scanned], sources: [claude]),
            desiredStates: [
                SQLiteDesiredServerState(source: claude, serverName: "memory", enabled: true, server: desired, updatedAt: Date(timeIntervalSince1970: 40))
            ]
        )

        let memory = try XCTUnwrap(model.bindings.first)
        let sourceBinding = try XCTUnwrap(binding(memory, source: claude))
        XCTAssertEqual(sourceBinding.driftStatus, AgentCanonicalBindingDriftStatus.inSync)
        XCTAssertEqual(sourceBinding.payloadDriftDetails, [])
    }

    func testCanonicalDriftActionPlannerSuggestsDeterministicActionsForDrift() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let pi = ConfigSource(agent: .pi, path: "/tmp/pi.json")
        let template = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let githubClaude = server(name: "github", source: claude)
        let memoryTemplate = server(name: "memory", source: template)
        let githubTemplate = server(name: "github", source: template)
        let scannedSlack = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: pi.agent, sourcePath: pi.path, name: "slack"),
            displayName: "slack",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-slack", "--token", "xoxb_scannedSecret1234567890"],
            envBindings: ["SLACK_TOKEN": "xoxb_scannedSecret1234567890"],
            sourcePath: pi.path
        )
        let desiredSlack = ServerDefinition(
            id: "template:slack",
            displayName: "slack",
            transport: .stdio,
            command: "node",
            args: ["server.js", "--token", "xoxb_desiredSecret1234567890"],
            envBindings: ["SLACK_TOKEN": "keychain://MCP-HQ/slack"],
            sourcePath: template.path
        )

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [githubClaude, scannedSlack], sources: [claude, cursor, pi]),
            desiredStates: [
                SQLiteDesiredServerState(source: cursor, serverName: "memory", enabled: true, server: memoryTemplate, updatedAt: Date(timeIntervalSince1970: 10)),
                SQLiteDesiredServerState(source: claude, serverName: "github", enabled: false, server: githubTemplate, updatedAt: Date(timeIntervalSince1970: 11)),
                SQLiteDesiredServerState(source: pi, serverName: "slack", enabled: true, server: desiredSlack, updatedAt: Date(timeIntervalSince1970: 12)),
            ]
        )

        let plan = AgentCanonicalDriftActionPlanner().plan(for: model)

        XCTAssertEqual(plan.actions.map(\.kind), [
            .removeDisabledBinding,
            .restoreMissingDesiredBinding,
            .replacePayloadWithDesiredState,
        ])
        XCTAssertEqual(plan.actions.map(\.operation), [
            .bindingDraftDisable,
            .bindingDraftEnable,
            .payloadReplacementPreview,
        ])
        XCTAssertEqual(plan.lowRiskActions.map(\.kind), [.removeDisabledBinding, .restoreMissingDesiredBinding])
        XCTAssertEqual(plan.actions.map(\.normalizedName), ["github", "memory", "slack"])
        XCTAssertEqual(plan.actions(for: "Memory").first?.sourceID, cursor.id)
        XCTAssertEqual(plan.actions.first?.title, "Remove github from Claude")
        XCTAssertTrue(plan.actions[1].detailText.contains("Add the saved desired binding"))
    }

    func testCanonicalDriftActionsAreSecretSafeAndSnapshotOnlyShowsLowRiskSuggestionText() throws {
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let cursor = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let scanned = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: claude.agent, sourcePath: claude.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_scannedSecret1234567890"],
            headers: ["Authorization": "Bearer ghp_scannedSecret1234567890"],
            envBindings: ["GITHUB_TOKEN": "ghp_scannedSecret1234567890"],
            sourcePath: claude.path
        )
        let desired = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "node",
            args: ["server.js", "--token", "ghp_desiredSecret1234567890"],
            headers: ["Authorization": "Bearer keychain://MCP-HQ/github"],
            envBindings: ["GITHUB_TOKEN": "keychain://MCP-HQ/github"],
            sourcePath: "/tmp/template.yaml"
        )
        let memoryTemplate = server(name: "memory", source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"))

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [scanned], sources: [claude, cursor]),
            desiredStates: [
                SQLiteDesiredServerState(source: claude, serverName: "github", enabled: true, server: desired, updatedAt: Date(timeIntervalSince1970: 20)),
                SQLiteDesiredServerState(source: cursor, serverName: "memory", enabled: true, server: memoryTemplate, updatedAt: Date(timeIntervalSince1970: 21)),
            ]
        )

        let actions = AgentCanonicalDriftActionPlanner().suggestedActions(for: model)
        let payloadAction = try XCTUnwrap(actions.first { $0.kind == .replacePayloadWithDesiredState })
        XCTAssertEqual(payloadAction.risk, .reviewRequired)
        XCTAssertTrue(payloadAction.detailText.contains("Preview replacing this binding"))
        XCTAssertFalse(String(describing: payloadAction).contains("ghp_scannedSecret"))
        XCTAssertFalse(String(describing: payloadAction).contains("ghp_desiredSecret"))

        let snapshot = AgentCanonicalConfigManagerSnapshot(model: model)
        let githubRow = try XCTUnwrap(snapshot.binding(named: "github")?.sourceRows.first { $0.sourceID == claude.id })
        XCTAssertEqual(githubRow.suggestedAction?.kind, .replacePayloadWithDesiredState)
        XCTAssertNil(githubRow.suggestedActionText)

        let memoryRow = try XCTUnwrap(snapshot.binding(named: "memory")?.sourceRows.first { $0.sourceID == cursor.id })
        XCTAssertEqual(memoryRow.suggestedAction?.kind, .restoreMissingDesiredBinding)
        XCTAssertEqual(memoryRow.suggestedActionText, "Add memory to Cursor")
    }

    private func server(name: String, source: ConfigSource) -> ServerDefinition {
        ServerDefinition(
            id: ServerDefinition.canonicalID(agent: source.agent, sourcePath: source.path, name: name),
            displayName: name,
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-\(name.lowercased())"],
            sourcePath: source.path
        )
    }

    private func binding(_ summary: AgentCanonicalBindingSummary, source: ConfigSource) -> AgentCanonicalSourceBinding? {
        summary.sourceBindings.first { $0.source == source }
    }
}
