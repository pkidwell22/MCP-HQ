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
}
