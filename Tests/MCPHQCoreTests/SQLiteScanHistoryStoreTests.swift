import XCTest
@testable import MCPHQCore

final class SQLiteScanHistoryStoreTests: XCTestCase {
    func testSavePersistsQueryableHistoryRowsAndLoadsLatestResult() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .codex, path: "/tmp/config.toml")
        let server = ServerDefinition(
            id: "codex:/tmp/config.toml:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            envBindings: ["MEMORY_TOKEN": "sk-1234567890abcdef"],
            sourcePath: source.path
        )
        let process = MCPProcessSnapshot(
            pid: 4242,
            executableName: "node",
            commandLine: "node mcp-server-memory --token <redacted>",
            matchReason: "mcp command pattern",
            cpuPercent: 1.5,
            memoryBytes: 65_536
        )
        let result = ScanResult(
            servers: [server],
            sources: [source],
            sourceHealth: [ConfigSourceHealth(source: source, state: .parsed, serverCount: 1, message: "Found config")],
            issues: [ScanIssue(source: source, severity: .warning, message: "Missing env var MEMORY_TOKEN for memory")],
            processes: [process]
        )
        let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let runID = try store.save(result, scannedAt: scannedAt)

        let counts = try store.counts(forRunID: runID)
        XCTAssertEqual(counts.runCount, 1)
        XCTAssertEqual(counts.sourceCount, 1)
        XCTAssertEqual(counts.serverCount, 1)
        XCTAssertEqual(counts.findingCount, 1)
        XCTAssertEqual(counts.processSnapshotCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))

        let doctorHistory = try XCTUnwrap(store.loadDoctorReport(runID: runID))
        XCTAssertEqual(doctorHistory.runID, runID)
        XCTAssertEqual(doctorHistory.scannedAt, scannedAt)
        XCTAssertEqual(doctorHistory.reportedAt, scannedAt)
        XCTAssertEqual(doctorHistory.report, DoctorReportBuilder().build(from: result))

        let stored = try XCTUnwrap(store.loadLatest())
        XCTAssertEqual(stored.result, result)
        XCTAssertEqual(stored.scannedAt, scannedAt)
    }

    func testLoadLatestReturnsMostRecentRun() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let olderSource = ConfigSource(agent: .claude, path: "/tmp/older.json")
        let newerSource = ConfigSource(agent: .pi, path: "/tmp/newer.json")
        let older = ScanResult(servers: [], sources: [olderSource])
        let newer = ScanResult(servers: [], sources: [newerSource])

        try store.save(older, scannedAt: Date(timeIntervalSince1970: 10))
        try store.save(newer, scannedAt: Date(timeIntervalSince1970: 20))

        let latest = try XCTUnwrap(store.loadLatest())
        XCTAssertEqual(latest.result, newer)
        XCTAssertEqual(latest.scannedAt, Date(timeIntervalSince1970: 20))
    }

    func testLoadSpecificRunByID() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let firstSource = ConfigSource(agent: .claude, path: "/tmp/first.json")
        let secondSource = ConfigSource(agent: .pi, path: "/tmp/second.json")
        let first = ScanResult(servers: [], sources: [firstSource])
        let second = ScanResult(servers: [], sources: [secondSource])

        let firstRunID = try store.save(first, scannedAt: Date(timeIntervalSince1970: 10))
        _ = try store.save(second, scannedAt: Date(timeIntervalSince1970: 20))

        let loaded = try XCTUnwrap(store.load(runID: firstRunID))

        XCTAssertEqual(loaded.result, first)
        XCTAssertEqual(loaded.scannedAt, Date(timeIntervalSince1970: 10))
        XCTAssertNil(try store.load(runID: "missing-run"))
    }

    func testListRunSummariesReturnsNewestFirstWithCountsAndLimit() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: "/tmp/history.json")
        let serverA = ServerDefinition(
            id: "claude:/tmp/history.json:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let serverB = ServerDefinition(
            id: "claude:/tmp/history.json:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: source.path
        )
        let process = MCPProcessSnapshot(
            pid: 9001,
            executableName: "node",
            commandLine: "node mcp-server-memory",
            matchReason: "mcp command pattern"
        )

        let olderRunID = try store.save(ScanResult(servers: [], sources: [source]), scannedAt: Date(timeIntervalSince1970: 10))
        let middleRunID = try store.save(
            ScanResult(
                servers: [serverA],
                sources: [source],
                issues: [ScanIssue(source: source, severity: .warning, message: "Missing env var TOKEN for memory")]
            ),
            scannedAt: Date(timeIntervalSince1970: 20)
        )
        let newestRunID = try store.save(
            ScanResult(
                servers: [serverA, serverB],
                sources: [source],
                processes: [process],
                probeResults: [MCPProbeResult(serverID: serverA.id, status: .healthy, toolCount: 3, message: "ok")]
            ),
            scannedAt: Date(timeIntervalSince1970: 30)
        )

        let summaries = try store.listRunSummaries(limit: 2)

        XCTAssertEqual(summaries.map(\.runID), [newestRunID, middleRunID])
        XCTAssertFalse(summaries.map(\.runID).contains(olderRunID))
        XCTAssertEqual(summaries[0].scannedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(summaries[0].sourceCount, 1)
        XCTAssertEqual(summaries[0].serverCount, 2)
        XCTAssertEqual(summaries[0].findingCount, 0)
        XCTAssertEqual(summaries[0].processCount, 1)
        XCTAssertEqual(summaries[0].probeCount, 1)
        XCTAssertEqual(try store.listRunSummaries(limit: 0), [])
    }

    func testMigrateCreatesDatabaseAndIsIdempotent() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))

        try store.migrate()
        try store.migrate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
        XCTAssertNil(try store.loadLatest())
        XCTAssertEqual(try store.listDoctorReportSummaries(), [])
    }

    func testSaveSyncsControlPlaneAgentAndSourceBindingRows() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .cursor, path: "/tmp/cursor/mcp.json")
        let result = ScanResult(
            servers: [],
            sources: [source],
            sourceHealth: [
                ConfigSourceHealth(
                    source: source,
                    state: .missing,
                    serverCount: 0,
                    message: "Cursor config is missing"
                )
            ]
        )
        let scannedAt = Date(timeIntervalSince1970: 1_800)

        let runID = try store.save(result, scannedAt: scannedAt)

        let agents = try store.listAgentRecords()
        XCTAssertTrue(agents.contains { $0.agent == .cursor && $0.rendererStatus == .supported })
        let bindings = try store.listSourceBindings()
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].source, source)
        XCTAssertEqual(bindings[0].state, .missing)
        XCTAssertEqual(bindings[0].serverCount, 0)
        XCTAssertEqual(bindings[0].message, "Cursor config is missing")
        XCTAssertEqual(bindings[0].lastRunID, runID)
        XCTAssertEqual(bindings[0].lastSeenAt, scannedAt)
    }

    func testDesiredServerStateAndBackupsAreQueryableAndRedacted() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let plaintextSecret = "ghp_desiredStateSecret1234567890"
        let server = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": plaintextSecret],
            sourcePath: "/tmp/hermes.yaml"
        )
        let updatedAt = Date(timeIntervalSince1970: 2_000)

        try store.upsertDesiredServerStates([server], for: source, enabled: true, updatedAt: updatedAt)
        let backupID = try store.recordConfigBackup(
            source: source,
            backupPath: "/tmp/claude.json.mcphq-backup-20260530000000",
            reason: "binding apply",
            runID: "run-1",
            createdAt: updatedAt
        )

        let states = try store.listDesiredServerStates(source: source)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].source, source)
        XCTAssertEqual(states[0].serverName, "github")
        XCTAssertEqual(states[0].enabled, true)
        XCTAssertEqual(states[0].server.envBindings["GITHUB_PERSONAL_ACCESS_TOKEN"], "<redacted>")
        XCTAssertEqual(states[0].updatedAt, updatedAt)

        let backups = try store.listConfigBackups(source: source)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].backupID, backupID)
        XCTAssertEqual(backups[0].source, source)
        XCTAssertEqual(backups[0].reason, "binding apply")
        XCTAssertEqual(backups[0].runID, "run-1")

        let databaseBytes = try Data(contentsOf: store.databaseURL)
        let databaseText = String(decoding: databaseBytes, as: UTF8.self)
        XCTAssertFalse(databaseText.contains(plaintextSecret))
        XCTAssertTrue(databaseText.contains("<redacted>"))
    }

    func testRuntimeInstancesAreQueryableAndRedacted() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let instance = RuntimeInstance(
            id: "hub:github",
            serverID: "github",
            pid: 4242,
            ownership: .hubOwned,
            commandLine: "npx github --token ghp_runtimeStoreSecret1234567890",
            status: .healthy,
            logPath: "/tmp/github.stdout.log"
        )
        let updatedAt = Date(timeIntervalSince1970: 2_400)

        try store.upsertRuntimeInstance(instance, updatedAt: updatedAt)

        let records = try store.listRuntimeInstanceRecords(ownership: .hubOwned)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].instance.id, "hub:github")
        XCTAssertEqual(records[0].instance.pid, 4242)
        XCTAssertEqual(records[0].instance.status, .healthy)
        XCTAssertEqual(records[0].instance.commandLine, "npx github --token <redacted>")
        XCTAssertEqual(records[0].updatedAt, updatedAt)

        let databaseBytes = try Data(contentsOf: store.databaseURL)
        let databaseText = String(decoding: databaseBytes, as: UTF8.self)
        XCTAssertFalse(databaseText.contains("ghp_runtimeStoreSecret"))
    }

    func testBulkRollbackTransactionsArePersistedAndQueryable() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: tempDirectory.appendingPathComponent("claude.json").path)
        let createdAt = Date(timeIntervalSince1970: 3_000)
        let plan = AgentBulkConnectRollbackPlan(
            id: "rollback-1",
            createdAt: createdAt,
            targets: [
                AgentBulkConnectRollbackTarget(
                    source: source,
                    agentName: "Claude",
                    backupPath: source.path + ".mcphq-backup-20260530000000",
                    shouldDeleteCreatedFile: false
                )
            ]
        )

        try store.recordBulkRollbackTransaction(plan: plan, reason: "bulk connect 2 bindings", createdAt: createdAt)
        try store.markBulkRollbackTransaction("rollback-1", status: "rolledBack", updatedAt: Date(timeIntervalSince1970: 3_010))

        let loaded = try XCTUnwrap(store.loadBulkRollbackTransaction("rollback-1"))
        XCTAssertEqual(loaded.transactionID, "rollback-1")
        XCTAssertEqual(loaded.status, "rolledBack")
        XCTAssertEqual(loaded.reason, "bulk connect 2 bindings")
        XCTAssertEqual(loaded.plan, plan)
        XCTAssertEqual(loaded.createdAt, createdAt)

        let records = try store.listBulkRollbackTransactions()
        XCTAssertEqual(records.map(\.transactionID), ["rollback-1"])
    }

    func testConnectAllTargetProfilesArePersistedAndQueryable() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let firstUpdatedAt = Date(timeIntervalSince1970: 2_100)
        let secondUpdatedAt = Date(timeIntervalSince1970: 2_200)
        let claude = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let codex = ConfigSource(agent: .codex, path: "/tmp/config.toml")

        try store.upsertConnectAllTargetProfile(
            name: "local-dev",
            targetSources: [claude, codex, claude],
            updatedAt: firstUpdatedAt
        )

        var loaded = try XCTUnwrap(store.loadConnectAllTargetProfile(name: "local-dev"))
        XCTAssertEqual(loaded.name, "local-dev")
        XCTAssertEqual(loaded.targetSources, [claude, codex])
        XCTAssertEqual(loaded.updatedAt, firstUpdatedAt)

        try store.upsertConnectAllTargetProfile(
            name: "local-dev",
            targetSources: [codex],
            updatedAt: secondUpdatedAt
        )

        loaded = try XCTUnwrap(store.loadConnectAllTargetProfile(name: "local-dev"))
        XCTAssertEqual(loaded.targetSources, [codex])
        XCTAssertEqual(loaded.updatedAt, secondUpdatedAt)
        XCTAssertEqual(try store.listConnectAllTargetProfiles(), [loaded])
        XCTAssertNil(try store.loadConnectAllTargetProfile(name: "missing"))
    }

    func testSecretBindingsAreQueryableWithoutPersistingSecretValues() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let plaintextSecret = "ghp_secretBindingSecret1234567890"
        let server = ServerDefinition(
            id: "claude:/tmp/claude.json:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": plaintextSecret],
            sourcePath: "/tmp/claude.json"
        )
        let detected = SecretDetector().detect(in: server)
        let updatedAt = Date(timeIntervalSince1970: 2_600)

        try store.upsertSecretBindings(detected, status: "stored", updatedAt: updatedAt, validatedAt: updatedAt)

        let records = try store.listSecretBindingRecords(sourcePath: "/tmp/claude.json")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].sourcePath, "/tmp/claude.json")
        XCTAssertEqual(records[0].serverName, "github")
        XCTAssertEqual(records[0].fieldKind, .environment)
        XCTAssertEqual(records[0].fieldName, "GITHUB_TOKEN")
        XCTAssertEqual(records[0].status, "stored")
        XCTAssertEqual(records[0].updatedAt, updatedAt)
        XCTAssertEqual(records[0].validatedAt, updatedAt)

        let databaseBytes = try Data(contentsOf: store.databaseURL)
        let databaseText = String(decoding: databaseBytes, as: UTF8.self)
        XCTAssertFalse(databaseText.contains(plaintextSecret))
    }

    func testSaveListAndLoadDoctorReportHistory() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .error,
                category: .config,
                agentName: "Claude",
                sourcePath: "/tmp/claude.json",
                title: "Claude config is malformed",
                whyItMatters: "The agent may fail to load MCP servers from this config.",
                suggestedFix: "Fix the JSON syntax."
            ),
            DoctorFinding(
                severity: .warning,
                category: .server,
                agentName: "Claude",
                sourcePath: "/tmp/claude.json",
                serverID: "claude:/tmp/claude.json:github",
                serverName: "github",
                title: "Missing env var for github: GITHUB_TOKEN",
                whyItMatters: "The server likely needs a credential before it can start.",
                suggestedFix: "Set the environment variable."
            ),
            DoctorFinding(
                severity: .info,
                category: .source,
                agentName: "Pi",
                sourcePath: "/tmp/pi.json",
                title: "Pi config has no MCP servers",
                whyItMatters: "No server bindings are currently enabled there.",
                suggestedFix: "Add a server."
            ),
        ])
        let scannedAt = Date(timeIntervalSince1970: 100)
        let reportedAt = Date(timeIntervalSince1970: 200)

        let runID = try store.saveDoctorReport(report, scannedAt: scannedAt, reportedAt: reportedAt)

        let summaries = try store.listDoctorReportSummaries(limit: 5)
        XCTAssertEqual(summaries.map(\.runID), [runID])
        XCTAssertEqual(summaries.first?.scannedAt, scannedAt)
        XCTAssertEqual(summaries.first?.reportedAt, reportedAt)
        XCTAssertEqual(summaries.first?.findingCount, 3)
        XCTAssertEqual(summaries.first?.errorCount, 1)
        XCTAssertEqual(summaries.first?.warningCount, 1)
        XCTAssertEqual(summaries.first?.infoCount, 1)
        XCTAssertEqual(summaries.first?.sourceCount, 2)
        XCTAssertEqual(summaries.first?.serverCount, 1)

        let loaded = try XCTUnwrap(store.loadDoctorReport(runID: runID))
        XCTAssertEqual(loaded.runID, runID)
        XCTAssertEqual(loaded.scannedAt, scannedAt)
        XCTAssertEqual(loaded.reportedAt, reportedAt)
        XCTAssertEqual(loaded.report, report)
        XCTAssertNil(try store.loadDoctorReport(runID: "missing-run"))
    }

    func testDoctorReportHistoryRedactsSecretsAndDoesNotPersistPlaintext() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let plaintextSecret = "ghp_doctorHistorySecret1234567890"
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .warning,
                category: .server,
                agentName: "Claude",
                sourcePath: "/tmp/claude.json",
                serverID: "claude:/tmp/claude.json:github",
                serverName: "github \(plaintextSecret)",
                title: "Token value \(plaintextSecret) failed validation",
                whyItMatters: "Authorization=\(plaintextSecret) cannot be checked in.",
                suggestedFix: "Move token=\(plaintextSecret) into Keychain."
            )
        ])

        let runID = try store.saveDoctorReport(report, scannedAt: Date(timeIntervalSince1970: 300), reportedAt: Date(timeIntervalSince1970: 400))

        let loaded = try XCTUnwrap(store.loadDoctorReport(runID: runID))
        XCTAssertFalse(loaded.report.findings[0].serverName?.contains(plaintextSecret) ?? true)
        XCTAssertFalse(loaded.report.findings[0].title.contains(plaintextSecret))
        XCTAssertTrue(loaded.report.findings[0].title.contains("<redacted>"))

        let exportedJSON = try XCTUnwrap(store.exportDoctorReportJSON(runID: runID))
        XCTAssertFalse(exportedJSON.contains(plaintextSecret))
        let exportedData = try XCTUnwrap(exportedJSON.data(using: .utf8))
        let exportedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: exportedData) as? [String: Any])
        XCTAssertEqual(exportedObject["warningCount"] as? Int, 1)

        let databaseBytes = try Data(contentsOf: store.databaseURL)
        let databaseText = String(decoding: databaseBytes, as: UTF8.self)
        XCTAssertFalse(databaseText.contains(plaintextSecret))
        XCTAssertTrue(databaseText.contains("<redacted>"))
    }
}
