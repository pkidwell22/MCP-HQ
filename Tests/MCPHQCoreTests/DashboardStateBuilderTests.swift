import XCTest
@testable import MCPHQCore

final class DashboardStateBuilderTests: XCTestCase {
    func testBuildsDashboardSummaryRowsAndIssuesFromScanResult() {
        let claudeSource = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let hermesSource = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "github",
                    displayName: "GitHub",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-github"],
                    envBindings: [
                        "GITHUB_TOKEN": "fake-secret-token-1234567890",
                        "SAFE_REFERENCE": "${GITHUB_TOKEN}",
                    ],
                    sourcePath: claudeSource.path
                ),
                ServerDefinition(
                    id: "docs",
                    displayName: "Docs",
                    transport: .sse,
                    url: "http://localhost:8181/mcp",
                    sourcePath: hermesSource.path
                ),
            ],
            sources: [claudeSource, hermesSource],
            issues: [
                ScanIssue(source: hermesSource, severity: .warning, message: "Unsupported agent config parser: hermes")
            ],
            processes: [
                MCPProcessSnapshot(
                    pid: 1201,
                    executableName: "npx",
                    commandLine: "npx -y @modelcontextprotocol/server-github --token <redacted>",
                    matchReason: "mcp command pattern",
                    cpuPercent: 2.5,
                    memoryBytes: 4_194_304
                )
            ],
            processMatches: [ServerProcessMatch(
                serverID: "github",
                processID: 1201,
                confidence: .high,
                reason: "command and MCP-specific argument matched"
            )]
        )

        let state = DashboardStateBuilder().build(from: result)

        XCTAssertEqual(state.summary.serverCount, 2)
        XCTAssertEqual(state.summary.processCount, 1)
        XCTAssertEqual(state.summary.sourceCount, 2)
        XCTAssertEqual(state.summary.issueCount, 1)
        XCTAssertEqual(state.summary.warningCount, 1)
        XCTAssertEqual(state.summary.errorCount, 0)
        XCTAssertEqual(state.summary.statusText, "2 servers • 1 process • 2 sources • 1 warning")

        XCTAssertEqual(state.serverRows.map(\.displayName), ["Docs", "GitHub"])
        XCTAssertEqual(state.serverRows[0].connectionSummary, "sse • http://localhost:8181/mcp")
        XCTAssertEqual(state.serverRows[1].connectionSummary, "stdio • npx -y @modelcontextprotocol/server-github")
        XCTAssertEqual(state.serverRows[1].processSummary, "Matched pid 1201 • high")
        XCTAssertEqual(state.serverRows[1].toolSummary, "Probe not run")
        XCTAssertEqual(state.serverRows[1].envSummary, "2 env vars")
        XCTAssertEqual(state.serverRows[1].redactedEnvBindings["GITHUB_TOKEN"], "<redacted>")
        XCTAssertEqual(state.serverRows[1].redactedEnvBindings["SAFE_REFERENCE"], "${GITHUB_TOKEN}")

        XCTAssertEqual(state.issueRows.count, 1)
        XCTAssertEqual(state.issueRows[0].agentName, "hermes")
        XCTAssertEqual(state.issueRows[0].severityLabel, "warning")
        XCTAssertEqual(state.issueRows[0].message, "Unsupported agent config parser: hermes")

        XCTAssertEqual(state.processRows.count, 1)
        XCTAssertEqual(state.processRows[0].pid, 1201)
        XCTAssertEqual(state.processRows[0].executableName, "npx")
        XCTAssertEqual(state.processRows[0].commandLine, "npx -y @modelcontextprotocol/server-github --token <redacted>")
        XCTAssertEqual(state.processRows[0].ownership, .agentOwned)
        XCTAssertEqual(state.processRows[0].resourceSummary, "CPU 2.5% • Memory 4.0 MB")
    }

    func testBuildsEmptyStateWhenNoConfigsExist() {
        let state = DashboardStateBuilder().build(from: ScanResult(servers: [], sources: [], issues: []))

        XCTAssertEqual(state.summary.statusText, "No MCP configs found")
        XCTAssertEqual(state.serverRows, [])
        XCTAssertEqual(state.processRows, [])
        XCTAssertEqual(state.issueRows, [])
    }

    func testBuildsSourceHealthRowsAndGroupsInventoryByAgentSource() {
        let codexSource = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let hermesSource = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let missingSource = ConfigSource(agent: .opencode, path: "/tmp/opencode.json")
        let result = ScanResult(
            servers: [
                ServerDefinition(id: "codex:one", displayName: "node_repl", transport: .stdio, command: "node", sourcePath: codexSource.path),
                ServerDefinition(id: "hermes:one", displayName: "github", transport: .stdio, command: "npx", sourcePath: hermesSource.path),
            ],
            sources: [codexSource, hermesSource],
            sourceHealth: [
                ConfigSourceHealth(source: codexSource, state: .parsed, serverCount: 1, message: "Found config • parsed 1 server"),
                ConfigSourceHealth(source: hermesSource, state: .parsed, serverCount: 1, message: "Found config • parsed 1 server"),
                ConfigSourceHealth(source: missingSource, state: .missing, message: "OpenCode config missing"),
            ]
        )

        let state = DashboardStateBuilder().build(from: result)

        XCTAssertEqual(state.summary.sourceCount, 3)
        XCTAssertEqual(state.sourceRows.map(\.agentName), ["Codex", "Hermes", "OpenCode"])
        XCTAssertEqual(state.sourceRows.map(\.stateLabel), ["Parsed", "Parsed", "Missing"])
        XCTAssertEqual(state.serverSections.map(\.agentName), ["Codex", "Hermes"])
        XCTAssertEqual(state.serverSections[0].serverRows.map(\.displayName), ["node_repl"])
        XCTAssertEqual(state.serverRows.first { $0.displayName == "github" }?.agentName, "Hermes")
    }

    func testNeverExposesRawSecretValuesInDashboardRows() {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "github",
                displayName: "GitHub",
                transport: .stdio,
                command: "mcp-server-github",
                envBindings: ["GITHUB_TOKEN": "fake-secret-token-1234567890"],
                sourcePath: "/tmp/claude.json"
            )],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")]
        )

        let state = DashboardStateBuilder().build(from: result)
        let row = try! XCTUnwrap(state.serverRows.first)

        XCTAssertEqual(row.redactedEnvBindings["GITHUB_TOKEN"], "<redacted>")
        XCTAssertFalse(String(describing: state).contains("fake-secret-token-1234567890"))
    }

    func testBuildsToolSummaryFromHealthyProbeResult() throws {
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "memory",
                displayName: "Memory",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                sourcePath: "/tmp/claude.json"
            )],
            sources: [ConfigSource(agent: .claude, path: "/tmp/claude.json")],
            probeResults: [MCPProbeResult(serverID: "memory", status: .healthy, toolCount: 9, message: "tools/list succeeded")]
        )

        let state = DashboardStateBuilder().build(from: result)
        let row = try XCTUnwrap(state.serverRows.first)

        XCTAssertEqual(row.toolSummary, "Healthy • 9 tools")
    }

    func testDashboardSummaryCountsProbeFailures() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let result = ScanResult(
            servers: [
                ServerDefinition(id: "remote", displayName: "Remote", transport: .http, url: "http://localhost:40404/mcp", sourcePath: source.path),
                ServerDefinition(id: "flaky", displayName: "Flaky", transport: .stdio, command: "npx", sourcePath: source.path),
            ],
            sources: [source],
            issues: [
                ScanIssue(source: source, severity: .warning, message: "Missing env var for flaky: TOKEN")
            ],
            probeResults: [
                MCPProbeResult(serverID: "remote", status: .error, message: "HTTP MCP probe could not connect"),
                MCPProbeResult(serverID: "flaky", status: .warning, message: "MCP ping failed"),
            ]
        )

        let state = DashboardStateBuilder().build(from: result)

        XCTAssertEqual(state.summary.issueCount, 3)
        XCTAssertEqual(state.summary.warningCount, 2)
        XCTAssertEqual(state.summary.errorCount, 1)
        XCTAssertEqual(state.summary.statusText, "2 servers • 0 processes • 1 source • 1 error • 2 warnings")
        XCTAssertEqual(StatusMenuSnapshot(state: state, isProbing: false).detailText, "1 source • 1 error • 2 warnings")
    }

    func testDashboardRedactsSecretsInConnectionSummaries() throws {
        let state = DashboardStateBuilder().build(from: ScanResult(
            servers: [
                ServerDefinition(
                    id: "local",
                    displayName: "Local",
                    transport: .stdio,
                    command: "mcp-server-example",
                    args: ["--token", "sk-config-secret-1234567890", "api_key=shortsecret"],
                    sourcePath: "/tmp/local.json"
                ),
                ServerDefinition(
                    id: "remote",
                    displayName: "Remote",
                    transport: .streamableHTTP,
                    url: "https://example.test/mcp?api_key=sk-url-secret-1234567890",
                    sourcePath: "/tmp/remote.json"
                ),
            ],
            sources: [
                ConfigSource(agent: .claude, path: "/tmp/local.json"),
                ConfigSource(agent: .gemini, path: "/tmp/remote.json"),
            ]
        ))

        XCTAssertTrue(state.serverRows.contains { row in
            row.connectionSummary == "stdio • mcp-server-example --token <redacted> api_key=<redacted>"
        })
        XCTAssertTrue(state.serverRows.contains { row in
            row.connectionSummary == "streamable_http • https://example.test/mcp?api_key=<redacted>"
        })
        XCTAssertFalse(String(describing: state).contains("sk-config-secret"))
        XCTAssertFalse(String(describing: state).contains("shortsecret"))
        XCTAssertFalse(String(describing: state).contains("sk-url-secret"))
    }

    func testBuildsServerDetailWithProbeProcessesIssuesAndRedactedEnvironment() throws {
        let suspiciousToolName = "danger-" + "ghp_" + "1234567890abcdef"
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let issue = ScanIssue(source: source, severity: .warning, message: "Missing env var for GitHub: GITHUB_TOKEN")
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "github",
                displayName: "GitHub",
                transport: .stdio,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                envBindings: ["GITHUB_TOKEN": "fake-secret-token-1234567890"],
                sourcePath: source.path
            )],
            sources: [source],
            issues: [issue],
            processes: [MCPProcessSnapshot(
                pid: 4201,
                executableName: "npx",
                commandLine: "npx -y @modelcontextprotocol/server-github --token <redacted>",
                matchReason: "mcp command pattern"
            )],
            processMatches: [ServerProcessMatch(
                serverID: "github",
                processID: 4201,
                confidence: .high,
                reason: "command and MCP-specific argument matched"
            )],
            probeResults: [MCPProbeResult(
                serverID: "github",
                status: .healthy,
                toolCount: 3,
                toolNames: ["create_issue", "search_repositories", suspiciousToolName],
                toolDetails: [
                    MCPToolDetail(
                        name: "create_issue",
                        description: "Create a GitHub issue",
                        inputSchemaSummary: "object • required: owner, repo, title • properties: body, owner, repo, title"
                    ),
                    MCPToolDetail(
                        name: suspiciousToolName,
                        description: "Leaky description token=\(suspiciousToolName)",
                        inputSchemaSummary: "object"
                    ),
                ],
                resourceCount: 2,
                resourceNames: ["Repo docs", suspiciousToolName],
                resourceDetails: [
                    MCPResourceDetail(
                        uri: "file:///repo/README.md",
                        name: "Repo docs",
                        description: "Repository README",
                        mimeType: "text/markdown"
                    ),
                    MCPResourceDetail(
                        uri: "secret://\(suspiciousToolName)",
                        description: "Leaky resource api_key=\(suspiciousToolName)"
                    ),
                ],
                pingSucceeded: true,
                promptCount: 2,
                promptNames: ["draft_issue", suspiciousToolName],
                promptDetails: [
                    MCPPromptDetail(
                        name: "draft_issue",
                        description: "Draft a GitHub issue",
                        argumentSummary: "required: title • optional: body"
                    ),
                    MCPPromptDetail(
                        name: suspiciousToolName,
                        description: "Leaky prompt token=\(suspiciousToolName)",
                        argumentSummary: "required: secret"
                    ),
                ],
                message: "tools/list succeeded"
            )]
        )

        let state = DashboardStateBuilder().build(from: result)
        let detail = try XCTUnwrap(state.serverDetails.first)

        XCTAssertEqual(detail.id, "github")
        XCTAssertEqual(detail.displayName, "GitHub")
        XCTAssertEqual(detail.connectionSummary, "stdio • npx -y @modelcontextprotocol/server-github")
        XCTAssertEqual(detail.toolSummary, "Healthy • 3 tools")
        XCTAssertEqual(detail.resourceSummary, "2 resources")
        XCTAssertEqual(detail.promptSummary, "2 prompts")
        XCTAssertEqual(detail.healthSummary, "MCP ping ok")
        XCTAssertEqual(detail.toolNames, ["create_issue", "search_repositories", "danger-<redacted>"])
        XCTAssertEqual(detail.resourceNames, ["Repo docs", "danger-<redacted>"])
        XCTAssertEqual(detail.promptNames, ["draft_issue", "danger-<redacted>"])
        XCTAssertEqual(detail.toolDetails.map(\.name), ["create_issue", "danger-<redacted>"])
        let createIssue = try XCTUnwrap(detail.toolDetails.first)
        XCTAssertEqual(createIssue.description, "Create a GitHub issue")
        XCTAssertEqual(createIssue.inputSchemaSummary, "object • required: owner, repo, title • properties: body, owner, repo, title")
        let redactedTool = try XCTUnwrap(detail.toolDetails.dropFirst().first)
        XCTAssertEqual(redactedTool.description, "Leaky description token=<redacted>")
        XCTAssertEqual(detail.resourceDetails.map(\.uri), ["file:///repo/README.md", "secret:<redacted>"])
        let redactedResource = try XCTUnwrap(detail.resourceDetails.dropFirst().first)
        XCTAssertEqual(redactedResource.description, "Leaky resource api_key=<redacted>")
        XCTAssertEqual(detail.promptDetails.map(\.name), ["draft_issue", "danger-<redacted>"])
        let redactedPrompt = try XCTUnwrap(detail.promptDetails.dropFirst().first)
        XCTAssertEqual(redactedPrompt.description, "Leaky prompt token=<redacted>")
        XCTAssertEqual(redactedPrompt.argumentSummary, "required: secret")
        XCTAssertEqual(detail.sourcePath, source.path)
        XCTAssertEqual(detail.redactedEnvBindings["GITHUB_TOKEN"], "<redacted>")
        XCTAssertEqual(detail.processRows.map(\.pid), [4201])
        XCTAssertEqual(detail.issueRows.map(\.message), ["Missing env var for GitHub: GITHUB_TOKEN"])
        XCTAssertFalse(String(describing: detail).contains("fake-secret-token-1234567890"))
        XCTAssertFalse(String(describing: detail).contains(suspiciousToolName))
    }

    func testServerDetailDoesNotAttachSiblingServerIssueFromSameSource() throws {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let result = ScanResult(
            servers: [
                ServerDefinition(id: "filesystem", displayName: "filesystem", transport: .stdio, command: "npx", sourcePath: source.path),
                ServerDefinition(id: "github", displayName: "github", transport: .stdio, command: "npx", sourcePath: source.path),
            ],
            sources: [source],
            issues: [ScanIssue(source: source, severity: .warning, message: "Missing env var for github: GITHUB_TOKEN")]
        )

        let state = DashboardStateBuilder().build(from: result)
        let filesystemDetail = try XCTUnwrap(state.serverDetails.first { $0.id == "filesystem" })
        let githubDetail = try XCTUnwrap(state.serverDetails.first { $0.id == "github" })

        XCTAssertTrue(filesystemDetail.issueRows.isEmpty)
        XCTAssertEqual(githubDetail.issueRows.map(\.message), ["Missing env var for github: GITHUB_TOKEN"])
    }

    func testBuildsKeychainRecoveryRowsWithSafeActionsWithoutSecretValues() throws {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let recoveryState = SecretRecoveryState(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: source.path,
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: reference,
            presence: SecretPresenceCheck(
                reference: reference,
                status: .missing,
                message: "Secret token=ghp_recoverySecret1234567890 is missing"
            ),
            previousStatus: "present",
            validatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let result = ScanResult(
            servers: [ServerDefinition(id: "github", displayName: "GitHub", transport: .stdio, command: "npx", sourcePath: source.path)],
            sources: [source]
        )

        let state = DashboardStateBuilder().build(from: result, secretRecoveryReport: SecretRecoveryReport(states: [recoveryState]))

        XCTAssertEqual(state.summary.keychainRecoveryCount, 1)
        XCTAssertEqual(state.summary.warningCount, 1)
        XCTAssertEqual(state.summary.issueCount, 1)
        let row = try XCTUnwrap(state.keychainRecoveryRows.first)
        XCTAssertEqual(row.statusLabel, "Missing")
        XCTAssertEqual(row.primaryActionTitle, "Review Config")
        XCTAssertEqual(row.secondaryActionTitle, "Rerun Validation")
        XCTAssertEqual(row.reviewActionTitle, "Open Migration Review")
        XCTAssertFalse(row.supportsMigrationCleanup)
        XCTAssertTrue(row.guidance.contains("cannot recover an unknown secret value"))
        XCTAssertEqual(row.previousStatus, "present")
        XCTAssertFalse(String(describing: row).contains("ghp_recoverySecret"))
    }

    func testBuildsMigrationWriteFailureRecoveryRowsWithRetryCleanupActions() throws {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let recoveryState = SecretRecoveryState(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: source.path,
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: reference,
            presence: SecretPresenceCheck(
                reference: reference,
                status: .missing,
                message: "Secret token=ghp_recoverySecret1234567890 is missing"
            ),
            previousStatus: SecretRecoveryStatus.migrationWriteFailed.rawValue,
            validatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let state = DashboardStateBuilder().build(
            from: ScanResult(servers: [], sources: [source]),
            secretRecoveryReport: SecretRecoveryReport(states: [recoveryState])
        )

        let row = try XCTUnwrap(state.keychainRecoveryRows.first)
        XCTAssertEqual(row.statusLabel, "Migration write failed")
        XCTAssertEqual(row.primaryActionTitle, "Review Failed Migration")
        XCTAssertEqual(row.secondaryActionTitle, "Rerun After Fix")
        XCTAssertEqual(row.reviewActionTitle, "Open Secret Review")
        XCTAssertTrue(row.supportsMigrationCleanup)
        XCTAssertTrue(row.guidance.contains("removed partial Keychain writes"))
        XCTAssertFalse(String(describing: row).contains("ghp_recoverySecret"))
    }

    func testBuildsSecretRowsWithoutExposingLiteralValues() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "header_Authorization")
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let result = ScanResult(
            servers: [ServerDefinition(
                id: "github",
                displayName: "GitHub",
                transport: .stdio,
                command: "npx",
                headers: ["Authorization": "Bearer \(reference.configValue)"],
                envBindings: ["GITHUB_TOKEN": "ghp_literalSecret1234567890"],
                sourcePath: source.path
            )],
            sources: [source]
        )

        let detail = try XCTUnwrap(DashboardStateBuilder().build(from: result).serverDetails.first)

        XCTAssertEqual(detail.secretRows.map(\.statusLabel), ["Literal secret", "Keychain reference"])
        XCTAssertEqual(detail.secretRows.map(\.name), ["GITHUB_TOKEN", "Authorization"])
        XCTAssertTrue(detail.secretRows.contains { $0.replacementValue == KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN").configValue })
        XCTAssertFalse(String(describing: detail.secretRows).contains("ghp_literalSecret"))
    }
}
