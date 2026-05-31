import XCTest
@testable import MCPHQCore

final class AgentConfigAuthoringTests: XCTestCase {
    func testPreviewBindingEnablesServerAcrossTargetAgentsWithoutWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        let codexURL = directory.appendingPathComponent("codex.toml")
        try #"{"theme":"dark","mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        try "profile = \"work\"\n".write(to: codexURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let codex = ConfigSource(agent: .codex, path: codexURL.path)
        let template = ServerDefinition(
            id: "hermes:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/hermes.yaml"
        )

        let draft = try AgentConfigAuthoringPlanner().previewBinding(
            templateServer: template,
            targetSources: [claude, codex],
            existingServers: [],
            enabledSourceIDs: Set([claude.id, codex.id])
        )

        XCTAssertEqual(draft.bindingName, "memory")
        XCTAssertEqual(draft.changedPreviews.count, 2)
        XCTAssertTrue(draft.summaryText.contains("2 enabled agents"))
        let claudePreview = try XCTUnwrap(draft.targetPreviews.first { $0.source == claude })
        XCTAssertTrue(claudePreview.preview.renderedText.contains(#""theme" : "dark""#))
        XCTAssertTrue(claudePreview.preview.renderedText.contains(#""memory""#))
        let codexPreview = try XCTUnwrap(draft.targetPreviews.first { $0.source == codex })
        XCTAssertTrue(codexPreview.preview.renderedText.contains("profile = \"work\""))
        XCTAssertTrue(codexPreview.preview.renderedText.contains("[mcp_servers.memory]"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claudeURL.path + ".mcphq-backup"))
    }

    func testPreviewBindingDisablesServerForDeselectedAgent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let existing = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: claude.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: claude.path
        )

        let draft = try AgentConfigAuthoringPlanner().previewBinding(
            templateServer: existing,
            targetSources: [claude],
            existingServers: [existing],
            enabledSourceIDs: []
        )

        let preview = try XCTUnwrap(draft.targetPreviews.first?.preview)
        XCTAssertFalse(preview.renderedText.contains(#""memory""#))
        XCTAssertEqual(preview.reparsedServers, [])
        XCTAssertEqual(draft.changedPreviews.count, 1)
    }

    func testPreviewBindingOmitsSourcesWhoseSelectionDidNotChange() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let missingCursor = ConfigSource(agent: .cursor, path: directory.appendingPathComponent("missing-cursor.json").path)
        let existing = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: claude.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: claude.path
        )

        let draft = try AgentConfigAuthoringPlanner().previewBinding(
            templateServer: existing,
            targetSources: [claude, missingCursor],
            existingServers: [existing],
            enabledSourceIDs: [claude.id]
        )

        XCTAssertEqual(draft.desiredEnabledCount, 1)
        XCTAssertEqual(draft.targetPreviews, [])
        XCTAssertEqual(draft.changedPreviews, [])
        XCTAssertTrue(draft.summaryText.contains("0 sources would change"))
    }

    func testApplyBindingWritesChangedSourcesAndCreatesBackups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        let codexURL = directory.appendingPathComponent("codex.toml")
        try #"{"mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        try "model = \"gpt-5.5\"\n".write(to: codexURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let codex = ConfigSource(agent: .codex, path: codexURL.path)
        let template = ServerDefinition(
            id: "template:filesystem",
            displayName: "filesystem",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", directory.path],
            sourcePath: "/tmp/template.yaml"
        )

        let result = try AgentConfigAuthoringPlanner().applyBinding(
            templateServer: template,
            targetSources: [claude, codex],
            existingServers: [],
            enabledSourceIDs: [claude.id, codex.id]
        )

        XCTAssertEqual(result.appliedTargets.count, 2)
        XCTAssertTrue(result.appliedTargets.allSatisfy { $0.backupPath?.contains(".mcphq-backup-") == true })
        let claudeData = try Data(contentsOf: claudeURL)
        let codexData = try Data(contentsOf: codexURL)
        XCTAssertEqual(try AgentConfigParser().parse(data: claudeData, source: claude).map(\.displayName), ["filesystem"])
        XCTAssertEqual(try AgentConfigParser().parse(data: codexData, source: codex).map(\.displayName), ["filesystem"])
        XCTAssertTrue(String(data: codexData, encoding: .utf8)?.contains("model = \"gpt-5.5\"") == true)
    }

    func testApplyBindingCanCreateMissingKnownAgentConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursor = ConfigSource(agent: .cursor, path: directory.appendingPathComponent("cursor/mcp.json").path)
        let template = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/template.yaml"
        )

        let result = try AgentConfigAuthoringPlanner().applyBinding(
            templateServer: template,
            targetSources: [cursor],
            existingServers: [],
            enabledSourceIDs: [cursor.id]
        )

        XCTAssertEqual(result.appliedTargets.count, 1)
        XCTAssertNil(result.appliedTargets.first?.backupPath)
        let data = try Data(contentsOf: URL(fileURLWithPath: cursor.path))
        XCTAssertEqual(try AgentConfigParser().parse(data: data, source: cursor).map(\.displayName), ["memory"])
    }

    func testApplyBindingRecordsDesiredStateAndBackupsWhenStoreIsProvided() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let store = SQLiteScanHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite3"))
        let timestamp = Date(timeIntervalSince1970: 42)
        let template = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_authoringSecret1234567890"],
            sourcePath: "/tmp/template.yaml"
        )

        _ = try AgentConfigAuthoringPlanner(controlPlaneStore: store, now: { timestamp }).applyBinding(
            templateServer: template,
            targetSources: [claude],
            existingServers: [],
            enabledSourceIDs: [claude.id]
        )

        let desiredStates = try store.listDesiredServerStates(source: claude)
        XCTAssertEqual(desiredStates.count, 1)
        XCTAssertEqual(desiredStates[0].serverName, "github")
        XCTAssertTrue(desiredStates[0].enabled)
        XCTAssertEqual(desiredStates[0].updatedAt, timestamp)
        XCTAssertEqual(desiredStates[0].server.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "<redacted>")

        let backups = try store.listConfigBackups(source: claude)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].source, claude)
        XCTAssertEqual(backups[0].reason, "enable github binding")
        XCTAssertEqual(backups[0].createdAt, timestamp)
    }

    func testBulkPreviewConnectAllCreatesOnePreviewPerSelectedSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        let cursorURL = directory.appendingPathComponent("cursor/mcp.json")
        try #"{"theme":"dark","mcpServers":{"memory":{"command":"old-memory"}}}"#
            .write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let cursor = ConfigSource(agent: .cursor, path: cursorURL.path)
        let hermes = ConfigSource(agent: .hermes, path: directory.appendingPathComponent("hermes.yaml").path)
        let templates = [
            ServerDefinition(
                id: "hermes:filesystem",
                displayName: "filesystem",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", directory.path],
                sourcePath: hermes.path
            ),
            ServerDefinition(
                id: "hermes:memory",
                displayName: "memory",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                sourcePath: hermes.path
            ),
        ]
        let existingMemory = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: claude.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "old-memory",
            sourcePath: claude.path
        )

        let draft = try AgentBulkConfigAuthoringPlanner().previewConnectAll(
            templateServers: templates,
            templateSource: hermes,
            targetSources: [claude, cursor],
            existingServers: [existingMemory],
            enabledSourceIDs: [claude.id, cursor.id]
        )

        XCTAssertEqual(draft.templateSource, hermes)
        XCTAssertEqual(draft.templateBindingCount, 2)
        XCTAssertEqual(draft.targetPreviews.count, 2)
        XCTAssertEqual(draft.changedPreviews.count, 2)
        XCTAssertTrue(draft.summaryText.contains("2 bindings from Hermes"))
        let claudePreview = try XCTUnwrap(draft.targetPreviews.first { $0.source == claude })
        XCTAssertTrue(claudePreview.preview.renderedText.contains(#""theme" : "dark""#))
        XCTAssertTrue(claudePreview.preview.renderedText.contains(#""filesystem""#))
        XCTAssertTrue(claudePreview.preview.renderedText.contains(#""memory""#))
        XCTAssertFalse(claudePreview.preview.renderedText.contains("old-memory"))
        let cursorPreview = try XCTUnwrap(draft.targetPreviews.first { $0.source == cursor })
        XCTAssertEqual(cursorPreview.preview.reparsedServers.map(\.displayName), ["filesystem", "memory"])
    }

    func testBulkPreviewConnectAllPreservesTargetKeychainEnvReferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hermesURL = directory.appendingPathComponent("hermes.yaml")
        let hermes = ConfigSource(agent: .hermes, path: hermesURL.path)
        let codex = ConfigSource(agent: .codex, path: directory.appendingPathComponent("codex.toml").path)
        let targetServerID = ServerDefinition.canonicalID(agent: .hermes, sourcePath: hermes.path, name: "github")
        let reference = KeychainSecretReference.stable(
            serverID: targetServerID,
            secretName: "GITHUB_PERSONAL_ACCESS_TOKEN"
        )
        try """
        mcp_servers:
          github:
            command: old-github
            env:
              GITHUB_PERSONAL_ACCESS_TOKEN: "\(reference.configValue)"
        """
        .write(to: hermesURL, atomically: true, encoding: .utf8)
        let template = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .codex, sourcePath: codex.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"],
            sourcePath: codex.path
        )
        let existing = ServerDefinition(
            id: targetServerID,
            displayName: "github",
            transport: .stdio,
            command: "old-github",
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": reference.configValue],
            sourcePath: hermes.path
        )

        let draft = try AgentBulkConfigAuthoringPlanner().previewConnectAll(
            templateServers: [template],
            templateSource: codex,
            targetSources: [hermes],
            existingServers: [existing],
            enabledSourceIDs: [hermes.id]
        )

        let preview = try XCTUnwrap(draft.targetPreviews.first)
        let github = try XCTUnwrap(preview.serversAfterChange.first { $0.displayName == "github" })
        XCTAssertEqual(github.command, "npx")
        XCTAssertEqual(github.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(github.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], reference.configValue)
        XCTAssertEqual(
            preview.preview.reparsedServers.first { $0.displayName == "github" }?.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"],
            reference.configValue
        )
        XCTAssertTrue(preview.preview.renderedText.contains(reference.configValue))
        XCTAssertFalse(preview.preview.renderedText.contains(#""${GITHUB_PERSONAL_ACCESS_TOKEN}""#))
    }

    func testBulkApplyConnectAllWritesEachSourceOnceAndRecordsBreadcrumbs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        let cursorURL = directory.appendingPathComponent("cursor/mcp.json")
        try #"{"mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let cursor = ConfigSource(agent: .cursor, path: cursorURL.path)
        let hermes = ConfigSource(agent: .hermes, path: directory.appendingPathComponent("hermes.yaml").path)
        let store = SQLiteScanHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite3"))
        let timestamp = Date(timeIntervalSince1970: 111)
        let templates = [
            ServerDefinition(
                id: "hermes:github",
                displayName: "github",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_bulkSecret1234567890"],
                sourcePath: hermes.path
            ),
            ServerDefinition(
                id: "hermes:memory",
                displayName: "memory",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                sourcePath: hermes.path
            ),
        ]

        let result = try AgentBulkConfigAuthoringPlanner(controlPlaneStore: store, now: { timestamp }).applyConnectAll(
            templateServers: templates,
            templateSource: hermes,
            targetSources: [claude, cursor],
            existingServers: [],
            enabledSourceIDs: [claude.id, cursor.id]
        )

        XCTAssertEqual(result.templateBindingCount, 2)
        XCTAssertEqual(result.appliedTargets.count, 2)
        XCTAssertEqual(result.appliedTargets.first { $0.source == claude }?.backupPath?.contains(".mcphq-backup-"), true)
        XCTAssertNil(result.appliedTargets.first { $0.source == cursor }?.backupPath)

        let claudeServers = try AgentConfigParser().parse(data: Data(contentsOf: claudeURL), source: claude)
        let cursorServers = try AgentConfigParser().parse(data: Data(contentsOf: cursorURL), source: cursor)
        XCTAssertEqual(claudeServers.map(\.displayName), ["github", "memory"])
        XCTAssertEqual(cursorServers.map(\.displayName), ["github", "memory"])
        XCTAssertEqual(claudeServers.first { $0.displayName == "github" }?.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "${GITHUB_PERSONAL_ACCESS_TOKEN}")

        let claudeDesired = try store.listDesiredServerStates(source: claude)
        let cursorDesired = try store.listDesiredServerStates(source: cursor)
        XCTAssertEqual(claudeDesired.map(\.serverName).sorted(), ["github", "memory"])
        XCTAssertEqual(cursorDesired.map(\.serverName).sorted(), ["github", "memory"])
        XCTAssertTrue(claudeDesired.allSatisfy { $0.enabled && $0.updatedAt == timestamp })
        XCTAssertEqual(try store.listConfigBackups(source: claude).first?.reason, "bulk connect 2 bindings")
        XCTAssertEqual(try store.listConfigBackups(source: cursor), [])
        XCTAssertEqual(result.verificationReport?.configuredCount, 2)
        XCTAssertEqual(result.verificationReport?.targets.map(\.status), [.configured, .configured])
        XCTAssertTrue(result.verificationReport?.targets.allSatisfy { $0.presentBindingCount == 2 } == true)
        let claudeVerification = try XCTUnwrap(result.verificationReport?.targets.first { $0.source == claude })
        XCTAssertEqual(claudeVerification.bindingVerifications.map(\.bindingName), ["github", "memory"])
        XCTAssertEqual(claudeVerification.bindingVerifications.map(\.configStatus), [.configured, .configured])
        XCTAssertEqual(claudeVerification.bindingVerifications.map(\.probeStatus), [.notRun, .notRun])
        XCTAssertEqual(result.rollbackPlan?.targets.count, 2)
        XCTAssertEqual(result.rollbackPlan?.targets.first { $0.source == claude }?.shouldDeleteCreatedFile, false)
        XCTAssertEqual(result.rollbackPlan?.targets.first { $0.source == cursor }?.shouldDeleteCreatedFile, true)
    }

    func testBulkConnectRollbackRestoresExistingAndDeletesCreatedTargets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        let cursorURL = directory.appendingPathComponent("cursor/mcp.json")
        let originalClaude = #"{"mcpServers":{"old":{"command":"old-runner"}}}"#
        try originalClaude.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let cursor = ConfigSource(agent: .cursor, path: cursorURL.path)
        let hermes = ConfigSource(agent: .hermes, path: directory.appendingPathComponent("hermes.yaml").path)
        let template = ServerDefinition(
            id: "hermes:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: hermes.path
        )
        let planner = AgentBulkConfigAuthoringPlanner()

        let result = try planner.applyConnectAll(
            templateServers: [template],
            templateSource: hermes,
            targetSources: [claude, cursor],
            existingServers: [],
            enabledSourceIDs: [claude.id, cursor.id]
        )
        let rollbackPlan = try XCTUnwrap(result.rollbackPlan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cursor.path))
        XCTAssertTrue(try String(contentsOf: claudeURL, encoding: .utf8).contains("memory"))

        let rollback = try planner.rollbackConnectAll(rollbackPlan)

        XCTAssertEqual(rollback.restoredTargets.count, 2)
        XCTAssertEqual(try String(contentsOf: claudeURL, encoding: .utf8), originalClaude)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cursor.path))
    }

    func testBulkApplyConnectAllRejectsStalePreviewSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let hermes = ConfigSource(agent: .hermes, path: directory.appendingPathComponent("hermes.yaml").path)
        let template = ServerDefinition(
            id: "hermes:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: hermes.path
        )
        let planner = AgentBulkConfigAuthoringPlanner()
        let draft = try planner.previewConnectAll(
            templateServers: [template],
            templateSource: hermes,
            targetSources: [claude],
            existingServers: [],
            enabledSourceIDs: [claude.id]
        )

        try #"{"mcpServers":{"other":{"command":"other"}}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try planner.applyConnectAll(
            templateServers: [template],
            templateSource: hermes,
            targetSources: [claude],
            existingServers: [],
            enabledSourceIDs: [claude.id],
            expectedFileSnapshots: draft.fileSnapshotsByPath
        )) { error in
            XCTAssertEqual(error as? AgentConfigAuthoringError, .staleTargetSource(claude.path))
        }

        let written = try String(contentsOf: claudeURL, encoding: .utf8)
        XCTAssertTrue(written.contains("other"))
        XCTAssertFalse(written.contains("memory"))
    }

    func testBulkConnectVerifierReportsMissingBindingsAfterExternalDrift() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx"}}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let templates = [
            ServerDefinition(
                id: "template:github",
                displayName: "github",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                sourcePath: "/tmp/template.yaml"
            ),
            ServerDefinition(
                id: "template:memory",
                displayName: "memory",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                sourcePath: "/tmp/template.yaml"
            ),
        ]

        let report = AgentBulkConnectVerifier().verify(templateServers: templates, targetSources: [claude])

        XCTAssertEqual(report.templateBindingCount, 2)
        XCTAssertEqual(report.configuredCount, 0)
        XCTAssertEqual(report.targets.first?.status, .missingBindings)
        XCTAssertEqual(report.targets.first?.presentBindingCount, 1)
        XCTAssertEqual(report.targets.first?.missingBindingNames, ["github"])
        XCTAssertEqual(report.targets.first?.bindingVerifications.map(\.bindingName), ["github", "memory"])
        XCTAssertEqual(report.targets.first?.bindingVerifications.map(\.configStatus), [.missingBinding, .configured])
        XCTAssertEqual(report.targets.first?.bindingVerifications.map(\.probeStatus), [.unavailable, .notRun])
    }

    func testBulkConnectVerifierCanAttachProbeEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeURL = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx"}}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)
        let claude = ConfigSource(agent: .claude, path: claudeURL.path)
        let template = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            sourcePath: "/tmp/template.yaml"
        )
        let targetServerID = ServerDefinition.canonicalID(agent: .claude, sourcePath: claude.path, name: "memory")

        let report = AgentBulkConnectVerifier().verify(
            templateServers: [template],
            targetSources: [claude],
            probeResults: [
                MCPProbeResult(serverID: targetServerID, status: .healthy, toolCount: 2, message: "tools/list succeeded")
            ]
        )

        XCTAssertEqual(report.configuredCount, 1)
        XCTAssertEqual(report.probeHealthyTargetCount, 1)
        XCTAssertEqual(report.probeSummaryText, "1 of 1 target source passed live probe verification")
        XCTAssertEqual(report.targets.first?.probeStatus, .healthy)
        XCTAssertEqual(report.targets.first?.healthyProbeCount, 1)
        XCTAssertEqual(report.targets.first?.probeMessage, "Live probes: 1 healthy, 0 warning, 0 error, 0 skipped, 0 missing of 1 expected binding.")
        XCTAssertEqual(report.targets.first?.bindingVerifications.first?.configStatus, .configured)
        XCTAssertEqual(report.targets.first?.bindingVerifications.first?.probeStatus, .probeable)
        XCTAssertEqual(
            AgentBulkConnectVerificationMatrixFormatter.markdownTable(for: report),
            """
            | Target source | Binding | Config verification | Live probe |
            | --- | --- | --- | --- |
            | Claude \(claude.path) | memory | configured | probeable |
            """
        )
    }

    func testBulkConnectVerificationMatrixRedactsSecretsAndUsesHonestLabels() throws {
        let secretPath = "/tmp/token=ghp_matrixSecret1234567890/config.json"
        let source = ConfigSource(agent: .claude, path: secretPath)
        let report = AgentBulkConnectVerificationReport(
            templateBindingCount: 1,
            targets: [
                AgentBulkConnectTargetVerification(
                    source: source,
                    agentName: "Claude",
                    status: .configured,
                    expectedBindingCount: 1,
                    presentBindingCount: 1,
                    missingBindingNames: [],
                    message: "configured",
                    bindingVerifications: [
                        AgentBulkConnectBindingVerification(
                            bindingName: "secret-token=ghp_bindingSecret1234567890",
                            configStatus: .configured,
                            probeStatus: .probeable,
                            probeMessage: "token=ghp_probeSecret1234567890"
                        )
                    ]
                )
            ]
        )

        let matrix = AgentBulkConnectVerificationMatrixFormatter.markdownTable(for: report)

        XCTAssertTrue(matrix.contains("configured"))
        XCTAssertTrue(matrix.contains("probeable"))
        XCTAssertFalse(matrix.localizedCaseInsensitiveContains("loaded"))
        XCTAssertFalse(matrix.contains("ghp_matrixSecret1234567890"))
        XCTAssertFalse(matrix.contains("ghp_bindingSecret1234567890"))
        XCTAssertFalse(matrix.contains("ghp_probeSecret1234567890"))
    }
}
