import XCTest
@testable import MCPHQCore

final class ServerDiagnosticCheckerTests: XCTestCase {
    func testMissingStdioCommandProducesActionableWarning() {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let server = ServerDefinition(
            id: "broken",
            displayName: "Broken Server",
            transport: .stdio,
            command: "definitely-not-installed-mcp",
            args: ["--serve"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { command, _ in
            command != "definitely-not-installed-mcp"
        })

        let issues = checker.issues(servers: [server], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Command not found for Broken Server: definitely-not-installed-mcp. Install it or update PATH/config before launching this MCP server."
        )])
    }

    func testAvailableStdioCommandProducesNoIssue() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        XCTAssertEqual(checker.issues(servers: [server], sources: [source]), [])
    }

    func testRemoteServersWithoutCommandsAreNotChecked() {
        let source = ConfigSource(agent: .gemini, path: "/tmp/gemini.json")
        let server = ServerDefinition(
            id: "remote-docs",
            displayName: "Remote Docs",
            transport: .sse,
            url: "http://localhost:8181/mcp",
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in
            XCTFail("Remote servers should not ask for command availability")
            return false
        })

        XCTAssertEqual(checker.issues(servers: [server], sources: [source]), [])
    }

    func testServerEnvPathIsPassedToCommandChecker() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: "qmd",
            displayName: "qmd",
            transport: .stdio,
            command: "qmd",
            envBindings: ["PATH": "/custom/bin:/usr/bin"],
            sourcePath: source.path
        )
        var observedPath: String?
        let checker = ServerDiagnosticChecker(commandExists: { _, environment in
            observedPath = environment["PATH"]
            return true
        })

        _ = checker.issues(servers: [server], sources: [source])

        XCTAssertEqual(observedPath, "/custom/bin:/usr/bin")
    }

    func testEmptySensitiveEnvBindingProducesKeychainWarning() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_PERSONAL_ACCESS_TOKEN": ""],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        let issues = checker.issues(servers: [server], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Missing env var for github: GITHUB_PERSONAL_ACCESS_TOKEN. Add it to Keychain or configure the environment before launching this MCP server."
        )])
    }

    func testUnsetEnvironmentReferenceProducesKeychainWarning() {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": "${MISSING_GITHUB_TOKEN}"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(
            commandExists: { _, _ in true },
            environmentValue: { _ in nil }
        )

        let issues = checker.issues(servers: [server], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Missing env var for github: MISSING_GITHUB_TOKEN referenced by GITHUB_TOKEN. Add it to Keychain or configure the environment before launching this MCP server."
        )])
    }

    func testNonSensitiveEnvironmentValuesDoNotProduceSecretWarnings() {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: "qmd",
            displayName: "qmd",
            transport: .stdio,
            command: "qmd",
            envBindings: ["PATH": "/custom/bin", "LOG_LEVEL": ""],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        XCTAssertEqual(checker.issues(servers: [server], sources: [source]), [])
    }

    func testDuplicateStdioServerTargetsProduceWarning() {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let original = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: source.path
        )
        let duplicate = ServerDefinition(
            id: "github-copy",
            displayName: "github-copy",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        let issues = checker.issues(servers: [original, duplicate], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Duplicate MCP server target: github and github-copy both point to stdio npx -y @modelcontextprotocol/server-github. Rename/remove one entry to avoid duplicate tools."
        )])
    }

    func testDistinctStdioArgumentsDoNotProduceDuplicateWarning() {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let github = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: source.path
        )
        let memory = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        XCTAssertEqual(checker.issues(servers: [github, memory], sources: [source]), [])
    }

    func testSameServerTargetAcrossDifferentSourcesDoesNotProduceDuplicateWarning() {
        let claudeSource = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let codexSource = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let claudeGithub = ServerDefinition(
            id: "claude-github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: claudeSource.path
        )
        let codexGithub = ServerDefinition(
            id: "codex-github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: codexSource.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        XCTAssertEqual(
            checker.issues(servers: [claudeGithub, codexGithub], sources: [claudeSource, codexSource]),
            []
        )
    }

    func testDuplicateRemoteServerURLsProduceWarning() {
        let source = ConfigSource(agent: .gemini, path: "/tmp/gemini.json")
        let docs = ServerDefinition(
            id: "docs",
            displayName: "docs",
            transport: .sse,
            url: "http://localhost:8181/sse",
            sourcePath: source.path
        )
        let docsCopy = ServerDefinition(
            id: "docs-copy",
            displayName: "docs-copy",
            transport: .sse,
            url: "http://localhost:8181/sse",
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        let issues = checker.issues(servers: [docs, docsCopy], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Duplicate MCP server target: docs and docs-copy both point to sse http://localhost:8181/sse. Rename/remove one entry to avoid duplicate tools."
        )])
    }

    func testDuplicateTargetWarningsRedactSecretsInArgsAndURLs() {
        let source = ConfigSource(agent: .gemini, path: "/tmp/gemini.json")
        let remote = ServerDefinition(
            id: "remote",
            displayName: "remote",
            transport: .streamableHTTP,
            url: "https://example.test/mcp?api_key=sk-url-secret-1234567890",
            sourcePath: source.path
        )
        let remoteCopy = ServerDefinition(
            id: "remote-copy",
            displayName: "remote-copy",
            transport: .streamableHTTP,
            url: "https://example.test/mcp?api_key=sk-url-secret-1234567890",
            sourcePath: source.path
        )
        let local = ServerDefinition(
            id: "local",
            displayName: "local",
            transport: .stdio,
            command: "mcp-server-example",
            args: ["--token", "sk-arg-secret-1234567890"],
            sourcePath: source.path
        )
        let localCopy = ServerDefinition(
            id: "local-copy",
            displayName: "local-copy",
            transport: .stdio,
            command: "mcp-server-example",
            args: ["--token", "sk-arg-secret-1234567890"],
            sourcePath: source.path
        )
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true })

        let messages = checker.issues(servers: [remote, remoteCopy, local, localCopy], sources: [source]).map(\.message)

        XCTAssertTrue(messages.contains { $0.contains("https://example.test/mcp?api_key=<redacted>") })
        XCTAssertTrue(messages.contains { $0.contains("mcp-server-example --token <redacted>") })
        XCTAssertFalse(messages.joined(separator: "\n").contains("sk-url-secret"))
        XCTAssertFalse(messages.joined(separator: "\n").contains("sk-arg-secret"))
    }

    func testMissingKeychainSecretReferenceProducesPresenceWarningWithoutValue() throws {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            envBindings: ["GITHUB_TOKEN": reference.configValue],
            sourcePath: source.path
        )
        let store = InMemorySecretStore()
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true }, secretStore: store)

        let issues = checker.issues(servers: [server], sources: [source])

        XCTAssertEqual(issues, [ScanIssue(
            source: source,
            severity: .warning,
            message: "Missing Keychain secret for github env var GITHUB_TOKEN (service com.mcphq.secrets, account github/GITHUB_TOKEN). Safe recovery: Re-enter the secret value and migrate/store it back to Keychain; do not paste plaintext into config. If the credential was intentionally removed, remove the keychain:// reference."
        )])
        XCTAssertFalse(issues.map(\.message).joined(separator: "\n").contains("secret-value"))
    }

    func testPresentKeychainHeaderReferenceProducesNoWarning() throws {
        let source = ConfigSource(agent: .gemini, path: "/tmp/gemini.json")
        let reference = KeychainSecretReference.stable(serverID: "remote", secretName: "header_Authorization")
        let server = ServerDefinition(
            id: "remote",
            displayName: "remote",
            transport: .streamableHTTP,
            url: "https://example.test/mcp",
            headers: ["Authorization": "Bearer \(reference.configValue)"],
            sourcePath: source.path
        )
        let store = InMemorySecretStore(values: [reference: "secret-value-not-reported"])
        let checker = ServerDiagnosticChecker(commandExists: { _, _ in true }, secretStore: store)

        XCTAssertEqual(checker.issues(servers: [server], sources: [source]), [])
    }
}
