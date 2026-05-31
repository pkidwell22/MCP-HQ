import XCTest
@testable import MCPHQCore

final class LocalControlAPITests: XCTestCase {
    func testScanUpdatesHealthCacheAndDefaultStatusCanServeCachedCountsForFullSourceScope() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        let missingURL = tempDirectory.appendingPathComponent("missing.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let sourceProvider = DefaultConfigSourceProvider(registry: AgentRegistry(agents: [
            AgentDefinition(
                agent: .claude,
                displayName: "Claude",
                configFormat: .json,
                configPaths: [configURL.path, missingURL.path],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "test"
            )
        ]))
        let healthCacheStore = JSONHealthCacheStore(fileURL: tempDirectory.appendingPathComponent("health-cache.json"))
        let scanDate = Date(timeIntervalSince1970: 1_700_000_000)
        let router = LocalControlRouter(
            defaultSourceProvider: sourceProvider,
            healthCacheStore: healthCacheStore,
            now: { scanDate }
        )

        let scan = router.handle(LocalControlRequest(route: .scan))
        try #"{"mcpServers":{"memory":{"command":"npx"},"github":{"command":"npx"}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let status = router.handle(LocalControlRequest(route: .status))

        XCTAssertNil(scan.error)
        XCTAssertEqual(scan.scanResult?.servers.count, 1)
        XCTAssertEqual(scan.healthCache?.counts.serverCount, 1)
        XCTAssertEqual(scan.healthCache?.sourceIDs.sorted(), sourceProvider.sources().map(\.id).sorted())
        XCTAssertEqual(scan.healthCache?.scannedAt, scanDate)
        XCTAssertEqual(status.status?.serverCount, 1)
        XCTAssertEqual(status.status?.servedFromHealthCache, true)
        XCTAssertEqual(status.status?.scannedAt, scanDate)
        XCTAssertEqual(status.status?.cacheAgeSeconds, 0)
        XCTAssertEqual(status.status?.cacheFreshness, .fresh)
        XCTAssertEqual(status.status?.cacheStaleAfterSeconds, HealthCacheSnapshot.defaultStaleAfterSeconds)
        XCTAssertEqual(status.status?.cacheRefreshRecommended, false)
        XCTAssertEqual(status.healthCache, scan.healthCache)
    }

    func testDefaultStatusServesStaleHealthCacheWithRefreshMetadata() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let sourceProvider = DefaultConfigSourceProvider(registry: AgentRegistry(agents: [
            AgentDefinition(
                agent: .claude,
                displayName: "Claude",
                configFormat: .json,
                configPaths: [configURL.path],
                parserStatus: .supported,
                rendererStatus: .supported,
                launchContextNotes: "test"
            )
        ]))
        let healthCacheStore = JSONHealthCacheStore(fileURL: tempDirectory.appendingPathComponent("health-cache.json"))
        try healthCacheStore.save(HealthCacheSnapshot(
            scanStatus: .completed,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceIDs: sourceProvider.sources().map(\.id),
            includesProbes: false,
            counts: HealthSummaryCounts(serverCount: 1, sourceCount: 1, processCount: 0, issueCount: 0, warningCount: 0, errorCount: 0)
        ))
        try #"{"mcpServers":{"memory":{"command":"npx"},"github":{"command":"npx"}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter(
            defaultSourceProvider: sourceProvider,
            healthCacheStore: healthCacheStore,
            now: { Date(timeIntervalSince1970: 1_700_000_301) }
        )

        let status = router.handle(LocalControlRequest(route: .status))

        XCTAssertEqual(status.status?.serverCount, 1)
        XCTAssertEqual(status.status?.servedFromHealthCache, true)
        XCTAssertEqual(status.status?.cacheAgeSeconds, 301)
        XCTAssertEqual(status.status?.cacheFreshness, .stale)
        XCTAssertEqual(status.status?.cacheRefreshRecommended, true)
        XCTAssertEqual(status.healthCache?.counts.serverCount, 1)
    }

    func testScanServersDoctorAndStatusRoutesUseRedactedScanResults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"],
              "env": {
                "GITHUB_TOKEN": "ghp_routeSecret1234567890"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let source = ConfigSource(agent: .claude, path: configURL.path)
        let router = LocalControlRouter()

        let status = router.handle(LocalControlRequest(route: .status, source: source))
        let scan = router.handle(LocalControlRequest(route: .scan, source: source))
        let servers = router.handle(LocalControlRequest(route: .servers, source: source))
        let doctor = router.handle(LocalControlRequest(route: .doctor, source: source))

        XCTAssertEqual(status.status?.serverCount, 1)
        XCTAssertEqual(scan.scanResult?.servers.count, 1)
        XCTAssertEqual(servers.servers?.map(\.displayName), ["github"])
        XCTAssertEqual(doctor.doctorReport?.warningCount, 0)
        XCTAssertFalse(String(describing: scan).contains("ghp_routeSecret"))
        XCTAssertFalse(String(describing: servers).contains("ghp_routeSecret"))
    }

    func testScanRouteCanUseExplicitTargetSourcesForDashboardClientRefresh() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let claudeURL = tempDirectory.appendingPathComponent("claude.json")
        let codexURL = tempDirectory.appendingPathComponent("codex.toml")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: claudeURL, atomically: true, encoding: .utf8)
        try """
        [mcp_servers.github]
        command = "npx"
        args = ["-y", "@modelcontextprotocol/server-github"]
        """.write(to: codexURL, atomically: true, encoding: .utf8)
        let sources = [
            ConfigSource(agent: .claude, path: claudeURL.path),
            ConfigSource(agent: .codex, path: codexURL.path),
        ]

        let response = LocalControlRouter().handle(LocalControlRequest(route: .scan, targetSources: sources))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.scanResult?.sources, sources)
        XCTAssertEqual(Set(response.scanResult?.servers.map(\.displayName) ?? []), ["memory", "github"])
    }

    func testRuntimeExplainRouteReturnsReadOnlyExternalProcessExplanation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter(scanCoordinator: ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: {
                [RawProcessSnapshot(pid: 321, commandLine: "npx -y @modelcontextprotocol/server-memory --token ghp_runtimeAPISecret1234567890")]
            })
        ))

        let response = router.handle(LocalControlRequest(
            route: .runtimeExplain,
            source: ConfigSource(agent: .claude, path: configURL.path)
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.runtimeExplanations?.first?.ownership, .agentOwned)
        XCTAssertTrue(response.runtimeExplanations?.first?.controlSummary.contains("Read-only external runtime") == true)
        XCTAssertFalse(String(describing: response).contains("ghp_runtimeAPISecret"))
    }

    func testRuntimeStartAndStopRoutesControlOnlySupervisorTrackedHubRuntime() throws {
        let handle = LocalControlFakeRuntimeProcessHandle(pid: 5150)
        let supervisor = HubRuntimeSupervisor(
            launcher: LocalControlFakeRuntimeProcessLauncher(handle: handle),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let router = LocalControlRouter(runtimeSupervisor: supervisor)
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "/bin/echo",
            args: ["hello"],
            sourcePath: "/tmp/hub.json"
        )

        let started = router.handle(LocalControlRequest(
            route: .runtimeStart,
            server: server,
            logDirectory: logDirectory.path
        ))
        let running = try XCTUnwrap(started.runtimeInstance)
        let stopped = router.handle(LocalControlRequest(
            route: .runtimeStop,
            runtimeInstance: running
        ))

        XCTAssertNil(started.error)
        XCTAssertEqual(running.ownership, .hubOwned)
        XCTAssertEqual(running.pid, 5150)
        XCTAssertEqual(stopped.runtimeInstance?.status, .stopped)
        XCTAssertNil(stopped.runtimeInstance?.pid)
        XCTAssertTrue(handle.didTerminate)
    }

    func testRuntimeStopRouteCanUseRuntimeIDForManagedHubRuntime() throws {
        let handle = LocalControlFakeRuntimeProcessHandle(pid: 5151)
        let supervisor = HubRuntimeSupervisor(
            launcher: LocalControlFakeRuntimeProcessLauncher(handle: handle),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let router = LocalControlRouter(runtimeSupervisor: supervisor)
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "/bin/echo",
            args: ["hello"],
            sourcePath: "/tmp/hub.json"
        )

        let started = router.handle(LocalControlRequest(
            route: .runtimeStart,
            server: server,
            logDirectory: logDirectory.path
        ))
        let runtimeID = try XCTUnwrap(started.runtimeInstance?.id)
        let stopped = router.handle(LocalControlRequest(
            route: .runtimeStop,
            runtimeInstanceID: runtimeID
        ))

        XCTAssertNil(stopped.error)
        XCTAssertEqual(stopped.runtimeInstance?.id, runtimeID)
        XCTAssertEqual(stopped.runtimeInstance?.status, .stopped)
        XCTAssertTrue(handle.didTerminate)
    }

    func testRuntimeExplainIncludesPersistedHubRuntimeAndMarksMissingPIDDegraded() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        try store.upsertRuntimeInstance(RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 12345,
            ownership: .hubOwned,
            commandLine: "npx -y @modelcontextprotocol/server-memory",
            status: .healthy,
            logPath: tempDirectory.appendingPathComponent("memory.log").path
        ))
        let router = LocalControlRouter(controlPlaneStore: store)

        let response = router.handle(LocalControlRequest(route: .runtimeExplain))

        let hub = try XCTUnwrap(response.runtimeExplanations?.first { $0.runtimeInstanceID == "hub:memory" })
        XCTAssertEqual(hub.ownership, .hubOwned)
        XCTAssertEqual(hub.status, .degraded)
        XCTAssertNil(hub.pid)
        XCTAssertTrue(hub.logSummary.contains("Log tail available"))
    }

    func testRuntimeExplainAutoLocatesKnownHubLogPathFromRequestedDirectory() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let configURL = tempDirectory.appendingPathComponent("hub.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let logURL = tempDirectory.appendingPathComponent("memory-20231114221320.stdout.log")
        try "ready".write(to: logURL, atomically: true, encoding: .utf8)
        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        try store.upsertRuntimeInstance(RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 12345,
            ownership: .hubOwned,
            commandLine: "npx -y @modelcontextprotocol/server-memory",
            status: .healthy
        ))
        let router = LocalControlRouter(controlPlaneStore: store)

        let response = router.handle(LocalControlRequest(
            route: .runtimeExplain,
            source: ConfigSource(agent: .claude, path: configURL.path),
            logDirectory: tempDirectory.path
        ))

        let hub = try XCTUnwrap(response.runtimeExplanations?.first { $0.runtimeInstanceID == "hub:memory" })
        XCTAssertEqual(hub.status, .degraded)
        XCTAssertTrue(hub.logFilePath?.hasSuffix(logURL.lastPathComponent) == true)
        XCTAssertTrue(hub.logSummary.contains("Log tail available"))
    }

    func testRuntimeStopRouteRefusesExternalRuntime() {
        let response = LocalControlRouter().handle(LocalControlRequest(
            route: .runtimeStop,
            runtimeInstance: RuntimeInstance(
                id: "pid:99",
                serverID: "github",
                pid: 99,
                ownership: .agentOwned,
                commandLine: "npx github",
                status: .observed
            )
        ))

        XCTAssertTrue(response.error?.contains("not hub-owned") == true)
        XCTAssertNil(response.runtimeInstance)
    }

    func testConfigPreviewRouteRendersWithoutWritingOrExposingSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let serverSourceURL = tempDirectory.appendingPathComponent("pi.json")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_previewSecret1234567890"],
              "env": {
                "GITHUB_TOKEN": "ghp_previewSecret1234567890"
              }
            }
          }
        }
        """.write(to: serverSourceURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter()

        let response = router.handle(LocalControlRequest(
            route: .configPreview,
            source: ConfigSource(agent: .claude, path: targetURL.path),
            serverSource: ConfigSource(agent: .pi, path: serverSourceURL.path)
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.configPreview?.reparsedServerCount, 1)
        XCTAssertTrue(response.configPreview?.renderedText.contains("\"mcpServers\"") == true)
        XCTAssertTrue(response.configPreview?.renderedText.contains("<redacted>") == true)
        XCTAssertFalse(String(describing: response).contains("ghp_previewSecret"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testConfigPreviewRouteReportsMissingTarget() {
        let response = LocalControlRouter().handle(LocalControlRequest(route: .configPreview))

        XCTAssertEqual(response.error, "Missing target source for config preview")
        XCTAssertNil(response.configPreview)
    }

    func testConfigApplyRouteDefaultsToDryRunAndDoesNotExposeSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let serverSourceURL = tempDirectory.appendingPathComponent("pi.json")
        let targetURL = tempDirectory.appendingPathComponent("codex.toml")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"],
              "env": {
                "GITHUB_TOKEN": "ghp_applySecret1234567890"
              }
            }
          }
        }
        """.write(to: serverSourceURL, atomically: true, encoding: .utf8)

        let response = LocalControlRouter().handle(LocalControlRequest(
            route: .configApply,
            source: ConfigSource(agent: .codex, path: targetURL.path),
            serverSource: ConfigSource(agent: .claude, path: serverSourceURL.path)
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.configApply?.dryRun, true)
        XCTAssertEqual(response.configApply?.didWrite, false)
        XCTAssertEqual(response.configApply?.reparsedServerCount, 1)
        XCTAssertTrue(response.configApply?.renderedText.contains("github") == true)
        XCTAssertFalse(String(describing: response).contains("ghp_applySecret"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testConfigApplyRouteCanWriteWhenDryRunIsDisabled() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sourceURL = tempDirectory.appendingPathComponent("claude.json")
        let targetURL = tempDirectory.appendingPathComponent("claude-target.json")
        try #"{"mcpServers":{}}"#.write(to: targetURL, atomically: true, encoding: .utf8)
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let response = LocalControlRouter().handle(LocalControlRequest(
            route: .configApply,
            source: ConfigSource(agent: .claude, path: targetURL.path),
            serverSource: ConfigSource(agent: .claude, path: sourceURL.path),
            dryRun: false
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.configApply?.dryRun, false)
        XCTAssertEqual(response.configApply?.didWrite, true)
        XCTAssertNotNil(response.configApply?.backupPath)
        let written = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertTrue(written.contains("memory"))
    }

    func testConfigConnectAllPreviewRouteRendersMultipleTargetsWithoutWriting() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let claudeURL = tempDirectory.appendingPathComponent("claude.json")
        let cursorURL = tempDirectory.appendingPathComponent("cursor/mcp.json")
        try """
        mcp_servers:
          github:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-github"
            env:
              GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_localBulkPreview1234567890"
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let response = LocalControlRouter().handle(LocalControlRequest(
            route: .configConnectAllPreview,
            templateSource: ConfigSource(agent: .hermes, path: templateURL.path),
            targetSources: [
                ConfigSource(agent: .claude, path: claudeURL.path),
                ConfigSource(agent: .cursor, path: cursorURL.path),
            ]
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.configBulkPreview?.templateBindingCount, 2)
        XCTAssertEqual(response.configBulkPreview?.targetCount, 2)
        XCTAssertEqual(response.configBulkPreview?.changedTargetCount, 2)
        XCTAssertTrue(response.configBulkPreview?.text.contains("Config connect-all preview") == true)
        XCTAssertTrue(response.configBulkPreview?.text.contains(#"GITHUB_PERSONAL_ACCESS_TOKEN" : "${GITHUB_PERSONAL_ACCESS_TOKEN}""#) == true)
        XCTAssertFalse(String(describing: response).contains("ghp_localBulkPreview"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claudeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cursorURL.path))
    }

    func testConfigConnectAllApplyRouteDryRunDoesNotWrite() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("codex.toml")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let response = LocalControlRouter().handle(LocalControlRequest(
            route: .configConnectAllApply,
            templateSource: ConfigSource(agent: .hermes, path: templateURL.path),
            targetSources: [ConfigSource(agent: .codex, path: targetURL.path)]
        ))

        XCTAssertNil(response.error)
        XCTAssertEqual(response.configBulkApply?.dryRun, true)
        XCTAssertEqual(response.configBulkApply?.didWrite, false)
        XCTAssertEqual(response.configBulkApply?.affectedTargetCount, 1)
        XCTAssertTrue(response.configBulkApply?.text.contains("Config connect-all apply dry run") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }
}

private final class LocalControlFakeRuntimeProcessHandle: RuntimeProcessHandle {
    let processIdentifier: Int32
    var isRunning = true
    var didTerminate = false

    init(pid: Int32) {
        self.processIdentifier = pid
    }

    func terminate() {
        didTerminate = true
        isRunning = false
    }
}

private final class LocalControlFakeRuntimeProcessLauncher: RuntimeProcessLaunching {
    private let handle: LocalControlFakeRuntimeProcessHandle

    init(handle: LocalControlFakeRuntimeProcessHandle) {
        self.handle = handle
    }

    func launch(
        command: String,
        args: [String],
        environment: [String: String],
        stdoutURL: URL,
        stderrURL: URL
    ) throws -> RuntimeProcessHandle {
        handle
    }
}
