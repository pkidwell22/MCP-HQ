import XCTest
@testable import MCPHQCore

final class AgentConfigRendererTests: XCTestCase {
    func testVisualDiffFormatterSeparatesAddedRemovedAndContextLines() {
        let lines = ConfigDiffFormatter.visualDiff(
            old: "one\ntwo\nthree\n",
            new: "one\ntwo updated\nthree\nfour\n"
        )

        XCTAssertTrue(lines.contains { $0.kind == .context && $0.content == "one" })
        XCTAssertTrue(lines.contains { $0.kind == .removed && $0.content == "two" })
        XCTAssertTrue(lines.contains { $0.kind == .added && $0.content == "two updated" })
        XCTAssertTrue(lines.contains { $0.kind == .added && $0.content == "four" })
    }

    func testVisualDiffFormatterReturnsNoLinesForNoChanges() {
        XCTAssertEqual(ConfigDiffFormatter.visualDiff(old: "same\n", new: "same\n"), [])
    }

    func testPreviewDiffOutputsAreRedactedInCompactAndVisualDiffs() throws {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let literalSecret = "ghp_1234567890abcdefABCDEF"

        let existingText = #"{"mcpServers":{"github":{"command":"npx","env":{"GITHUB_TOKEN":"\#(literalSecret)"}}}}"#
        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [server],
            existingData: Data(existingText.utf8)
        )

        let visualText = preview.visualDiffLines.map(\.content).joined(separator: "\n")
        XCTAssertFalse(preview.diffText.contains(literalSecret))
        XCTAssertFalse(visualText.contains(literalSecret))
        XCTAssertTrue(preview.diffText.contains("<redacted>"))
        XCTAssertTrue(visualText.contains("<redacted>"))
        XCTAssertTrue(preview.visualDiffLines.contains { $0.kind == .removed })
        XCTAssertTrue(preview.visualDiffLines.contains { $0.kind == .added })
    }

    func testPreviewRendersSecretSafeCodexConfigAndReparsesIt() throws {
        let source = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let server = ServerDefinition(
            id: "github",
            displayName: "github",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            headers: ["Authorization": "Bearer ghp_1234567890abcdef"],
            envBindings: ["GITHUB_TOKEN": "ghp_1234567890abcdef"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [server],
            existingData: Data("[mcp_servers.old]\ncommand = \"old\"\n".utf8)
        )

        XCTAssertTrue(preview.renderedText.contains("[mcp_servers.github]"))
        XCTAssertTrue(preview.renderedText.contains("GITHUB_TOKEN = \"${GITHUB_TOKEN}\""))
        XCTAssertTrue(preview.renderedText.contains("Authorization = \"Bearer ${AUTHORIZATION}\""))
        XCTAssertFalse(preview.renderedText.contains("ghp_1234567890abcdef"))
        XCTAssertEqual(preview.reparsedServers.count, 1)
        XCTAssertTrue(preview.diffText.contains("--- current"))
        XCTAssertTrue(preview.diffText.contains("+++ generated"))
    }

    func testPreviewPreservesNonMCPCodexTOMLSections() throws {
        let source = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [server],
            existingData: Data("""
            model = "gpt-5.5"

            [mcp_servers.old]
            command = "old"

            [ui]
            theme = "dark"
            """.utf8)
        )

        XCTAssertTrue(preview.renderedText.contains("model = \"gpt-5.5\""))
        XCTAssertTrue(preview.renderedText.contains("[ui]"))
        XCTAssertTrue(preview.renderedText.contains("theme = \"dark\""))
        XCTAssertTrue(preview.renderedText.contains("[mcp_servers.memory]"))
        XCTAssertFalse(preview.renderedText.contains("[mcp_servers.old]"))
        XCTAssertEqual(preview.reparsedServers.map(\.displayName), ["memory"])
    }

    func testPreviewPreservesUnchangedCodexMCPBlocksWhenAddingServer() throws {
        let source = ConfigSource(agent: .codex, path: "/tmp/codex.toml")
        let nodeRepl = ServerDefinition(
            id: "codex-node-repl",
            displayName: "node_repl",
            transport: .stdio,
            command: "/Applications/Codex.app/Contents/Resources/node_repl",
            envBindings: [
                "NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S": "0b0d41e7a14a4903d2f95b0b3f427ed796b12c8edca2fa392a03df43997075ae",
                "SKY_CUA_SERVICE_PATH": "/Users/example/.codex/plugins/cache/computer-use/Codex Computer Use.app"
            ],
            sourcePath: source.path
        )
        let filesystem = ServerDefinition(
            id: "codex-filesystem",
            displayName: "filesystem",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/example"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [nodeRepl, filesystem],
            existingData: Data("""
            model = "gpt-5.5"

            [mcp_servers.node_repl]
            args = []
            command = "/Applications/Codex.app/Contents/Resources/node_repl"
            startup_timeout_sec = 120

            [mcp_servers.node_repl.env]
            NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S = "0b0d41e7a14a4903d2f95b0b3f427ed796b12c8edca2fa392a03df43997075ae"
            SKY_CUA_SERVICE_PATH = "/Users/example/.codex/plugins/cache/computer-use/Codex Computer Use.app"
            """.utf8)
        )

        XCTAssertTrue(preview.renderedText.contains("[mcp_servers.filesystem]"))
        XCTAssertTrue(preview.renderedText.contains("startup_timeout_sec = 120"))
        XCTAssertTrue(preview.renderedText.contains("args = []"))
        XCTAssertTrue(preview.renderedText.contains("NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S = \"0b0d41e7a14a4903d2f95b0b3f427ed796b12c8edca2fa392a03df43997075ae\""))
        XCTAssertFalse(preview.renderedText.contains("NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S = \"${NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S}\""))
        XCTAssertFalse(preview.diffText.contains(#"-[plugins."computer-use@openai-bundled"]"#))
        XCTAssertEqual(Set(preview.reparsedServers.map(\.displayName)), ["filesystem", "node_repl"])
    }

    func testPreviewPreservesNonMCPHermesYAMLTopLevelSettings() throws {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [server],
            existingData: Data("""
            model:
              default: gpt-5.5
            mcp_servers:
              old:
                command: old
            terminal:
              cwd: .
            """.utf8)
        )

        XCTAssertTrue(preview.renderedText.contains("model:"))
        XCTAssertTrue(preview.renderedText.contains("default: gpt-5.5"))
        XCTAssertTrue(preview.renderedText.contains("terminal:"))
        XCTAssertTrue(preview.renderedText.contains("cwd: ."))
        XCTAssertTrue(preview.renderedText.contains("memory:"))
        XCTAssertFalse(preview.renderedText.contains("old:"))
        XCTAssertEqual(preview.reparsedServers.map(\.displayName), ["memory"])
    }

    func testPreviewPreservesUnchangedHermesMCPBlocksWhenAddingServer() throws {
        let source = ConfigSource(agent: .hermes, path: "/tmp/hermes.yaml")
        let memory = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let twozero = ServerDefinition(
            id: "twozero_td",
            displayName: "twozero_td",
            transport: .http,
            url: "http://localhost:40404/mcp",
            sourcePath: source.path
        )
        let filesystem = ServerDefinition(
            id: "filesystem",
            displayName: "filesystem",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [memory, twozero, filesystem],
            existingData: Data("""
            model:
              default: gpt-5.5
            mcp_servers:
              memory:
                command: npx
                args:
                - -y
                - '@modelcontextprotocol/server-memory'
                timeout: 30
                enabled: true
              twozero_td:
                url: http://localhost:40404/mcp
                timeout: 120
                connect_timeout: 60
            terminal:
              cwd: .
            """.utf8)
        )

        XCTAssertTrue(preview.renderedText.contains("filesystem:"))
        XCTAssertTrue(preview.renderedText.contains("timeout: 30"))
        XCTAssertTrue(preview.renderedText.contains("enabled: true"))
        XCTAssertTrue(preview.renderedText.contains("timeout: 120"))
        XCTAssertTrue(preview.renderedText.contains("connect_timeout: 60"))
        XCTAssertEqual(Set(preview.reparsedServers.map(\.displayName)), ["filesystem", "memory", "twozero_td"])
    }

    func testPreviewPreservesNonMCPJSONRootKeys() throws {
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )

        let preview = try AgentConfigSafeApplier().preview(
            source: source,
            servers: [server],
            existingData: Data(#"{"theme":"dark","mcpServers":{"old":{"command":"old"}}}"#.utf8)
        )

        XCTAssertTrue(preview.renderedText.contains(#""theme" : "dark""#))
        XCTAssertTrue(preview.renderedText.contains(#""memory""#))
        XCTAssertFalse(preview.renderedText.contains(#""old""#))
        XCTAssertEqual(preview.reparsedServers.map(\.displayName), ["memory"])
    }

    func testDryRunDoesNotWriteConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = ConfigSource(agent: .cursor, path: directory.appendingPathComponent("mcp.json").path)
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )

        let result = try AgentConfigSafeApplier().apply(source: source, servers: [server], dryRun: true)

        XCTAssertFalse(result.didWrite)
        XCTAssertNil(result.backupPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testApplyCreatesTimestampedBackupAndWrittenConfigParses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("mcp.json")
        try #"{"mcpServers":{"old":{"command":"old"}}}"#.write(to: configURL, atomically: true, encoding: .utf8)
        let source = ConfigSource(agent: .cursor, path: configURL.path)
        let server = ServerDefinition(
            id: "memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = try AgentConfigSafeApplier(now: { date }).apply(source: source, servers: [server])

        XCTAssertTrue(result.didWrite)
        let backupPath = try XCTUnwrap(result.backupPath)
        XCTAssertTrue(backupPath.hasSuffix(".mcphq-backup-20231114221320"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        let written = try Data(contentsOf: configURL)
        let reparsed = try AgentConfigParser().parse(data: written, source: source)
        XCTAssertEqual(reparsed.map(\.displayName), ["memory"])
    }
}
