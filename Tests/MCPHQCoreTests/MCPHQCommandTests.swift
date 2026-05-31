import XCTest
@testable import MCPHQCore

final class MCPHQCommandTests: XCTestCase {
    func testScanSourcePrintsParsedClaudeFixture() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "claude-mcp",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))

        let result = try MCPHQCommand().run(args: ["scan", "--source", "claude:\(fixture.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ scan"))
        XCTAssertTrue(result.stdout.contains("Servers: 2"))
        XCTAssertTrue(result.stdout.contains("github"))
        XCTAssertTrue(result.stdout.contains("qmd"))
        XCTAssertEqual(result.stderr, "")
    }

    func testScanJSONEmitsValidRedactedJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "mcp-server-github",
              "env": {
                "GITHUB_TOKEN": "ghp_abcd1234secretvalue"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["servers"] as? [[String: Any]])
        let firstServer = try XCTUnwrap(servers.first)
        let env = try XCTUnwrap(firstServer["envBindings"] as? [String: String])
        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        XCTAssertFalse(result.stdout.contains("ghp_abcd1234secretvalue"))
    }

    func testScanMalformedConfigReportsIssueAndExitsSuccessfully() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("bad.json")
        try "{ bad json".write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Servers: 0"))
        XCTAssertTrue(result.stdout.contains("Issues: 1"))
        XCTAssertTrue(result.stdout.contains("error claude \(configURL.path):"))
    }

    func testScanCorrelatesConfiguredServersWithRunningProcesses() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(processScanner: MCPProcessScanner(processProvider: {
            [RawProcessSnapshot(pid: 4201, commandLine: "npx -y @modelcontextprotocol/server-github --token ghp_ab...3456")]
        }))

        let result = try command.run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let matches = try XCTUnwrap(object["processMatches"] as? [[String: Any]])
        let firstMatch = try XCTUnwrap(matches.first)
        XCTAssertEqual(firstMatch["serverID"] as? String, ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "github"))
        XCTAssertEqual(firstMatch["processID"] as? Int, 4201)
        XCTAssertEqual(firstMatch["confidence"] as? String, "high")
        XCTAssertFalse(result.stdout.contains("ghp_ab...3456"))
    }

    func testScanReportsMissingConfiguredCommandAsWarning() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "broken": {
              "command": "definitely-not-installed-mcp"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let warning = try XCTUnwrap(issues.first)
        XCTAssertEqual(warning["severity"] as? String, "warning")
        XCTAssertTrue((warning["message"] as? String)?.contains("Command not found for broken: definitely-not-installed-mcp") == true)
    }

    func testScanReportsMissingSensitiveEnvAsWarning() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "env": {
                "GITHUB_TOKEN": ""
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let warning = try XCTUnwrap(issues.first)
        XCTAssertEqual(warning["severity"] as? String, "warning")
        XCTAssertTrue((warning["message"] as? String)?.contains("Missing env var for github: GITHUB_TOKEN") == true)
        XCTAssertTrue((warning["message"] as? String)?.contains("Keychain") == true)
    }

    func testScanIncludesInjectedProbeResults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(probeProvider: { servers in
            servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 9, message: "tools/list succeeded") }
        })

        let result = try command.run(args: ["scan", "--json", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let probes = try XCTUnwrap(object["probeResults"] as? [[String: Any]])
        XCTAssertEqual(probes.first?["serverID"] as? String, ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "memory"))
        XCTAssertEqual(probes.first?["toolCount"] as? Int, 9)
    }

    func testScanProbeFlagUsesLiveProbeProvider() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(liveProbeProvider: { servers in
            servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 2, message: "tools/list succeeded") }
        })

        let result = try command.run(args: ["scan", "--json", "--probe", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let probes = try XCTUnwrap(object["probeResults"] as? [[String: Any]])
        XCTAssertEqual(probes.first?["serverID"] as? String, ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "memory"))
        XCTAssertEqual(probes.first?["toolCount"] as? Int, 2)
    }

    func testScanCanUseEndpointBackedHTTPClientAndRedactsSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_scanEndpointArgSecret1234567890"],
              "env": {
                "GITHUB_TOKEN": "ghp_scanEndpointEnvSecret1234567890"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter(scanCoordinator: ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: {
                [RawProcessSnapshot(pid: 9911, commandLine: "npx -y @modelcontextprotocol/server-github --token ghp_scanEndpointProcessSecret1234567890")]
            })
        ))
        let adapter = LocalControlHTTPAdapter(
            client: LocalControlInProcessClient(router: router),
            authToken: "scan-client-token"
        )
        let server = LocalControlLoopbackHTTPServer(adapter: adapter)
        try server.start()
        defer { server.stop() }
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        try endpointStore.save(LocalControlEndpoint(
            baseURL: server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: "scan-client-token",
            pid: 1234,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let result = try MCPHQCommand(processScanner: MCPProcessScanner(processProvider: { [] })).run(args: [
            "scan", "--json",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(configURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["servers"] as? [[String: Any]])
        let env = try XCTUnwrap(servers.first?["envBindings"] as? [String: String])
        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        let processes = try XCTUnwrap(object["processes"] as? [[String: Any]])
        XCTAssertEqual(processes.first?["pid"] as? Int, 9911)
        XCTAssertFalse(result.stdout.contains("ghp_scanEndpointArgSecret"))
        XCTAssertFalse(result.stdout.contains("ghp_scanEndpointEnvSecret"))
        XCTAssertFalse(result.stdout.contains("ghp_scanEndpointProcessSecret"))
        XCTAssertFalse(result.stdout.contains("scan-client-token"))
        XCTAssertEqual(result.stderr, "")
    }

    func testDoctorCanUseEndpointBackedHTTPClientAndRedactsProbeSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter(scanCoordinator: ScanCoordinator(
            probeProvider: { servers in
                servers.map { MCPProbeResult(serverID: $0.id, status: .error, message: "Probe failed token=ghp_doctorEndpointProbeSecret1234567890") }
            }
        ))
        let adapter = LocalControlHTTPAdapter(
            client: LocalControlInProcessClient(router: router),
            authToken: "doctor-client-token"
        )
        let server = LocalControlLoopbackHTTPServer(adapter: adapter)
        try server.start()
        defer { server.stop() }
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        try endpointStore.save(LocalControlEndpoint(
            baseURL: server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: "doctor-client-token",
            pid: 1234,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let result = try MCPHQCommand(liveProbeProvider: { _ in [] }).run(args: [
            "doctor", "--json", "--probe",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(configURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["errorCount"] as? Int, 1)
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.first?["category"] as? String, "probe")
        XCTAssertTrue((findings.first?["title"] as? String)?.contains("token=<redacted>") == true)
        XCTAssertFalse(result.stdout.contains("ghp_doctorEndpointProbeSecret"))
        XCTAssertFalse(result.stdout.contains("doctor-client-token"))
        XCTAssertEqual(result.stderr, "")
    }

    func testDoctorCommandPrintsActionableReport() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "env": {
                "GITHUB_TOKEN": ""
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: ["doctor", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ doctor"))
        XCTAssertTrue(result.stdout.contains("[warning] server: Missing env var for github: GITHUB_TOKEN"))
        XCTAssertTrue(result.stdout.contains("why:"))
        XCTAssertTrue(result.stdout.contains("fix:"))
    }

    func testDoctorJSONEmitsValidReport() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")

        let result = try MCPHQCommand().run(args: ["doctor", "--json", "--source", "cursor:\(missingURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["infoCount"] as? Int, 1)
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.first?["category"] as? String, "source")
        XCTAssertEqual(findings.first?["severity"] as? String, "info")
    }

    func testDoctorTextFiltersBySeverityAndSourcePath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        let missingURL = tempDirectory.appendingPathComponent("missing.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "/bin/echo",
              "env": {
                "GITHUB_TOKEN": ""
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let warningResult = try MCPHQCommand().run(args: [
            "doctor",
            "--source", "claude:\(configURL.path)",
            "--source", "cursor:\(missingURL.path)",
            "--severity", "warning",
            "--source-path", configURL.path,
        ])

        XCTAssertEqual(warningResult.exitCode, 0)
        XCTAssertTrue(warningResult.stdout.contains("Findings: 1"))
        XCTAssertTrue(warningResult.stdout.contains("Warnings: 1"))
        XCTAssertTrue(warningResult.stdout.contains("[warning] server: Missing env var for github: GITHUB_TOKEN"))
        XCTAssertFalse(warningResult.stdout.contains("Cursor config is missing"))
    }

    func testDoctorJSONFiltersByServerName() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "/bin/echo",
              "env": {
                "GITHUB_TOKEN": ""
              }
            },
            "broken": {
              "command": "definitely-not-installed-mcp"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: [
            "doctor",
            "--json",
            "--source", "claude:\(configURL.path)",
            "--server", "github",
        ])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["warningCount"] as? Int, 1)
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?["serverName"] as? String, "github")
        XCTAssertFalse(result.stdout.contains("definitely-not-installed-mcp"))
    }

    func testDoctorTextFiltersByServerID() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "/bin/echo",
              "env": {
                "GITHUB_TOKEN": ""
              }
            },
            "broken": {
              "command": "definitely-not-installed-mcp"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let githubID = ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "github")

        let result = try MCPHQCommand().run(args: [
            "doctor",
            "--source", "claude:\(configURL.path)",
            "--server", githubID,
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Findings: 1"))
        XCTAssertTrue(result.stdout.contains("server: github"))
        XCTAssertFalse(result.stdout.contains("definitely-not-installed-mcp"))
    }

    func testDoctorRejectsInvalidSeverityFilter() throws {
        let result = try MCPHQCommand().run(args: ["doctor", "--severity", "critical"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Invalid --severity value: critical"))
    }

    func testConfigPreviewRendersGeneratedConfigWithoutWritingOrPrintingSecrets() throws {
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
              "args": ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_previewsecret1234567890"],
              "env": {
                "GITHUB_TOKEN": "ghp_previewsecret1234567890"
              }
            }
          }
        }
        """.write(to: serverSourceURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: [
            "config", "preview",
            "--source", "claude:\(targetURL.path)",
            "--server-source", "pi:\(serverSourceURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config preview"))
        XCTAssertTrue(result.stdout.contains("Reparsed servers: 1"))
        XCTAssertTrue(result.stdout.contains("Generated config:"))
        XCTAssertTrue(result.stdout.contains("\"mcpServers\""))
        XCTAssertTrue(result.stdout.contains("\"GITHUB_TOKEN\" : " + "\"${GITHUB_TOKEN}\""))
        XCTAssertTrue(result.stdout.contains("<redacted>"))
        XCTAssertFalse(result.stdout.contains("ghp_previewsecret1234567890"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigPreviewAndApplyDryRunCanUseEndpointBackedHTTPClient() throws {
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
              "args": ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_endpointsecret1234567890"],
              "env": {
                "GITHUB_TOKEN": "ghp_endpointsecret1234567890"
              }
            }
          }
        }
        """.write(to: serverSourceURL, atomically: true, encoding: .utf8)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: endpointStore).start(token: "command-config-token")
        defer { runtime.stop() }

        let preview = try MCPHQCommand().run(args: [
            "config", "preview",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(targetURL.path)",
            "--server-source", "pi:\(serverSourceURL.path)"
        ])

        XCTAssertEqual(preview.exitCode, 0)
        XCTAssertTrue(preview.stdout.contains("Config preview"))
        XCTAssertTrue(preview.stdout.contains("Reparsed servers: 1"))
        XCTAssertTrue(preview.stdout.contains("\"GITHUB_TOKEN\" : " + "\"${GITHUB_TOKEN}\""))
        XCTAssertFalse(preview.stdout.contains("ghp_endpointsecret1234567890"))
        XCTAssertEqual(preview.stderr, "")

        let apply = try MCPHQCommand().run(args: [
            "config", "apply",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(targetURL.path)",
            "--server-source", "pi:\(serverSourceURL.path)",
            "--dry-run"
        ])

        XCTAssertEqual(apply.exitCode, 0)
        XCTAssertTrue(apply.stdout.contains("Config apply dry run"))
        XCTAssertTrue(apply.stdout.contains("Did write: no"))
        XCTAssertFalse(apply.stdout.contains("ghp_endpointsecret1234567890"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertEqual(apply.stderr, "")
    }

    func testConfigApplyDryRunDoesNotWriteTarget() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let serverSourceURL = tempDirectory.appendingPathComponent("pi.json")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: serverSourceURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: [
            "config", "apply",
            "--source", "claude:\(targetURL.path)",
            "--server-source", "pi:\(serverSourceURL.path)",
            "--dry-run"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config apply dry run"))
        XCTAssertTrue(result.stdout.contains("Did write: no"))
        XCTAssertTrue(result.stdout.contains("Backup: none"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testConfigApplyWritesTargetAndReturnsBackupPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let serverSourceURL = tempDirectory.appendingPathComponent("pi.json")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"old":{"command":"old-command"}}}"#
            .write(to: targetURL, atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: serverSourceURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand().run(args: [
            "config", "apply",
            "--source", "claude:\(targetURL.path)",
            "--server-source", "pi:\(serverSourceURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config apply"))
        XCTAssertTrue(result.stdout.contains("Did write: yes"))
        let backupLine = try XCTUnwrap(result.stdout.split(separator: "\n").first { $0.hasPrefix("Backup: ") })
        let backupPath = String(backupLine.dropFirst("Backup: ".count))
        XCTAssertTrue(backupPath.contains(".mcphq-backup-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        let written = try Data(contentsOf: targetURL)
        let reparsed = try AgentConfigParser().parse(data: written, source: ConfigSource(agent: .claude, path: targetURL.path))
        XCTAssertEqual(reparsed.map(\.displayName), ["memory"])
    }

    func testConfigConnectAllPreviewRendersSelectedTargetsWithoutWriting() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let claudeURL = tempDirectory.appendingPathComponent("claude.json")
        let codexURL = tempDirectory.appendingPathComponent("codex.toml")
        try """
        mcp_servers:
          github:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-github"
            env:
              GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_connectallpreview1234567890"
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)
        try #"{"theme":"dark","mcpServers":{"old":{"command":"old"}}}"#
            .write(to: claudeURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand(scanHistoryStore: nil).run(args: [
            "config", "connect-all", "preview",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(claudeURL.path)",
            "--target-source", "codex:\(codexURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config connect-all preview"))
        XCTAssertTrue(result.stdout.contains("2 bindings from Hermes"))
        XCTAssertTrue(result.stdout.contains("Target sources: 2"))
        XCTAssertTrue(result.stdout.contains("Claude"))
        XCTAssertTrue(result.stdout.contains("Codex"))
        XCTAssertTrue(result.stdout.contains(#"GITHUB_PERSONAL_ACCESS_TOKEN" : "${GITHUB_PERSONAL_ACCESS_TOKEN}""#))
        XCTAssertTrue(result.stdout.contains(#"GITHUB_PERSONAL_ACCESS_TOKEN = "${GITHUB_PERSONAL_ACCESS_TOKEN}""#))
        XCTAssertFalse(result.stdout.contains("ghp_connectallpreview1234567890"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: codexURL.path))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigConnectAllApplyDryRunDoesNotWriteTargets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("cursor/mcp.json")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand(scanHistoryStore: nil).run(args: [
            "config", "connect-all", "apply",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "cursor:\(targetURL.path)",
            "--dry-run"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config connect-all apply dry run"))
        XCTAssertTrue(result.stdout.contains("1 binding from Hermes"))
        XCTAssertTrue(result.stdout.contains("Will create missing config: yes"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigConnectAllPreviewCanUseEndpointBackedHTTPClient() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: endpointStore).start(token: "command-connect-all-token")
        defer { runtime.stop() }

        let result = try MCPHQCommand(scanHistoryStore: nil).run(args: [
            "config", "connect-all", "preview",
            "--endpoint-file", endpointStore.fileURL.path,
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(targetURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config connect-all preview"))
        XCTAssertTrue(result.stdout.contains("1 binding from Hermes"))
        XCTAssertTrue(result.stdout.contains("Target sources: 1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigConnectAllApplyPrintsVerificationReport() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand(scanHistoryStore: nil).run(args: [
            "config", "connect-all", "apply",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(targetURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config connect-all apply"))
        XCTAssertTrue(result.stdout.contains("Verification:"))
        XCTAssertTrue(result.stdout.contains("1 of 1 target source configured and parseable"))
        XCTAssertTrue(result.stdout.contains("does not prove each external agent is using the changed config"))
        XCTAssertTrue(result.stdout.contains("Verification matrix:"))
        XCTAssertTrue(result.stdout.contains("| memory | configured | not run |"))
        XCTAssertTrue(result.stdout.contains("Claude: configured (1/1 bindings)"))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigConnectAllApplyCanRunProbeVerification() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(
            scanHistoryStore: nil,
            liveProbeProvider: { servers in
                servers.map {
                    MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 2, message: "tools/list succeeded")
                }
            }
        )

        let result = try command.run(args: [
            "config", "connect-all", "apply",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(targetURL.path)",
            "--probe"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Config connect-all apply"))
        XCTAssertTrue(result.stdout.contains("1 of 1 target source passed live probe verification"))
        XCTAssertTrue(result.stdout.contains("| memory | configured | probeable |"))
        XCTAssertTrue(result.stdout.contains("Probe: healthy - Live probes: 1 healthy, 0 warning, 0 error, 0 skipped, 0 missing of 1 expected binding."))
        XCTAssertEqual(result.stderr, "")
    }

    func testConfigConnectAllApplyPersistsRollbackTransactionAndRollbackCommandUsesIt() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let targetURL = tempDirectory.appendingPathComponent("claude.json")
        let createdURL = tempDirectory.appendingPathComponent("cursor/mcp.json")
        let originalClaude = #"{"mcpServers":{"old":{"command":"old-runner"}}}"#
        try originalClaude.write(to: targetURL, atomically: true, encoding: .utf8)
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)
        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let command = MCPHQCommand(scanHistoryStore: store)

        let apply = try command.run(args: [
            "config", "connect-all", "apply",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(targetURL.path)",
            "--target-source", "cursor:\(createdURL.path)"
        ])

        XCTAssertEqual(apply.exitCode, 0)
        let transactions = try store.listBulkRollbackTransactions(status: "available")
        let transaction = try XCTUnwrap(transactions.first)
        XCTAssertEqual(transaction.plan.targets.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertTrue(try String(contentsOf: targetURL, encoding: .utf8).contains("memory"))

        let registry = try command.run(args: ["registry", "rollbacks"])
        XCTAssertEqual(registry.exitCode, 0)
        XCTAssertTrue(registry.stdout.contains(transaction.transactionID))
        XCTAssertTrue(registry.stdout.contains("Status: available"))

        let rollback = try command.run(args: [
            "config", "connect-all", "rollback",
            "--transaction-id", transaction.transactionID
        ])

        XCTAssertEqual(rollback.exitCode, 0)
        XCTAssertTrue(rollback.stdout.contains("Config connect-all rollback"))
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), originalClaude)
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(try store.loadBulkRollbackTransaction(transaction.transactionID)?.status, "rolledBack")
    }

    func testConfigConnectAllCanSaveAndReuseTargetProfile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let templateURL = tempDirectory.appendingPathComponent("hermes.yaml")
        let claudeURL = tempDirectory.appendingPathComponent("claude.json")
        let codexURL = tempDirectory.appendingPathComponent("codex.toml")
        try """
        mcp_servers:
          memory:
            command: npx
            args:
              - -y
              - "@modelcontextprotocol/server-memory"
        """.write(to: templateURL, atomically: true, encoding: .utf8)
        try #"{"mcpServers":{}}"#.write(to: claudeURL, atomically: true, encoding: .utf8)

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let command = MCPHQCommand(scanHistoryStore: store)

        let save = try command.run(args: [
            "config", "connect-all", "preview",
            "--template-source", "hermes:\(templateURL.path)",
            "--target-source", "claude:\(claudeURL.path)",
            "--target-source", "codex:\(codexURL.path)",
            "--save-profile", "local-dev"
        ])

        XCTAssertEqual(save.exitCode, 0)
        XCTAssertTrue(save.stdout.contains("Saved target profile: local-dev (2 target sources)"))
        let storedProfile = try XCTUnwrap(store.loadConnectAllTargetProfile(name: "local-dev"))
        XCTAssertEqual(storedProfile.targetSources.map(\.id), ["claude:\(claudeURL.path)", "codex:\(codexURL.path)"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: codexURL.path))

        let reuse = try command.run(args: [
            "config", "connect-all", "preview",
            "--template-source", "hermes:\(templateURL.path)",
            "--profile", "local-dev"
        ])

        XCTAssertEqual(reuse.exitCode, 0)
        XCTAssertTrue(reuse.stdout.contains("Config connect-all preview"))
        XCTAssertTrue(reuse.stdout.contains("Target sources: 2"))
        XCTAssertTrue(reuse.stdout.contains("Source: claude:\(claudeURL.path)"))
        XCTAssertTrue(reuse.stdout.contains("Source: codex:\(codexURL.path)"))

        let registry = try command.run(args: ["registry", "target-profiles"])
        XCTAssertEqual(registry.exitCode, 0)
        XCTAssertTrue(registry.stdout.contains("MCP-HQ registry Connect All target profiles"))
        XCTAssertTrue(registry.stdout.contains("local-dev (2 targets)"))
        XCTAssertTrue(registry.stdout.contains("claude:\(claudeURL.path)"))
        XCTAssertTrue(registry.stdout.contains("codex:\(codexURL.path)"))
    }

    func testControlStatusUsesLocalControlClientAndCountsProbeErrors() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "remote": {
              "url": "http://localhost:40404/mcp"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let command = MCPHQCommand(liveProbeProvider: { servers in
            servers.map { MCPProbeResult(serverID: $0.id, status: .error, message: "HTTP MCP probe could not connect") }
        })

        let result = try command.run(args: ["control", "status", "--json", "--probe", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["serverCount"] as? Int, 1)
        XCTAssertEqual(object["issueCount"] as? Int, 1)
        XCTAssertEqual(object["errorCount"] as? Int, 1)
        XCTAssertEqual(result.stderr, "")
    }

    func testControlStatusCanUseEndpointBackedHTTPClient() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(endpointStore: endpointStore).start(token: "command-client-token")
        defer { runtime.stop() }

        let result = try MCPHQCommand().run(args: [
            "control", "status",
            "--json",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(configURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["serverCount"] as? Int, 1)
        XCTAssertEqual(result.stderr, "")
    }

    func testControlStatusTextShowsHealthCacheMetadataFromEndpoint() throws {
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
        let scanDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(
            endpointStore: endpointStore,
            clientFactory: {
                LocalControlInProcessClient(router: LocalControlRouter(
                    defaultSourceProvider: sourceProvider,
                    healthCacheStore: JSONHealthCacheStore(fileURL: tempDirectory.appendingPathComponent("health-cache.json")),
                    now: { scanDate }
                ))
            }
        ).start(token: "cache-status-token")
        defer { runtime.stop() }
        let command = MCPHQCommand(now: { Date(timeIntervalSince1970: 1_700_000_012) })

        let scan = try command.run(args: ["scan", "--endpoint-file", endpointStore.fileURL.path])
        try #"{"mcpServers":{"memory":{"command":"npx"},"github":{"command":"npx"}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let status = try command.run(args: ["control", "status", "--endpoint-file", endpointStore.fileURL.path])

        XCTAssertEqual(scan.exitCode, 0)
        XCTAssertEqual(status.exitCode, 0)
        XCTAssertTrue(status.stdout.contains("Servers: 1"))
        XCTAssertTrue(status.stdout.contains("Scanned at: 2023-11-14T22:13:20Z"))
        XCTAssertTrue(status.stdout.contains("Cache age: 0s"))
        XCTAssertTrue(status.stdout.contains("Health cache: served from cache"))
        XCTAssertTrue(status.stdout.contains("Cache freshness: fresh"))
        XCTAssertTrue(status.stdout.contains("Scan status: completed"))
    }

    func testControlLaunchAgentBootstrapUsesInjectedLaunchctlRunner() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        final class CommandRecorder: @unchecked Sendable {
            var command: [String] = []
        }
        let recorder = CommandRecorder()
        let command = MCPHQCommand(launchAgentCommandRunner: { launchctlCommand in
            recorder.command = launchctlCommand
            return LocalControlLaunchAgentCommandResult(
                command: launchctlCommand,
                exitCode: 0,
                stdout: "bootstrapped"
            )
        })

        let result = try command.run(args: [
            "control", "launch-agent", "bootstrap",
            "--launch-agents-dir", tempDirectory.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("LaunchAgent bootstrap"))
        XCTAssertTrue(result.stdout.contains("Exit code: 0"))
        XCTAssertEqual(recorder.command[0], "/bin/launchctl")
        XCTAssertEqual(recorder.command[1], "bootstrap")
        XCTAssertEqual(recorder.command[3], tempDirectory.appendingPathComponent("com.mcphq.control.plist").path)
        XCTAssertEqual(result.stderr, "")
    }

    func testControlLaunchAgentStatusChecksLaunchdAndRedactsOutput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try "plist".write(
            to: tempDirectory.appendingPathComponent("com.mcphq.control.plist"),
            atomically: true,
            encoding: .utf8
        )
        let endpointURL = tempDirectory.appendingPathComponent("control-endpoint.json")
        try LocalControlEndpointStore(fileURL: endpointURL).save(LocalControlEndpoint(
            baseURL: "http://127.0.0.1:37373",
            controlPath: "/api/v1/control",
            token: "mcphq_commandSecret1234567890",
            pid: 4321,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let command = MCPHQCommand(launchAgentCommandRunner: { launchctlCommand in
            LocalControlLaunchAgentCommandResult(
                command: launchctlCommand,
                exitCode: 0,
                stdout: "token=mcphq_commandSecret1234567890"
            )
        })

        let result = try command.run(args: [
            "control", "launch-agent", "status",
            "--launch-agents-dir", tempDirectory.path,
            "--endpoint-file", endpointURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Installed: yes"))
        XCTAssertTrue(result.stdout.contains("Launchd: loaded"))
        XCTAssertTrue(result.stdout.contains("PID: 4321"))
        XCTAssertTrue(result.stdout.contains("token=<redacted>"))
        XCTAssertFalse(result.stdout.contains("mcphq_commandSecret"))
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryListCommandPrintsSQLiteRunSummaries() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: tempDirectory.appendingPathComponent("claude.json").path)
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: source.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        _ = try store.save(ScanResult(servers: [], sources: [source]), scannedAt: Date(timeIntervalSince1970: 10))
        _ = try store.save(ScanResult(servers: [server], sources: [source]), scannedAt: Date(timeIntervalSince1970: 20))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["history", "list", "--limit", "1"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ history"))
        XCTAssertTrue(result.stdout.contains("1970-01-01T00:00:20Z"))
        XCTAssertTrue(result.stdout.contains("Servers: 1"))
        XCTAssertFalse(result.stdout.contains("1970-01-01T00:00:10Z"))
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryListCommandEmitsJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .pi, path: tempDirectory.appendingPathComponent("pi.json").path)
        _ = try store.save(ScanResult(servers: [], sources: [source]), scannedAt: Date(timeIntervalSince1970: 30))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["history", "list", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["sourceCount"] as? Int, 1)
        XCTAssertEqual(array.first?["serverCount"] as? Int, 0)
        XCTAssertEqual(array.first?["scannedAt"] as? String, "1970-01-01T00:00:30Z")
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryShowCommandPrintsStoredRunDetails() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: tempDirectory.appendingPathComponent("claude.json").path)
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: source.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github", "--token", "ghp_historyTextSecret1234567890"],
            envBindings: ["GITHUB_TOKEN": "ghp_historyTextSecret1234567890"],
            sourcePath: source.path
        )
        let runID = try store.save(ScanResult(servers: [server], sources: [source]), scannedAt: Date(timeIntervalSince1970: 40))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["history", "show", runID])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ history run"))
        XCTAssertTrue(result.stdout.contains("Run: \(runID)"))
        XCTAssertTrue(result.stdout.contains("Scanned at: 1970-01-01T00:00:40Z"))
        XCTAssertTrue(result.stdout.contains("github"))
        XCTAssertTrue(result.stdout.contains("GITHUB_TOKEN=<redacted>"))
        XCTAssertFalse(result.stdout.contains("ghp_historyTextSecret"))
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryShowCommandEmitsRedactedJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .pi, path: tempDirectory.appendingPathComponent("pi.json").path)
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .pi, sourcePath: source.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": "ghp_historyJSONSecret1234567890"],
            sourcePath: source.path
        )
        let runID = try store.save(ScanResult(servers: [server], sources: [source]), scannedAt: Date(timeIntervalSince1970: 50))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["history", "show", runID, "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("ghp_historyJSONSecret"))
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["runID"] as? String, runID)
        XCTAssertEqual(object["scannedAt"] as? String, "1970-01-01T00:00:50Z")
        let scan = try XCTUnwrap(object["scan"] as? [String: Any])
        let servers = try XCTUnwrap(scan["servers"] as? [[String: Any]])
        let env = try XCTUnwrap(servers.first?["envBindings"] as? [String: String])
        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryDoctorCommandListsStoredDoctorReportSummaries() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .warning,
                category: .server,
                agentName: "Claude",
                sourcePath: "/tmp/claude.json",
                serverID: "claude:/tmp/claude.json:github",
                serverName: "github",
                title: "Command missing",
                whyItMatters: "The server cannot launch",
                suggestedFix: "Install npx"
            )
        ])
        _ = try store.saveDoctorReport(report, scannedAt: Date(timeIntervalSince1970: 60), reportedAt: Date(timeIntervalSince1970: 70))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["history", "doctor", "--limit", "1"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ Doctor history"))
        XCTAssertTrue(result.stdout.contains("1970-01-01T00:01:10Z"))
        XCTAssertTrue(result.stdout.contains("Warnings: 1"))
        XCTAssertTrue(result.stdout.contains("Servers: 1"))
        XCTAssertEqual(result.stderr, "")
    }

    func testHistoryDoctorCommandShowsStoredReportAsTextAndJSONWithoutSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .error,
                category: .probe,
                agentName: "Pi",
                sourcePath: "/tmp/pi.json",
                serverID: "pi:/tmp/pi.json:github",
                serverName: "github",
                title: "Probe failed with ghp_doctorHistorySecret1234567890",
                whyItMatters: "The server cannot be inspected",
                suggestedFix: "Check token ghp_doctorHistorySecret1234567890"
            )
        ])
        let runID = try store.saveDoctorReport(report, scannedAt: Date(timeIntervalSince1970: 80), reportedAt: Date(timeIntervalSince1970: 90))
        let command = MCPHQCommand(scanHistoryStore: store)

        let text = try command.run(args: ["history", "doctor", runID])

        XCTAssertEqual(text.exitCode, 0)
        XCTAssertTrue(text.stdout.contains("MCP-HQ Doctor history report"))
        XCTAssertTrue(text.stdout.contains("Run: \(runID)"))
        XCTAssertTrue(text.stdout.contains("Scanned at: 1970-01-01T00:01:20Z"))
        XCTAssertTrue(text.stdout.contains("Reported at: 1970-01-01T00:01:30Z"))
        XCTAssertTrue(text.stdout.contains("<redacted>"))
        XCTAssertFalse(text.stdout.contains("ghp_doctorHistorySecret"))
        XCTAssertEqual(text.stderr, "")

        let json = try command.run(args: ["history", "doctor", runID, "--json"])

        XCTAssertEqual(json.exitCode, 0)
        XCTAssertFalse(json.stdout.contains("ghp_doctorHistorySecret"))
        let data = try XCTUnwrap(json.stdout.data(using: String.Encoding.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["runID"] as? String, runID)
        XCTAssertEqual(object["reportedAt"] as? String, "1970-01-01T00:01:30Z")
        let doctor = try XCTUnwrap(object["doctor"] as? [String: Any])
        let findings = try XCTUnwrap(doctor["findings"] as? [[String: Any]])
        let firstFinding = try XCTUnwrap(findings.first)
        XCTAssertEqual(firstFinding["severity"] as? String, "error")
        XCTAssertEqual(json.stderr, "")
    }

    func testRegistrySourcesCommandPrintsControlPlaneRows() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .cursor, path: tempDirectory.appendingPathComponent("cursor.json").path)
        _ = try store.save(
            ScanResult(
                servers: [],
                sources: [source],
                sourceHealth: [ConfigSourceHealth(source: source, state: .missing, message: "Cursor config is missing")]
            ),
            scannedAt: Date(timeIntervalSince1970: 60)
        )
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["registry", "sources"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ registry sources"))
        XCTAssertTrue(result.stdout.contains("Cursor missing"))
        XCTAssertTrue(result.stdout.contains(source.path))
        XCTAssertTrue(result.stdout.contains("1970-01-01T00:01:00Z"))
        XCTAssertEqual(result.stderr, "")
    }

    func testRegistryDesiredCommandEmitsRedactedJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let source = ConfigSource(agent: .claude, path: tempDirectory.appendingPathComponent("claude.json").path)
        let server = ServerDefinition(
            id: "template:github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": "ghp_registryJSONSecret1234567890"],
            sourcePath: "/tmp/template.yaml"
        )
        try store.upsertDesiredServerStates([server], for: source, enabled: true, updatedAt: Date(timeIntervalSince1970: 70))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["registry", "desired", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("ghp_registryJSONSecret"))
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["serverName"] as? String, "github")
        XCTAssertEqual(array.first?["enabled"] as? Bool, true)
        let encodedServer = try XCTUnwrap(array.first?["server"] as? [String: Any])
        let env = try XCTUnwrap(encodedServer["envBindings"] as? [String: String])
        XCTAssertEqual(env["GITHUB_TOKEN"], "<redacted>")
        XCTAssertEqual(result.stderr, "")
    }

    func testRegistryRuntimesCommandPrintsPersistedRuntimeRows() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        try store.upsertRuntimeInstance(
            RuntimeInstance(
                id: "hub:memory",
                serverID: "memory",
                pid: 8080,
                ownership: .hubOwned,
                commandLine: "npx memory",
                status: .healthy,
                logPath: "/tmp/memory.log"
            ),
            updatedAt: Date(timeIntervalSince1970: 80)
        )
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["registry", "runtimes"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ registry runtimes"))
        XCTAssertTrue(result.stdout.contains("hub:memory healthy"))
        XCTAssertTrue(result.stdout.contains("Ownership: hubOwned"))
        XCTAssertTrue(result.stdout.contains("PID: 8080"))
        XCTAssertTrue(result.stdout.contains("1970-01-01T00:01:20Z"))
        XCTAssertEqual(result.stderr, "")
    }

    func testRegistrySecretsCommandEmitsSecretBindingJSONWithoutPlaintext() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        let sourcePath = tempDirectory.appendingPathComponent("claude.json").path
        let plaintextSecret = "ghp_registrySecretBinding1234567890"
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: sourcePath, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": plaintextSecret],
            sourcePath: sourcePath
        )
        try store.upsertSecretBindings(
            SecretDetector().detect(in: server),
            status: "stored",
            updatedAt: Date(timeIntervalSince1970: 90)
        )
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["registry", "secrets", "--json", "--source", "claude:\(sourcePath)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains(plaintextSecret))
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["sourcePath"] as? String, sourcePath)
        XCTAssertEqual(array.first?["fieldName"] as? String, "GITHUB_TOKEN")
        XCTAssertEqual(array.first?["status"] as? String, "stored")
        XCTAssertEqual(result.stderr, "")
    }

    func testRuntimeExplainCommandPrintsReadOnlyLifecycleExplanation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"github":{"command":"npx","args":["-y","@modelcontextprotocol/server-github"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let processScanner = MCPProcessScanner(processProvider: {
            [RawProcessSnapshot(pid: 9001, commandLine: "npx -y @modelcontextprotocol/server-github --token ghp_runtimeCommandSecret1234567890")]
        })
        let command = MCPHQCommand(processScanner: processScanner)

        let result = try command.run(args: ["runtime", "explain", "--source", "claude:\(configURL.path)"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ runtime"))
        XCTAssertTrue(result.stdout.contains("Read-only external runtime"))
        XCTAssertTrue(result.stdout.contains("stop: disabled"))
        XCTAssertFalse(result.stdout.contains("ghp_runtimeCommandSecret"))
        XCTAssertEqual(result.stderr, "")
    }

    func testRuntimeExplainCommandIncludesPersistedHubOwnedRows() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let store = SQLiteScanHistoryStore(databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"))
        try store.upsertRuntimeInstance(RuntimeInstance(
            id: "hub:memory",
            serverID: "memory",
            pid: 7777,
            ownership: .hubOwned,
            commandLine: "npx -y @modelcontextprotocol/server-memory",
            status: .healthy,
            logPath: tempDirectory.appendingPathComponent("memory.log").path
        ))
        let command = MCPHQCommand(scanHistoryStore: store)

        let result = try command.run(args: ["runtime", "explain"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hub:memory"))
        XCTAssertTrue(result.stdout.contains("ownership: Hub-owned"))
        XCTAssertTrue(result.stdout.contains("status: degraded"))
        XCTAssertTrue(result.stdout.contains("Log tail available"))
    }

    func testRuntimeExplainCanUseEndpointBackedHTTPClient() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let router = LocalControlRouter(scanCoordinator: ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: {
                [RawProcessSnapshot(pid: 9876, commandLine: "npx -y @modelcontextprotocol/server-memory --token ghp_runtimeEndpointSecret1234567890")]
            })
        ))
        let adapter = LocalControlHTTPAdapter(
            client: LocalControlInProcessClient(router: router),
            authToken: "runtime-client-token"
        )
        let server = LocalControlLoopbackHTTPServer(adapter: adapter)
        try server.start()
        defer { server.stop() }
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        try endpointStore.save(LocalControlEndpoint(
            baseURL: server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: "runtime-client-token",
            pid: 1234,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let result = try MCPHQCommand().run(args: [
            "runtime", "explain",
            "--json",
            "--endpoint-file", endpointStore.fileURL.path,
            "--source", "claude:\(configURL.path)"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let first = try XCTUnwrap(objects.first)
        XCTAssertEqual(first["pid"] as? Int, 9876)
        XCTAssertEqual(first["ownership"] as? String, "agentOwned")
        XCTAssertFalse(result.stdout.contains("ghp_runtimeEndpointSecret"))
        XCTAssertFalse(result.stdout.contains("runtime-client-token"))
        XCTAssertEqual(result.stderr, "")
    }

    func testRuntimeStartAndStopUseEndpointBackedHelper() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"/bin/echo","args":["hello"]}}}"#
            .write(to: configURL, atomically: true, encoding: .utf8)
        let logDirectory = tempDirectory.appendingPathComponent("logs", isDirectory: true)
        let handle = CommandFakeRuntimeProcessHandle(pid: 6161)
        let supervisor = HubRuntimeSupervisor(
            launcher: CommandFakeRuntimeProcessLauncher(handle: handle),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let router = LocalControlRouter(runtimeSupervisor: supervisor)
        let endpointStore = LocalControlEndpointStore(fileURL: tempDirectory.appendingPathComponent("control-endpoint.json"))
        let runtime = try LocalControlServerLauncher(
            endpointStore: endpointStore,
            clientFactory: {
                LocalControlInProcessClient(router: router)
            }
        ).start(token: "runtime-action-token")
        defer { runtime.stop() }
        let command = MCPHQCommand()

        let started = try command.run(args: [
            "runtime", "start",
            "--source", "claude:\(configURL.path)",
            "--server", "memory",
            "--log-directory", logDirectory.path,
            "--endpoint-file", endpointStore.fileURL.path,
        ])
        let runtimeID = try XCTUnwrap(started.stdout
            .split(separator: "\n")
            .first { $0.hasPrefix("Runtime: ") }?
            .replacingOccurrences(of: "Runtime: ", with: ""))
        let stopped = try command.run(args: [
            "runtime", "stop",
            "--runtime-id", runtimeID,
            "--endpoint-file", endpointStore.fileURL.path,
        ])

        XCTAssertEqual(started.exitCode, 0)
        XCTAssertTrue(started.stdout.contains("MCP-HQ runtime start"))
        XCTAssertTrue(started.stdout.contains("Runtime: hub:"))
        XCTAssertTrue(started.stdout.contains("PID: 6161"))
        XCTAssertFalse(started.stdout.contains("runtime-action-token"))
        XCTAssertEqual(stopped.exitCode, 0)
        XCTAssertTrue(stopped.stdout.contains("MCP-HQ runtime stop"))
        XCTAssertTrue(stopped.stdout.contains("Status: stopped"))
        XCTAssertTrue(handle.didTerminate)
    }

    func testRuntimeStartRequiresEndpointBackedHelper() throws {
        let result = try MCPHQCommand().run(args: [
            "runtime", "start",
            "--source", "claude:/tmp/claude.json",
            "--server", "memory",
            "--log-directory", "/tmp/logs",
        ])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("requires --endpoint-file"))
    }

    func testLogsCommandTailsAndRedactsFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let logURL = tempDirectory.appendingPathComponent("server.log")
        try """
        first
        api_key=sk-commandLogSecret1234567890
        final
        """.write(to: logURL, atomically: true, encoding: .utf8)

        let result = try MCPHQCommand(logTailer: RuntimeLogTailer(now: { Date(timeIntervalSince1970: 0) })).run(args: [
            "logs", "--file", logURL.path, "--runtime-id", "runtime-1", "--lines", "2"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("MCP-HQ logs"))
        XCTAssertTrue(result.stdout.contains("Runtime: runtime-1"))
        XCTAssertTrue(result.stdout.contains("api_key=<redacted>"))
        XCTAssertTrue(result.stdout.contains("final"))
        XCTAssertFalse(result.stdout.contains("sk-commandLogSecret"))
        XCTAssertEqual(result.stderr, "")
    }

    func testUnknownCommandReturnsUsageError() throws {
        let result = try MCPHQCommand().run(args: ["bogus"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }
}

private final class CommandFakeRuntimeProcessHandle: RuntimeProcessHandle {
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

private final class CommandFakeRuntimeProcessLauncher: RuntimeProcessLaunching {
    private let handle: CommandFakeRuntimeProcessHandle

    init(handle: CommandFakeRuntimeProcessHandle) {
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
