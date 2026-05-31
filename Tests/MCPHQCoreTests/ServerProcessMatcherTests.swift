import XCTest
@testable import MCPHQCore

final class ServerProcessMatcherTests: XCTestCase {
    func testMatchesConfiguredStdioServerToRunningProcessByCommandAndPackageArgument() {
        let server = ServerDefinition(
            id: "github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: "/tmp/claude.json"
        )
        let process = MCPProcessSnapshot(
            pid: 4201,
            executableName: "npx",
            commandLine: "npx -y @modelcontextprotocol/server-github --token <redacted>",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [server], processes: [process])

        XCTAssertEqual(matches, [
            ServerProcessMatch(
                serverID: "github",
                processID: 4201,
                confidence: .high,
                reason: "command and MCP-specific argument matched"
            )
        ])
    }

    func testDoesNotMatchGenericRunnersByCommandOnly() {
        let genericNodeServer = ServerDefinition(
            id: "one",
            displayName: "One",
            transport: .stdio,
            command: "node",
            args: [],
            sourcePath: "/tmp/claude.json"
        )
        let unrelatedNodeProcess = MCPProcessSnapshot(
            pid: 901,
            executableName: "node",
            commandLine: "node /tmp/some-other-mcp-wrapper.js",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [genericNodeServer], processes: [unrelatedNodeProcess])

        XCTAssertEqual(matches, [])
    }

    func testMatchesAbsoluteCommandPathByExecutableBasename() {
        let server = ServerDefinition(
            id: "qmd",
            displayName: "QMD",
            transport: .stdio,
            command: "/Users/patkidwell/.bun/bin/bun",
            args: ["qmd", "mcp"],
            sourcePath: "/tmp/hermes.yaml"
        )
        let process = MCPProcessSnapshot(
            pid: 770,
            executableName: "bun",
            commandLine: "/Users/patkidwell/.bun/bin/bun qmd mcp --collection agent-memory/mcp-hq",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [server], processes: [process])

        XCTAssertEqual(matches.map(\.serverID), ["qmd"])
        XCTAssertEqual(matches.map(\.processID), [770])
        XCTAssertEqual(matches.map(\.confidence), [.high])
    }

    func testMatchesRemoteServerByURLWhenURLAppearsInProcessCommandLine() {
        let server = ServerDefinition(
            id: "remote-docs",
            displayName: "Remote Docs",
            transport: .sse,
            url: "http://127.0.0.1:8181/mcp",
            sourcePath: "/tmp/gemini.json"
        )
        let process = MCPProcessSnapshot(
            pid: 991,
            executableName: "node",
            commandLine: "node server.js --endpoint http://127.0.0.1:8181/mcp",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [server], processes: [process])

        XCTAssertEqual(matches, [
            ServerProcessMatch(
                serverID: "remote-docs",
                processID: 991,
                confidence: .high,
                reason: "URL matched"
            )
        ])
    }

    func testTreatsNpxConfiguredServersAsNpmExecProcessesWhenPackageArgumentMatches() {
        let server = ServerDefinition(
            id: "github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            sourcePath: "/tmp/hermes.yaml"
        )
        let process = MCPProcessSnapshot(
            pid: 27677,
            executableName: "npm",
            commandLine: "npm exec @modelcontextprotocol/server-github",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [server], processes: [process])

        XCTAssertEqual(matches.map(\.processID), [27677])
        XCTAssertEqual(matches.map(\.confidence), [.high])
    }

    func testMatchesWrappedQMDProcessByServerIdentityAndMCPArgument() {
        let server = ServerDefinition(
            id: "qmd",
            displayName: "qmd",
            transport: .stdio,
            command: "/Users/patkidwell/.local/bin/qmd",
            args: ["mcp"],
            sourcePath: "/tmp/hermes.yaml"
        )
        let process = MCPProcessSnapshot(
            pid: 27678,
            executableName: "bun",
            commandLine: "bun /Users/patkidwell/qmd/dist/cli/qmd.js mcp",
            matchReason: "mcp command pattern"
        )

        let matches = ServerProcessMatcher().matches(servers: [server], processes: [process])

        XCTAssertEqual(matches.map(\.processID), [27678])
        XCTAssertEqual(matches.map(\.confidence), [.high])
    }

    func testConfiguredProcessMatchesAreAgentOwnedByDefault() {
        let server = ServerDefinition(
            id: "memory",
            displayName: "Memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: "/tmp/claude.json"
        )
        let process = MCPProcessSnapshot(
            pid: 8801,
            executableName: "npx",
            commandLine: "npx -y @modelcontextprotocol/server-memory",
            matchReason: "mcp command pattern"
        )

        let match = ServerProcessMatcher().matches(servers: [server], processes: [process]).first

        XCTAssertEqual(match?.ownership, .agentOwned)
    }
}
