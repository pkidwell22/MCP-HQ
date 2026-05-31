import XCTest
@testable import MCPHQCore

final class DoctorReportTests: XCTestCase {
    func testBuildsDoctorReportFromSourceHealthIssuesAndProbeFailures() throws {
        let missingSource = ConfigSource(agent: .cursor, path: "/tmp/missing.json")
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .hermes, sourcePath: source.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": ""],
            sourcePath: source.path
        )
        let result = ScanResult(
            servers: [server],
            sources: [source],
            sourceHealth: [
                ConfigSourceHealth(source: missingSource, state: .missing, message: "Cursor config missing"),
                ConfigSourceHealth(source: source, state: .parsed, serverCount: 1, message: "Found config • parsed 1 server"),
            ],
            issues: [
                ScanIssue(source: source, severity: .warning, message: "Missing env var for github: GITHUB_TOKEN")
            ],
            probeResults: [
                MCPProbeResult(serverID: server.id, status: .error, message: "initialize failed with token=ghp_1234567890abcdef")
            ]
        )

        let report = DoctorReportBuilder().build(from: result)

        XCTAssertEqual(report.errorCount, 1)
        XCTAssertEqual(report.warningCount, 1)
        XCTAssertEqual(report.infoCount, 1)
        XCTAssertTrue(report.findings.contains { $0.category == .source && $0.agentName == "Cursor" })
        XCTAssertTrue(report.findings.contains { $0.category == .server && $0.serverName == "github" })
        let probeFinding = try XCTUnwrap(report.findings.first { $0.category == .probe })
        XCTAssertEqual(probeFinding.title, "initialize failed with token=<redacted>")
        XCTAssertFalse(String(describing: report).contains("ghp_1234567890abcdef"))
    }

    func testDoctorTextFormatterExplainsWhyAndFix() {
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .warning,
                category: .server,
                agentName: "Hermes",
                sourcePath: "/tmp/hermes.yaml",
                serverName: "github",
                title: "Missing env var for github: GITHUB_TOKEN",
                whyItMatters: "The server likely needs a credential.",
                suggestedFix: "Set the environment variable."
            )
        ])

        let text = DoctorReportFormatter().formatText(report)

        XCTAssertTrue(text.contains("MCP-HQ doctor"))
        XCTAssertTrue(text.contains("[warning] server: Missing env var"))
        XCTAssertTrue(text.contains("why: The server likely needs a credential."))
        XCTAssertTrue(text.contains("fix: Set the environment variable."))
    }

    func testDoctorTextFormatterShowsGroupedSourceServerSeverityCategory() {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .claude, sourcePath: source.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            sourcePath: source.path
        )
        let result = ScanResult(
            servers: [server],
            sources: [source],
            sourceHealth: [
                ConfigSourceHealth(source: source, state: .parsed, serverCount: 1, message: "Found config")
            ],
            issues: [
                ScanIssue(
                    source: source,
                    severity: .error,
                    message: "Missing env var for github: GITHUB_TOKEN"
                )
            ],
            probeResults: [
                MCPProbeResult(
                    serverID: server.id,
                    status: .warning,
                    message: "initialize failed for github"
                )
            ]
        )

        let report = DoctorReportBuilder().build(from: result)
        let text = DoctorReportFormatter().formatText(report)

        XCTAssertTrue(text.contains("source: /tmp/claude.json"))
        XCTAssertTrue(text.contains("server: github"))
        XCTAssertTrue(text.contains("category: server"))
        XCTAssertTrue(text.contains("severity: error"))
        XCTAssertTrue(text.contains("severity: warning"))
    }

    func testIssueFindingsMatchServerWithinIssueSource() throws {
        let firstSource = ConfigSource(agent: .antigravity, path: "/tmp/antigravity.json")
        let secondSource = ConfigSource(agent: .cursor, path: "/tmp/cursor.json")
        let firstGithub = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .antigravity, sourcePath: firstSource.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            sourcePath: firstSource.path
        )
        let secondGithub = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .cursor, sourcePath: secondSource.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            sourcePath: secondSource.path
        )
        let result = ScanResult(
            servers: [firstGithub, secondGithub],
            sources: [firstSource, secondSource],
            sourceHealth: [
                ConfigSourceHealth(source: firstSource, state: .parsed, serverCount: 1, message: "Found config"),
                ConfigSourceHealth(source: secondSource, state: .parsed, serverCount: 1, message: "Found config"),
            ],
            issues: [
                ScanIssue(
                    source: secondSource,
                    severity: .warning,
                    message: "Missing env var for github: GITHUB_PERSONAL_ACCESS_TOKEN referenced by GITHUB_PERSONAL_ACCESS_TOKEN."
                )
            ]
        )

        let report = DoctorReportBuilder().build(from: result)
        let finding = try XCTUnwrap(report.findings.first)

        XCTAssertEqual(finding.agentName, "Cursor")
        XCTAssertEqual(finding.sourcePath, secondSource.path)
        XCTAssertEqual(finding.serverID, secondGithub.id)
        XCTAssertNotEqual(finding.serverID, firstGithub.id)
    }

    func testDoctorJSONFormatterIsRedactedAndMachineReadable() throws {
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .error,
                category: .probe,
                agentName: "Hermes",
                sourcePath: "/tmp/hermes.yaml",
                serverID: "hermes:/tmp/hermes.yaml:github",
                serverName: "github",
                title: "Probe failed with token=ghp_doctorSecret1234567890",
                whyItMatters: "Credential token=ghp_doctorSecret1234567890 failed.",
                suggestedFix: "Rotate token=ghp_doctorSecret1234567890 and rerun."
            )
        ])

        let json = try DoctorReportFormatter().formatJSON(report)
        let decoded = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.errorCount, 1)
        XCTAssertEqual(decoded.findings.first?.title, "Probe failed with token=<redacted>")
        XCTAssertFalse(json.contains("ghp_doctorSecret"))
    }

    func testDoctorReportExporterWritesRedactedChosenDestination() throws {
        let plaintextSecret = "ghp_doctorExportSecret1234567890"
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .error,
                category: .probe,
                agentName: "Hermes",
                sourcePath: "/tmp/hermes.yaml",
                serverID: "hermes:/tmp/hermes.yaml:github",
                serverName: "github",
                title: "Probe failed with token=\(plaintextSecret)",
                whyItMatters: "Credential \(plaintextSecret) failed.",
                suggestedFix: "Rotate \(plaintextSecret)."
            )
        ])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("chosen-doctor-report.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        try DoctorReportExporter().write(report, format: .json, to: destination)
        let exported = try String(contentsOf: destination, encoding: .utf8)

        XCTAssertTrue(exported.contains("<redacted>"))
        XCTAssertFalse(exported.contains(plaintextSecret))
        XCTAssertEqual(DoctorReportExportFormat.json.fileName, "doctor-report.json")
        XCTAssertEqual(DoctorReportExportFormat.text.fileExtension, "txt")
    }

    func testDoctorFindingFilterMatchesSeveritySourceAndServer() throws {
        let githubID = "hermes:/tmp/hermes.yaml:github"
        let linearID = "pi:/tmp/pi.json:linear"
        let report = DoctorReport(findings: [
            DoctorFinding(
                severity: .warning,
                category: .server,
                agentName: "Hermes",
                sourcePath: "/tmp/hermes.yaml",
                serverID: githubID,
                serverName: "github",
                title: "Missing env var for github: GITHUB_TOKEN",
                whyItMatters: "Credential missing.",
                suggestedFix: "Set it."
            ),
            DoctorFinding(
                severity: .error,
                category: .probe,
                agentName: "Pi",
                sourcePath: "/tmp/pi.json",
                serverID: linearID,
                serverName: "linear",
                title: "initialize failed",
                whyItMatters: "Probe failed.",
                suggestedFix: "Check logs."
            ),
            DoctorFinding(
                severity: .info,
                category: .source,
                agentName: "Cursor",
                sourcePath: "/tmp/cursor.json",
                title: "Cursor config is missing",
                whyItMatters: "No config exists.",
                suggestedFix: "Create it."
            ),
        ])

        let warningReport = report.filtered(by: DoctorFindingFilter(severity: .warning))
        XCTAssertEqual(warningReport.findings.compactMap(\.serverID), [githubID])
        XCTAssertEqual(warningReport.warningCount, 1)
        XCTAssertEqual(warningReport.errorCount, 0)

        let piReport = report.filtered(by: DoctorFindingFilter(sourcePath: "/tmp/pi.json"))
        XCTAssertEqual(piReport.findings.compactMap(\.serverID), [linearID])
        XCTAssertEqual(piReport.groups.map(\.sourcePath), ["/tmp/pi.json"])

        let serverReport = report.filtered(by: DoctorFindingFilter(serverID: githubID))
        let serverFinding = try XCTUnwrap(serverReport.findings.first)
        XCTAssertEqual(serverFinding.serverName, "github")
        XCTAssertEqual(serverReport.findings.count, 1)

        let serverCategoryReport = report.filtered(by: DoctorFindingFilter(category: .server))
        XCTAssertEqual(serverCategoryReport.findings.count, 1)
        XCTAssertEqual(serverCategoryReport.findings.first?.serverID, githubID)

        let emptyReport = report.filtered(by: DoctorFindingFilter(severity: .error, sourcePath: "/tmp/hermes.yaml"))
        XCTAssertTrue(emptyReport.findings.isEmpty)
    }

    func testDoctorReportIncludesKeychainRecoveryFindingsWithRedactedStateText() throws {
        let source = ConfigSource(agent: .antigravity, path: "/tmp/antigravity.json")
        let server = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: .antigravity, sourcePath: source.path, name: "github"),
            displayName: "github",
            transport: .stdio,
            command: "npx",
            sourcePath: source.path
        )
        let secret = "ghp_doctorSecretFindings1234567890"
        let recoveryState = SecretRecoveryState(
            secretID: "\(server.id):environment:GITHUB_TOKEN",
            sourcePath: source.path,
            serverName: "github",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: KeychainSecretReference(account: "antigravity/github/GITHUB_TOKEN"),
            presence: SecretPresenceCheck(
                reference: KeychainSecretReference(account: "antigravity/github/GITHUB_TOKEN"),
                status: .missing,
                message: "Missing keychain secret token=\(secret)"
            ),
            validatedAt: nil
        )
        let report = DoctorReportBuilder().build(
            from: ScanResult(servers: [server], sources: [source], sourceHealth: [], issues: [], probeResults: []),
            keychainRecoveryReport: SecretRecoveryReport(states: [recoveryState])
        )

        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.category, .config)
        XCTAssertEqual(finding.serverID, server.id)

        let text = DoctorReportFormatter().formatText(report)
        let json = try DoctorReportFormatter().formatJSON(report)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(json.contains(secret))
    }
}
