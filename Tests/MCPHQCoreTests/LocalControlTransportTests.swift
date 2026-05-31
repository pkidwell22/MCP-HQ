import XCTest
@testable import MCPHQCore

final class LocalControlTransportTests: XCTestCase {
    func testJSONCodecRoundTripsRequestsAndResponsesWithStableID() throws {
        let codec = LocalControlJSONCodec()
        let source = ConfigSource(agent: .codex, path: "/tmp/config.toml")
        let request = LocalControlRequest(route: .doctor, includeProbes: true, source: source)

        let requestEnvelope = try codec.decodeRequest(try codec.encodeRequest(request, id: "request-1"))
        XCTAssertEqual(requestEnvelope.id, "request-1")
        XCTAssertEqual(requestEnvelope.request, request)
        XCTAssertNil(requestEnvelope.response)

        let response = LocalControlResponse(status: LocalControlStatus(result: ScanResult(
            servers: [],
            sources: [source],
            issues: []
        )))
        let responseEnvelope = try codec.decodeResponse(try codec.encodeResponse(response, id: requestEnvelope.id))

        XCTAssertEqual(responseEnvelope.id, "request-1")
        XCTAssertEqual(responseEnvelope.response, response)
        XCTAssertNil(responseEnvelope.request)
    }

    func testJSONCodecRejectsMalformedEnvelopeDirection() throws {
        let codec = LocalControlJSONCodec()
        let requestData = try codec.encodeRequest(LocalControlRequest(route: .status), id: "wrong-way")

        XCTAssertThrowsError(try codec.decodeResponse(requestData)) { error in
            XCTAssertEqual(error as? LocalControlTransportError, .invalidResponseEnvelope("contains request"))
        }
    }

    func testJSONCodecRedactsRemoteErrors() throws {
        let codec = LocalControlJSONCodec()
        let data = try codec.encodeError("token ghp_transportSecret1234567890 failed", id: "error-1")

        XCTAssertThrowsError(try codec.decodeResponse(data)) { error in
            guard case LocalControlTransportError.remoteError(let message) = error else {
                return XCTFail("Expected remote error, got \(error)")
            }
            XCTAssertEqual(message, "token <redacted> failed")
        }
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("ghp_transportSecret") == true)
    }

    func testInProcessClientUsesEnvelopeContractAndRedactedRouterResponse() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_clientSecret1234567890"],
              "env": {
                "GITHUB_TOKEN": "ghp_clientSecret1234567890"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let client = LocalControlInProcessClient(router: LocalControlRouter())
        let envelope = try client.sendEnvelope(
            LocalControlRequest(route: .scan, source: ConfigSource(agent: .claude, path: configURL.path)),
            id: "scan-1"
        )

        XCTAssertEqual(envelope.id, "scan-1")
        XCTAssertEqual(envelope.response?.scanResult?.servers.count, 1)
        XCTAssertFalse(String(describing: envelope).contains("ghp_clientSecret"))
    }

    func testLocalControlStatusCountsProbeFindings() {
        let status = LocalControlStatus(result: ScanResult(
            servers: [ServerDefinition(id: "remote", displayName: "Remote", transport: .http, url: "http://localhost:40404/mcp", sourcePath: "/tmp/hermes.yaml")],
            sources: [ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")],
            issues: [ScanIssue(source: ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml"), severity: .warning, message: "Missing env")],
            probeResults: [
                MCPProbeResult(serverID: "remote", status: .error, message: "HTTP MCP probe could not connect")
            ]
        ))

        XCTAssertEqual(status.issueCount, 2)
        XCTAssertEqual(status.warningCount, 1)
        XCTAssertEqual(status.errorCount, 1)
    }

    func testHTTPAdapterHandlesAuthorizedControlEnvelope() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)

        let codec = LocalControlJSONCodec()
        let body = try codec.encodeRequest(
            LocalControlRequest(route: .status, source: ConfigSource(agent: .claude, path: configURL.path)),
            id: "http-1"
        )
        let adapter = LocalControlHTTPAdapter(authToken: "local-token")

        let response = adapter.handle(LocalControlHTTPRequest(
            method: "POST",
            path: LocalControlHTTPAdapter.controlPath,
            headers: ["Authorization": "Bearer local-token"],
            body: body
        ))
        let envelope = try codec.decodeResponse(response.body)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["Cache-Control"], "no-store")
        XCTAssertEqual(envelope.id, "http-1")
        XCTAssertEqual(envelope.response?.status?.serverCount, 1)
    }

    func testHTTPAdapterRejectsUnauthorizedRequestsBeforeDecodingBody() throws {
        let codec = LocalControlJSONCodec()
        let body = try codec.encodeRequest(LocalControlRequest(route: .status), id: "unauthorized-1")
        let adapter = LocalControlHTTPAdapter(authToken: "secret-token-1234567890")

        let response = adapter.handle(LocalControlHTTPRequest(
            method: "POST",
            path: LocalControlHTTPAdapter.controlPath,
            body: body
        ))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertThrowsError(try codec.decodeResponse(response.body)) { error in
            guard case LocalControlTransportError.remoteError(let message) = error else {
                return XCTFail("Expected unauthorized remote error, got \(error)")
            }
            XCTAssertEqual(message, "Unauthorized local control request")
        }
        XCTAssertFalse(String(data: response.body, encoding: .utf8)?.contains("secret-token") == true)
    }

    func testHTTPAdapterRejectsWrongPathAndMethod() {
        let adapter = LocalControlHTTPAdapter()

        let missing = adapter.handle(LocalControlHTTPRequest(method: "POST", path: "/missing"))
        let wrongMethod = adapter.handle(LocalControlHTTPRequest(method: "GET", path: LocalControlHTTPAdapter.controlPath))

        XCTAssertEqual(missing.statusCode, 404)
        XCTAssertEqual(wrongMethod.statusCode, 405)
    }

    func testLoopbackHTTPServerServesControlRequestsOverURLSession() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)

        let codec = LocalControlJSONCodec()
        let server = LocalControlLoopbackHTTPServer(adapter: LocalControlHTTPAdapter(authToken: "loopback-token"))
        try server.start()
        defer { server.stop() }

        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/v1/control"))
        request.httpMethod = "POST"
        request.setValue("Bearer loopback-token", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try codec.encodeRequest(
            LocalControlRequest(route: .status, source: ConfigSource(agent: .claude, path: configURL.path)),
            id: "loopback-1"
        )

        let response = try performURLSessionRequest(request)
        let httpResponse = try XCTUnwrap(response.response as? HTTPURLResponse)
        let envelope = try codec.decodeResponse(response.data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(envelope.id, "loopback-1")
        XCTAssertEqual(envelope.response?.status?.serverCount, 1)
    }

    func testLoopbackHTTPServerRejectsMissingToken() throws {
        let codec = LocalControlJSONCodec()
        let server = LocalControlLoopbackHTTPServer(adapter: LocalControlHTTPAdapter(authToken: "loopback-token"))
        try server.start()
        defer { server.stop() }

        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/v1/control"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try codec.encodeRequest(LocalControlRequest(route: .status), id: "loopback-unauthorized")

        let response = try performURLSessionRequest(request)
        let httpResponse = try XCTUnwrap(response.response as? HTTPURLResponse)

        XCTAssertEqual(httpResponse.statusCode, 401)
        XCTAssertThrowsError(try codec.decodeResponse(response.data)) { error in
            guard case LocalControlTransportError.remoteError(let message) = error else {
                return XCTFail("Expected unauthorized remote error, got \(error)")
            }
            XCTAssertEqual(message, "Unauthorized local control request")
        }
    }

    func testServerLauncherWritesDiscoverableEndpointFileAndRemovesItOnStop() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let endpointURL = tempDirectory.appendingPathComponent("control-endpoint.json")
        let store = LocalControlEndpointStore(fileURL: endpointURL)
        let launcher = LocalControlServerLauncher(
            endpointStore: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let runtime = try launcher.start(token: "launcher-token")
        defer { runtime.stop() }
        let endpoint = try store.load()

        XCTAssertEqual(endpoint, runtime.endpoint)
        XCTAssertEqual(endpoint.token, "launcher-token")
        XCTAssertEqual(endpoint.controlURL.path, "/api/v1/control")
        XCTAssertEqual(endpoint.pid, getpid())
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpointURL.path))

        runtime.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpointURL.path))
    }

    func testServerLauncherEndpointCanAuthorizeLoopbackRequests() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let store = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: store).start(token: "launcher-token")
        defer { runtime.stop() }
        let endpoint = try store.load()

        let codec = LocalControlJSONCodec()
        var request = URLRequest(url: endpoint.controlURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try XCTUnwrap(endpoint.token))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try codec.encodeRequest(
            LocalControlRequest(route: .status, source: ConfigSource(agent: .claude, path: configURL.path)),
            id: "launcher-1"
        )

        let response = try performURLSessionRequest(request)
        let httpResponse = try XCTUnwrap(response.response as? HTTPURLResponse)
        let envelope = try codec.decodeResponse(response.data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(envelope.id, "launcher-1")
        XCTAssertEqual(envelope.response?.status?.serverCount, 1)
    }

    func testHTTPClientUsesEndpointFileToken() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let store = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: store).start(token: "client-token")
        defer { runtime.stop() }

        let response = try LocalControlHTTPClient(endpointStore: store).send(LocalControlRequest(
            route: .status,
            source: ConfigSource(agent: .claude, path: configURL.path)
        ), id: "client-1")

        XCTAssertEqual(response.status?.serverCount, 1)
    }

    func testClientStateHelperReportsEndpointMetadataWithoutToken() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        try endpointStore.save(LocalControlEndpoint(
            baseURL: "http://127.0.0.1:37373",
            token: "mcphq_stateSecret1234567890",
            pid: 2468,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let state = LocalControlClientStateHelper().state(endpointStore: endpointStore)

        XCTAssertEqual(state.backend, .endpointHTTP)
        XCTAssertEqual(state.endpointPID, 2468)
        XCTAssertEqual(state.endpointHasToken, true)
        XCTAssertEqual(state.availability.state, .unknown)
        XCTAssertTrue(state.endpointURL?.contains("/api/v1/control") == true)
        XCTAssertFalse(String(describing: state).contains("mcphq_stateSecret"))
    }

    func testClientStateHelperPrefersEndpointForSafeReadsWhenAvailable() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: endpointStore).start(token: "preferred-token")
        defer { runtime.stop() }
        final class FallbackRecorder: @unchecked Sendable { var wasCalled = false }
        let recorder = FallbackRecorder()

        let exchange = try LocalControlClientStateHelper().sendPreferringEndpoint(
            LocalControlRequest(route: .status, source: ConfigSource(agent: .claude, path: configURL.path)),
            endpointStore: endpointStore
        ) {
            recorder.wasCalled = true
            return LocalControlResponse(status: LocalControlStatus(result: ScanResult(servers: [], sources: [], issues: [])))
        }

        XCTAssertFalse(recorder.wasCalled)
        XCTAssertEqual(exchange.response.status?.serverCount, 1)
        XCTAssertEqual(exchange.state.backend, .endpointHTTP)
        XCTAssertEqual(exchange.state.availability.state, .available)
        XCTAssertTrue(exchange.state.endpointHasToken)
        XCTAssertFalse(String(describing: exchange.state).contains("preferred-token"))
    }

    func testClientStateHelperFallsBackToDirectCoreForSafeReadsWhenEndpointIsMissing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("missing-endpoint.json"))

        let exchange = try LocalControlClientStateHelper().sendPreferringEndpoint(
            LocalControlRequest(route: .status),
            endpointStore: endpointStore
        ) {
            LocalControlResponse(status: LocalControlStatus(result: ScanResult(
                servers: [ServerDefinition(id: "fallback", displayName: "Fallback", transport: .stdio, sourcePath: "/tmp/fallback.json")],
                sources: [ConfigSource(agent: .claude, path: "/tmp/fallback.json")],
                issues: []
            )))
        }

        XCTAssertEqual(exchange.response.status?.serverCount, 1)
        XCTAssertEqual(exchange.state.backend, .directCore)
        XCTAssertEqual(exchange.state.endpointFilePath, endpointStore.fileURL.path)
        XCTAssertEqual(exchange.state.availability.state, .unavailable)
        XCTAssertTrue(exchange.state.availability.message.contains("using direct in-process core"))
    }

    func testClientStateHelperDoesNotFallbackForGuardedMutations() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("missing-endpoint.json"))
        final class FallbackRecorder: @unchecked Sendable { var wasCalled = false }
        let recorder = FallbackRecorder()

        XCTAssertThrowsError(try LocalControlClientStateHelper().sendPreferringEndpoint(
            LocalControlRequest(route: .runtimeStop, runtimeInstanceID: "runtime-1"),
            endpointStore: endpointStore
        ) {
            recorder.wasCalled = true
            return LocalControlResponse(runtimeInstance: RuntimeInstance(
                id: "runtime-1",
                ownership: .hubOwned,
                commandLine: "",
                status: .stopped
            ))
        })
        XCTAssertFalse(recorder.wasCalled)
    }

    func testLaunchAgentManagerBuildsLaunchctlBootstrapAndBootoutCommands() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        final class CommandRecorder: @unchecked Sendable {
            var commands: [[String]] = []
        }
        let recorder = CommandRecorder()
        let manager = LocalControlLaunchAgentManager(
            launchAgentsDirectory: tempDirectory,
            commandRunner: { command in
                recorder.commands.append(command)
                return LocalControlLaunchAgentCommandResult(command: command, exitCode: 0, stdout: "ok")
            }
        )
        let configuration = LocalControlLaunchAgentConfiguration(
            programPath: "/tmp/mcphq",
            endpointFilePath: tempDirectory.appendingPathComponent("endpoint.json").path
        )
        _ = try manager.install(configuration)

        let bootstrap = try manager.bootstrap()
        let bootout = try manager.bootout()

        XCTAssertEqual(bootstrap.exitCode, 0)
        XCTAssertEqual(bootout.exitCode, 0)
        XCTAssertEqual(recorder.commands.count, 2)
        XCTAssertEqual(recorder.commands[0][0], "/bin/launchctl")
        XCTAssertEqual(recorder.commands[0][1], "bootstrap")
        XCTAssertTrue(recorder.commands[0][2].hasPrefix("gui/"))
        XCTAssertEqual(recorder.commands[0][3], tempDirectory.appendingPathComponent("com.mcphq.control.plist").path)
        XCTAssertEqual(recorder.commands[1][1], "bootout")
        XCTAssertTrue(recorder.commands[1][2].contains("/com.mcphq.control"))
    }

    func testLaunchAgentInstallDryRunDoesNotWritePlist() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let manager = LocalControlLaunchAgentManager(launchAgentsDirectory: tempDirectory)
        let configuration = LocalControlLaunchAgentConfiguration(
            programPath: "/tmp/mcphq",
            endpointFilePath: tempDirectory.appendingPathComponent("endpoint.json").path
        )

        let result = try manager.install(configuration, dryRun: true)

        XCTAssertFalse(result.didWrite)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.plistPath))
        XCTAssertTrue(result.plistText.contains("/tmp/mcphq"))
        XCTAssertTrue(result.bootstrapCommand.contains("launchctl bootstrap"))
    }

    func testLaunchAgentPlistIncludesDeterministicPathEnvironment() throws {
        let configuration = LocalControlLaunchAgentConfiguration(
            programPath: "/tmp/mcphq",
            environmentVariables: LocalControlLaunchAgentConfiguration.defaultEnvironmentVariables(
                currentPath: "/custom/bin:/usr/bin:/custom/bin"
            )
        )
        let data = try LocalControlLaunchAgentManager().renderPlist(configuration)
        let plistText = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(plistText.contains("<key>EnvironmentVariables</key>"))
        XCTAssertTrue(plistText.contains("<key>PATH</key>"))
        XCTAssertTrue(plistText.contains("/custom/bin:/usr/bin:/opt/homebrew/bin"))
        XCTAssertFalse(plistText.contains("TOKEN"))
    }

    func testHelperPathResolverPrefersBundledContentsMacOSHelper() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = tempDirectory.appendingPathComponent("MCP-HQ.app", isDirectory: true)
        let helperURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("mcphq")
        try FileManager.default.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

        let resolver = LocalControlHelperPathResolver(environmentPath: nil)
        let resolution = resolver.resolve(bundleURL: bundleURL, executablePath: nil)

        XCTAssertEqual(resolution.source, .bundledAppHelper)
        XCTAssertEqual(resolution.path, helperURL.standardizedFileURL.path)
        XCTAssertTrue(resolution.exists)
    }

    func testHelperStatusSnapshotLabelsAvailabilityAndMissingReason() {
        let status = LocalControlLaunchAgentStatus(
            plistPath: "/tmp/com.mcphq.control.plist",
            isInstalled: true,
            endpoint: LocalControlEndpoint(baseURL: "http://127.0.0.1:1234", token: nil, pid: 42),
            launchdState: .loaded,
            launchdMessage: "loaded"
        )
        let available = LocalControlHelperStatusSnapshot(
            launchAgentStatus: status,
            helperPath: LocalControlHelperPathResolution(path: "/tmp/mcphq", source: .bundledAppHelper, exists: true),
            endpointAvailability: LocalControlEndpointAvailability(state: .available, message: "ok")
        )

        XCTAssertEqual(available.installedLabel, "Installed")
        XCTAssertEqual(available.launchdLabel, "Loaded")
        XCTAssertEqual(available.endpointLabel, "Available")
        XCTAssertEqual(available.helperPathLabel, "Bundled app helper: /tmp/mcphq")
        XCTAssertTrue(available.canInstallPlist)
        XCTAssertFalse(available.canInstallAndBootstrap)
        XCTAssertFalse(available.canBootstrap)
        XCTAssertTrue(available.canBootout)
        XCTAssertNil(available.installDisabledReason)
        XCTAssertEqual(available.installAndBootstrapDisabledReason, "The helper is already loaded.")
        XCTAssertEqual(available.bootstrapDisabledReason, "The helper is already loaded.")
        XCTAssertNil(available.bootoutDisabledReason)

        let stopped = LocalControlHelperStatusSnapshot(
            launchAgentStatus: LocalControlLaunchAgentStatus(
                plistPath: "/tmp/com.mcphq.control.plist",
                isInstalled: true,
                endpoint: nil,
                launchdState: .notLoaded,
                launchdMessage: nil
            ),
            helperPath: LocalControlHelperPathResolution(path: "/tmp/mcphq", source: .bundledAppHelper, exists: true),
            endpointAvailability: .unknown
        )
        XCTAssertTrue(stopped.canInstallAndBootstrap)
        XCTAssertTrue(stopped.canBootstrap)
        XCTAssertFalse(stopped.canBootout)
        XCTAssertNil(stopped.installAndBootstrapDisabledReason)
        XCTAssertNil(stopped.bootstrapDisabledReason)
        XCTAssertEqual(stopped.bootoutDisabledReason, "The helper is not loaded.")

        let missing = LocalControlHelperStatusSnapshot(
            launchAgentStatus: status,
            helperPath: LocalControlHelperPathResolution(path: "/tmp/missing-mcphq", source: .missing, exists: false),
            endpointAvailability: .unknown
        )
        XCTAssertFalse(missing.canInstallPlist)
        XCTAssertFalse(missing.canInstallAndBootstrap)
        XCTAssertFalse(missing.canBootstrap)
        XCTAssertEqual(missing.helperPathLabel, "Missing: /tmp/missing-mcphq")
        XCTAssertTrue(missing.installDisabledReason?.contains("helper executable was not found") == true)
        XCTAssertEqual(missing.installAndBootstrapDisabledReason, missing.installDisabledReason)
        XCTAssertEqual(missing.bootstrapDisabledReason, missing.installDisabledReason)
    }

    func testEndpointCheckerUsesHumanMessageForMissingEndpointFile() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("missing-endpoint.json"))

        let availability = LocalControlEndpointChecker().check(endpointStore: endpointStore)

        XCTAssertEqual(availability.state, .unavailable)
        XCTAssertEqual(availability.message, "No endpoint file found")
    }

    func testLaunchAgentStatusCanCheckLaunchdWithoutExposingSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("endpoint.json"))
        try endpointStore.save(LocalControlEndpoint(
            baseURL: "http://127.0.0.1:37373",
            controlPath: "/api/v1/control",
            token: "mcphq_statusSecret1234567890",
            pid: 1234,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let manager = LocalControlLaunchAgentManager(
            launchAgentsDirectory: tempDirectory,
            commandRunner: { command in
                LocalControlLaunchAgentCommandResult(
                    command: command,
                    exitCode: 0,
                    stdout: "token=mcphq_statusSecret1234567890 loaded"
                )
            }
        )
        let configuration = LocalControlLaunchAgentConfiguration(
            programPath: "/tmp/mcphq",
            endpointFilePath: endpointStore.fileURL.path
        )
        _ = try manager.install(configuration)

        let status = manager.status(endpointStore: endpointStore, checkLaunchd: true)

        XCTAssertTrue(status.isInstalled)
        XCTAssertEqual(status.launchdState, .loaded)
        XCTAssertEqual(status.endpoint?.pid, 1234)
        XCTAssertFalse(status.launchdMessage?.contains("mcphq_statusSecret") == true)
    }

    private func performURLSessionRequest(_ request: URLRequest) throws -> (data: Data, response: URLResponse) {
        let expectation = XCTestExpectation(description: "URLSession request completes")
        final class RequestBox: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = RequestBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            expectation.fulfill()
        }.resume()

        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(waiterResult, .completed)
        if let error = box.error { throw error }
        return (try XCTUnwrap(box.data), try XCTUnwrap(box.response))
    }
}
