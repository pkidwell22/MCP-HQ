import XCTest
@testable import MCPHQCore

final class RuntimeLifecycleTests: XCTestCase {
    func testAgentOwnedRuntimeIsReadOnlyAndRedacted() {
        let instance = RuntimeInstance(
            id: "pid:42",
            serverID: "github",
            pid: 42,
            ownership: .agentOwned,
            commandLine: "npx mcp-server --token ghp_runtimeSecret1234567890",
            status: .observed,
            lastError: "authorization=sk-runtimeSecret1234567890"
        )

        let explanation = RuntimeLifecycleExplainer().explain(instance: instance)

        XCTAssertEqual(instance.commandLine, "npx mcp-server --token <redacted>")
        XCTAssertEqual(instance.lastError, "authorization=<redacted>")
        XCTAssertEqual(explanation.ownership, .agentOwned)
        XCTAssertTrue(explanation.controlSummary.contains("Read-only external runtime"))
        XCTAssertTrue(explanation.logSummary.contains("No MCP-HQ log capture"))
        XCTAssertTrue(explanation.capabilities.allSatisfy { !$0.isAvailable })
        XCTAssertTrue(explanation.capabilities.allSatisfy { $0.reason.contains("owned by its agent") })
    }

    func testHubOwnedLifecycleCapabilitiesReflectStatus() {
        let stopped = RuntimeInstance(
            id: "server:memory",
            serverID: "memory",
            ownership: .hubOwned,
            commandLine: "npx @modelcontextprotocol/server-memory",
            status: .stopped,
            logPath: "/tmp/memory.log"
        )
        let running = RuntimeInstance(
            id: "server:memory",
            serverID: "memory",
            pid: 1201,
            ownership: .hubOwned,
            commandLine: "npx @modelcontextprotocol/server-memory",
            status: .healthy,
            logPath: "/tmp/memory.log"
        )

        let stoppedExplanation = RuntimeLifecycleExplainer().explain(instance: stopped)
        let runningExplanation = RuntimeLifecycleExplainer().explain(instance: running)

        XCTAssertEqual(stoppedExplanation.capabilities.first { $0.action == .start }?.isAvailable, true)
        XCTAssertEqual(stoppedExplanation.capabilities.first { $0.action == .stop }?.isAvailable, false)
        XCTAssertEqual(runningExplanation.capabilities.first { $0.action == .start }?.isAvailable, false)
        XCTAssertEqual(runningExplanation.capabilities.first { $0.action == .stop }?.isAvailable, true)
        XCTAssertEqual(runningExplanation.capabilities.first { $0.action == .restart }?.isAvailable, true)
        XCTAssertEqual(runningExplanation.logSummary, "Log tail available: /tmp/memory.log")
    }

    func testExplainsScanResultProcessesWithMatchedOwnership() {
        let result = ScanResult(
            servers: [ServerDefinition(id: "github", displayName: "GitHub", transport: .stdio, command: "npx", sourcePath: "/tmp/claude.json")],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")],
            processes: [
                MCPProcessSnapshot(pid: 7, executableName: "npx", commandLine: "npx mcp-server", matchReason: "mcp command pattern"),
                MCPProcessSnapshot(pid: 8, executableName: "uvx", commandLine: "uvx other-mcp", matchReason: "mcp command pattern"),
            ],
            processMatches: [ServerProcessMatch(serverID: "github", processID: 7, confidence: .high, reason: "command matched")]
        )

        let explanations = RuntimeLifecycleExplainer().explain(scanResult: result)

        XCTAssertEqual(explanations.map(\.pid), [7, 8])
        XCTAssertEqual(explanations[0].ownership, .agentOwned)
        XCTAssertEqual(explanations[0].serverID, "github")
        XCTAssertEqual(explanations[1].ownership, .unknown)
        XCTAssertTrue(explanations[1].controlSummary.contains("ownership is unknown"))
    }

    func testKnownHubRuntimeMetadataReconcilesObservedProcessWithLogPath() throws {
        let result = ScanResult(
            servers: [ServerDefinition(id: "memory", displayName: "Memory", transport: .stdio, command: "npx", sourcePath: "/tmp/hub.json")],
            sources: [ConfigSource(agent: .hermes, path: "/tmp/hub.json")],
            processes: [
                MCPProcessSnapshot(pid: 4242, executableName: "npx", commandLine: "npx memory", matchReason: "mcp command pattern"),
            ],
            processMatches: [ServerProcessMatch(serverID: "memory", processID: 4242, confidence: .high, reason: "command matched")]
        )
        let knownHub = RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 4242,
            ownership: .hubOwned,
            commandLine: "npx memory",
            status: .healthy,
            logPath: "/tmp/memory.stdout.log"
        )

        let explanations = RuntimeLifecycleExplainer().explain(scanResult: result, knownHubRuntimes: [knownHub])

        XCTAssertEqual(explanations.map(\.runtimeInstanceID), ["hub:memory"])
        let hub = try XCTUnwrap(explanations.first)
        XCTAssertEqual(hub.ownership, .hubOwned)
        XCTAssertEqual(hub.pid, 4242)
        XCTAssertEqual(hub.logFilePath, "/tmp/memory.stdout.log")
        XCTAssertTrue(hub.logSummary.contains("Log tail available"))
        XCTAssertEqual(hub.capabilities.first { $0.action == .stop }?.isAvailable, true)
    }

    func testRuntimeLifecycleLogPathResolverFindsLatestKnownHubLogPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try "old".write(
            to: tempDirectory.appendingPathComponent("Memory-Server-20231114221320.stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        try "new".write(
            to: tempDirectory.appendingPathComponent("Memory-Server-20231114221420.stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        try "other".write(
            to: tempDirectory.appendingPathComponent("github-20231114221520.stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: tempDirectory.appendingPathComponent("Memory-Server-latest.stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        let knownHub = RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 4242,
            ownership: .hubOwned,
            commandLine: "npx memory",
            status: .healthy
        )
        let scanResult = ScanResult(
            servers: [
                ServerDefinition(
                    id: "memory",
                    displayName: "Memory Server",
                    transport: .stdio,
                    command: "npx",
                    sourcePath: "/tmp/hub.json"
                )
            ],
            sources: [],
            processes: [],
            processMatches: []
        )

        let enriched = RuntimeLifecycleLogPathResolver().enrich(
            instances: [knownHub],
            scanResult: scanResult,
            logDirectory: tempDirectory.path
        )

        XCTAssertTrue(enriched.first?.logPath?.hasSuffix("Memory-Server-20231114221420.stdout.log") == true)
    }

    func testRuntimeLifecycleLogPathResolverLeavesExternalRuntimeWithoutLogLookup() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try "external".write(
            to: tempDirectory.appendingPathComponent("github-20231114221320.stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        let external = RuntimeInstance(
            id: "pid:42",
            serverID: "github",
            pid: 42,
            ownership: .agentOwned,
            commandLine: "npx github",
            status: .observed
        )
        let scanResult = ScanResult(
            servers: [ServerDefinition(id: "github", displayName: "github", transport: .stdio, command: "npx", sourcePath: "/tmp/claude.json")],
            sources: [],
            processes: [],
            processMatches: []
        )

        let enriched = RuntimeLifecycleLogPathResolver().enrich(
            instances: [external],
            scanResult: scanResult,
            logDirectory: tempDirectory.path
        )

        XCTAssertNil(enriched.first?.logPath)
    }

    func testStaleHubRuntimeRecordExplainsRecoveryAndKeepsDestructiveControlsDisabled() throws {
        let knownHub = RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 5150,
            ownership: .hubOwned,
            commandLine: "npx memory",
            status: .healthy,
            logPath: "/tmp/memory.stdout.log"
        )

        let explanations = RuntimeLifecycleExplainer().explain(
            scanResult: ScanResult(servers: [], sources: [], processes: [], processMatches: []),
            knownHubRuntimes: [knownHub]
        )

        let stale = try XCTUnwrap(explanations.first)
        XCTAssertEqual(stale.runtimeInstanceID, "hub:memory")
        XCTAssertEqual(stale.status, .degraded)
        XCTAssertNil(stale.pid)
        XCTAssertTrue(stale.controlSummary.contains("Stale hub-owned runtime record"))
        XCTAssertTrue(stale.controlSummary.contains("no matching PID"))
        XCTAssertEqual(stale.capabilities.first { $0.action == .start }?.isAvailable, true)
        XCTAssertEqual(stale.capabilities.first { $0.action == .stop }?.isAvailable, false)
        XCTAssertEqual(stale.capabilities.first { $0.action == .restart }?.isAvailable, false)
        XCTAssertTrue(stale.capabilities.first { $0.action == .stop }?.reason.contains("will not stop an unknown process") == true)

        let row = try XCTUnwrap(RuntimeLifecyclePanelStateBuilder().build(from: explanations).rows.first)
        XCTAssertTrue(row.logView.isLoadable)
        XCTAssertEqual(row.logView.filePath, "/tmp/memory.stdout.log")
    }

    func testRuntimeLifecyclePanelDisablesHelperControlsWhenHelperUnavailable() throws {
        let instance = RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 4242,
            ownership: .hubOwned,
            commandLine: "npx memory",
            status: .healthy,
            logPath: "/tmp/memory.log"
        )
        let state = RuntimeLifecyclePanelStateBuilder(
            controlPlaneAvailability: RuntimeLifecycleControlPlaneAvailability(
                state: .unavailable,
                message: "Helper unavailable: No endpoint file found"
            )
        ).build(from: [instance])

        XCTAssertFalse(state.controlPlaneAllowsActions)
        let row = try XCTUnwrap(state.rows.first)
        XCTAssertEqual(row.availableControlActions, [])
        XCTAssertTrue(row.controlAvailabilityText.contains("Lifecycle controls are disabled"))
        XCTAssertTrue(row.controlAvailabilityText.contains("Helper unavailable"))
        XCTAssertTrue(row.capabilitySummaries.contains { $0.contains("Stop: available") })

        let text = RuntimeLifecyclePanelFormatter().formatText(state)
        XCTAssertTrue(text.contains("Helper unavailable"))
        XCTAssertTrue(text.contains("No endpoint file found"))
    }

    func testRuntimeLifecyclePanelStateIsReadOnlyAndIncludesSafeLogAction() throws {
        let instances = [
            RuntimeInstance(
                id: "hub:memory",
                serverID: "memory",
                pid: 4242,
                ownership: .hubOwned,
                commandLine: "npx memory",
                status: .healthy,
                logPath: "/tmp/memory.log"
            ),
            RuntimeInstance(
                id: "pid:7",
                serverID: "github",
                pid: 7,
                ownership: .agentOwned,
                commandLine: "npx github",
                status: .observed
            ),
        ]

        let state = RuntimeLifecyclePanelStateBuilder().build(from: instances)

        XCTAssertEqual(state.rows.map(\.runtimeInstanceID), ["pid:7", "hub:memory"])
        XCTAssertTrue(state.summaryText.contains("2 runtimes"))
        XCTAssertTrue(state.footerText.contains("hub-owned runtimes"))
        XCTAssertTrue(state.footerText.contains("does not kill"))
        let hubRow = try XCTUnwrap(state.rows.first { $0.runtimeInstanceID == "hub:memory" })
        XCTAssertTrue(hubRow.controlAvailabilityText.contains("supervised helper"))
        XCTAssertTrue(hubRow.capabilitySummaries.contains { $0.contains("Stop: available") })
        XCTAssertEqual(hubRow.serverID, "memory")
        XCTAssertEqual(hubRow.availableControlActions, [.stop, .restart])
        XCTAssertTrue(hubRow.logView.isLoadable)
        XCTAssertEqual(hubRow.logView.filePath, "/tmp/memory.log")
        XCTAssertTrue(hubRow.logView.message.contains("Load a bounded"))
        XCTAssertTrue(hubRow.safeActions.contains { $0.kind == .copyRuntimeID })
        XCTAssertTrue(hubRow.safeActions.contains { action in
            action.kind == .copyLogTailCommand
                && action.textToCopy.contains("mcphq logs")
                && action.textToCopy.contains("/tmp/memory.log")
        })
        let agentRow = try XCTUnwrap(state.rows.first { $0.runtimeInstanceID == "pid:7" })
        XCTAssertEqual(agentRow.safeActions.map(\.kind), [.copyRuntimeID])
        XCTAssertFalse(agentRow.logView.isLoadable)
        XCTAssertTrue(agentRow.logView.message.contains("owning agent's logs"))
        XCTAssertTrue(agentRow.controlAvailabilityText.contains("No lifecycle controls"))
    }

    func testRuntimeLifecyclePanelLogLoaderLoadsBoundedRedactedKnownLogPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let logURL = tempDirectory.appendingPathComponent("server.log")
        try (1...6)
            .map { $0 == 5 ? "token=ghp_logSecret1234567890" : "line \($0)" }
            .joined(separator: "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
        let instance = RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 4242,
            ownership: .hubOwned,
            commandLine: "npx memory",
            status: .healthy,
            logPath: logURL.path
        )
        let row = try XCTUnwrap(RuntimeLifecyclePanelStateBuilder().build(from: [instance]).rows.first)

        let result = try RuntimeLifecyclePanelLogLoader(
            tailer: RuntimeLogTailer(now: { Date(timeIntervalSince1970: 0) })
        ).load(row: row, lineLimit: 3)

        XCTAssertEqual(result.runtimeInstanceID, "hub:memory")
        XCTAssertEqual(result.entries.map(\.message), ["line 4", "token=<redacted>", "line 6"])
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.summaryText.contains("last 3 lines"))
        XCTAssertFalse(String(describing: result).contains("ghp_logSecret"))
    }

    func testRuntimeLifecyclePanelLogLoaderExplainsUnavailableLogs() throws {
        let instance = RuntimeInstance(
            id: "pid:7",
            serverID: "github",
            pid: 7,
            ownership: .agentOwned,
            commandLine: "npx github",
            status: .observed
        )
        let row = try XCTUnwrap(RuntimeLifecyclePanelStateBuilder().build(from: [instance]).rows.first)

        XCTAssertThrowsError(try RuntimeLifecyclePanelLogLoader().load(row: row)) { error in
            XCTAssertEqual(
                error as? RuntimeLifecyclePanelLogLoadError,
                .unavailable("No MCP-HQ log capture for this external process; check the owning agent's logs.")
            )
        }
    }

    func testRuntimeLifecyclePanelFormatterRedactsLogCommand() throws {
        let instance = RuntimeInstance(
            id: "hub:secret",
            serverID: "secret",
            pid: 99,
            ownership: .hubOwned,
            commandLine: "secret",
            status: .healthy,
            logPath: "/tmp/ghp_logSecret1234567890/server.log"
        )

        let text = RuntimeLifecyclePanelFormatter().formatText(RuntimeLifecyclePanelStateBuilder().build(from: [instance]))

        XCTAssertTrue(text.contains("Copy log tail command"))
        XCTAssertFalse(text.contains("ghp_logSecret1234567890"))
        XCTAssertTrue(text.contains("<redacted>"))
    }

    func testRuntimeLogTailerTailsAndRedactsLines() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let logURL = tempDirectory.appendingPathComponent("server.log")
        try """
        first line
        token=ghp_logSecret1234567890
        final line
        """.write(to: logURL, atomically: true, encoding: .utf8)

        let result = try RuntimeLogTailer(now: { Date(timeIntervalSince1970: 0) }).tail(request: RuntimeLogTailRequest(
            runtimeInstanceID: "runtime-1",
            filePath: logURL.path,
            lineLimit: 2,
            stream: .stderr
        ))

        XCTAssertEqual(result.runtimeInstanceID, "runtime-1")
        XCTAssertEqual(result.entries.map(\.stream), [.stderr, .stderr])
        XCTAssertEqual(result.entries.map(\.message), ["token=<redacted>", "final line"])
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(String(describing: result).contains("ghp_logSecret"))
    }

    func testRuntimeLogTailerRejectsInvalidLineLimit() throws {
        let request = RuntimeLogTailRequest(runtimeInstanceID: "runtime-1", filePath: "/tmp/missing.log", lineLimit: 0)

        XCTAssertThrowsError(try RuntimeLogTailer().tail(request: request)) { error in
            XCTAssertEqual(error as? RuntimeLogTailError, .invalidLineLimit(0))
        }
    }

    func testHubRuntimeSupervisorStartsHubOwnedServerWithLogCapture() throws {
        let launcher = FakeRuntimeProcessLauncher(pid: 4242)
        let supervisor = HubRuntimeSupervisor(
            launcher: launcher,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "/bin/echo",
            args: ["hello"],
            envBindings: ["MCP_TOKEN": "ghp_supervisorSecret1234567890"],
            sourcePath: "/tmp/hub.json"
        )

        let instance = try supervisor.start(request: HubRuntimeLaunchRequest(
            server: server,
            logDirectory: directory.path,
            extraEnvironment: ["PATH": "/bin:/usr/bin"]
        ))

        XCTAssertEqual(instance.id, "hub:memory")
        XCTAssertEqual(instance.pid, 4242)
        XCTAssertEqual(instance.ownership, .hubOwned)
        XCTAssertEqual(instance.status, .healthy)
        XCTAssertTrue(instance.logPath?.hasSuffix("memory-20231114221320.stdout.log") == true)
        XCTAssertEqual(launcher.launches.first?.command, "/bin/echo")
        XCTAssertEqual(launcher.launches.first?.args, ["hello"])
        XCTAssertEqual(launcher.launches.first?.environment["MCP_TOKEN"], "ghp_supervisorSecret1234567890")
        XCTAssertFalse(String(describing: instance).contains("ghp_supervisorSecret"))
    }

    func testHubRuntimeSupervisorResolvesKeychainAndEnvironmentReferencesBeforeLaunch() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let secretStore = InMemorySecretStore(values: [reference: "ghp_keychainRuntimeSecret1234567890"])
        let launcher = FakeRuntimeProcessLauncher(pid: 4343)
        let supervisor = HubRuntimeSupervisor(
            launcher: launcher,
            secretStore: secretStore,
            processEnvironment: [
                "PATH": "/bin:/usr/bin",
                "MCP_PROFILE": "development",
                "BASE_URL": "http://localhost:40404"
            ],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "/bin/echo",
            args: ["hello"],
            envBindings: [
                "GITHUB_TOKEN": reference.configValue,
                "MCP_PROFILE": "${MCP_PROFILE}",
                "MCP_URL": "${BASE_URL}/mcp"
            ],
            sourcePath: "/tmp/hub.json"
        )

        let instance = try supervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: directory.path))
        let environment = try XCTUnwrap(launcher.launches.first?.environment)

        XCTAssertEqual(instance.id, "hub:github")
        XCTAssertEqual(environment["GITHUB_TOKEN"], "ghp_keychainRuntimeSecret1234567890")
        XCTAssertEqual(environment["MCP_PROFILE"], "development")
        XCTAssertEqual(environment["MCP_URL"], "http://localhost:40404/mcp")
        XCTAssertFalse(String(describing: instance).contains("ghp_keychainRuntimeSecret"))
    }

    func testHubRuntimeSupervisorFailsBeforeLaunchWhenKeychainReferenceIsMissing() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let launcher = FakeRuntimeProcessLauncher(pid: 4545)
        let supervisor = HubRuntimeSupervisor(
            launcher: launcher,
            secretStore: InMemorySecretStore(),
            processEnvironment: ["PATH": "/bin:/usr/bin"],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "/bin/echo",
            envBindings: ["GITHUB_TOKEN": reference.configValue],
            sourcePath: "/tmp/hub.json"
        )

        XCTAssertThrowsError(try supervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: directory.path))) { error in
            XCTAssertEqual(error as? RuntimeSupervisorError, .missingSecret(reference))
            XCTAssertFalse(String(describing: error).contains("ghp_"))
        }
        XCTAssertEqual(launcher.launches.count, 0)
    }

    func testHubRuntimeSupervisorFailsBeforeLaunchWhenEnvironmentReferenceIsMissing() throws {
        let launcher = FakeRuntimeProcessLauncher(pid: 4646)
        let supervisor = HubRuntimeSupervisor(
            launcher: launcher,
            secretStore: InMemorySecretStore(),
            processEnvironment: ["PATH": "/bin:/usr/bin"],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "/bin/echo",
            envBindings: ["GITHUB_TOKEN": "${MISSING_GITHUB_TOKEN}"],
            sourcePath: "/tmp/hub.json"
        )

        XCTAssertThrowsError(try supervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: directory.path))) { error in
            XCTAssertEqual(error as? RuntimeSupervisorError, .missingEnvironmentReference(name: "MISSING_GITHUB_TOKEN", referencedBy: "GITHUB_TOKEN"))
            XCTAssertFalse(String(describing: error).contains("ghp_"))
        }
        XCTAssertEqual(launcher.launches.count, 0)
    }

    func testHubRuntimeSupervisorPersistsStartedAndStoppedStateWhenStoreProvided() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SQLiteScanHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite3"))
        let handle = FakeRuntimeProcessHandle(pid: 9001)
        let launcher = FakeRuntimeProcessLauncher(handle: handle)
        let supervisor = HubRuntimeSupervisor(
            launcher: launcher,
            controlPlaneStore: store,
            now: { Date(timeIntervalSince1970: 2_500) }
        )
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "/bin/echo",
            args: ["hello"],
            sourcePath: "/tmp/hub.json"
        )

        let started = try supervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: directory.path))
        var records = try store.listRuntimeInstanceRecords(ownership: .hubOwned)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].instance.id, started.id)
        XCTAssertEqual(records[0].instance.pid, 9001)
        XCTAssertEqual(records[0].instance.status, .healthy)

        _ = try supervisor.stop(instance: started)
        records = try store.listRuntimeInstanceRecords(ownership: .hubOwned)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].instance.id, started.id)
        XCTAssertNil(records[0].instance.pid)
        XCTAssertEqual(records[0].instance.status, .stopped)
    }

    func testHubRuntimeSupervisorStopsOnlyTrackedHubOwnedProcesses() throws {
        let handle = FakeRuntimeProcessHandle(pid: 7001)
        let supervisor = HubRuntimeSupervisor(launcher: FakeRuntimeProcessLauncher(handle: handle))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let server = ServerDefinition(
            id: "filesystem",
            displayName: "filesystem",
            transport: .stdio,
            command: "/bin/cat",
            sourcePath: "/tmp/hub.json"
        )
        let running = try supervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: directory.path))

        let stopped = try supervisor.stop(instance: running)

        XCTAssertTrue(handle.didTerminate)
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertNil(stopped.pid)
        XCTAssertThrowsError(try supervisor.stop(instance: stopped)) { error in
            XCTAssertEqual(error as? RuntimeSupervisorError, .runtimeNotManaged("hub:filesystem"))
        }
    }

    func testHubRuntimeSupervisorRefusesExternalOrUnknownRuntimes() throws {
        let supervisor = HubRuntimeSupervisor(launcher: FakeRuntimeProcessLauncher(pid: 1))
        let external = RuntimeInstance(
            id: "pid:123",
            serverID: "github",
            pid: 123,
            ownership: .agentOwned,
            commandLine: "npx github",
            status: .observed
        )

        XCTAssertThrowsError(try supervisor.stop(instance: external)) { error in
            XCTAssertEqual(error as? RuntimeSupervisorError, .nonHubOwnedRuntime("pid:123"))
        }
    }

    func testRuntimeLaunchCandidateBuilderListsStartableStdioServersFirstAndExplainsRemoteServers() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "remote",
                    displayName: "remote",
                    transport: .http,
                    url: "http://localhost:8080/mcp",
                    sourcePath: source.path
                ),
                ServerDefinition(
                    id: "memory",
                    displayName: "memory",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-memory"],
                    envBindings: ["TOKEN": "ghp_candidateSecret1234567890"],
                    sourcePath: source.path
                ),
            ],
            sources: [source],
            issues: []
        )

        let candidates = RuntimeLaunchCandidateBuilder().build(from: result)

        XCTAssertEqual(candidates.map(\.serverID), ["memory", "remote"])
        XCTAssertEqual(candidates[0].agentName, "Hermes")
        XCTAssertTrue(candidates[0].isStartable)
        XCTAssertTrue(candidates[0].commandSummary.contains("@modelcontextprotocol/server-memory"))
        XCTAssertFalse(String(describing: candidates).contains("ghp_candidateSecret"))
        XCTAssertFalse(candidates[1].isStartable)
        XCTAssertTrue(candidates[1].disabledReason?.contains("Only stdio") == true)
    }
}

private final class FakeRuntimeProcessHandle: RuntimeProcessHandle {
    let processIdentifier: Int32
    var isRunning: Bool
    var didTerminate = false

    init(pid: Int32, isRunning: Bool = true) {
        self.processIdentifier = pid
        self.isRunning = isRunning
    }

    func terminate() {
        didTerminate = true
        isRunning = false
    }
}

private struct FakeRuntimeLaunch: Equatable {
    let command: String
    let args: [String]
    let environment: [String: String]
    let stdoutURL: URL
    let stderrURL: URL
}

private final class FakeRuntimeProcessLauncher: RuntimeProcessLaunching {
    var launches: [FakeRuntimeLaunch] = []
    private let handle: FakeRuntimeProcessHandle

    init(pid: Int32) {
        self.handle = FakeRuntimeProcessHandle(pid: pid)
    }

    init(handle: FakeRuntimeProcessHandle) {
        self.handle = handle
    }

    func launch(
        command: String,
        args: [String],
        environment: [String: String],
        stdoutURL: URL,
        stderrURL: URL
    ) throws -> RuntimeProcessHandle {
        launches.append(FakeRuntimeLaunch(
            command: command,
            args: args,
            environment: environment,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL
        ))
        return handle
    }
}
