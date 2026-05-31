import XCTest
@testable import MCPHQCore

final class ScanCoordinatorTests: XCTestCase {
    func testScanOmitsProbeResultsWhenIncludeProbesIsFalse() throws {
        let configURL = try makeClaudeConfig(command: "npx")
        let source = ConfigSource(agent: .claude, path: configURL.path)
        let coordinator = ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: { [] }),
            probeProvider: { servers in
                servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 2, message: "tools/list succeeded") }
            }
        )

        let result = coordinator.scan(sources: [source], includeProbes: false)

        XCTAssertEqual(result.servers.map(\.displayName), ["memory"])
        XCTAssertTrue(result.probeResults.isEmpty)
    }

    func testScanIncludesProbeResultsWhenIncludeProbesIsTrue() throws {
        let configURL = try makeClaudeConfig(command: "npx")
        let source = ConfigSource(agent: .claude, path: configURL.path)
        let coordinator = ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: { [] }),
            probeProvider: { servers in
                servers.map { MCPProbeResult(serverID: $0.id, status: .healthy, toolCount: 2, message: "tools/list succeeded") }
            }
        )

        let result = coordinator.scan(sources: [source], includeProbes: true)

        let probe = try XCTUnwrap(result.probeResults.first)
        XCTAssertEqual(probe.serverID, ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "memory"))
        XCTAssertEqual(probe.status, .healthy)
        XCTAssertEqual(probe.toolCount, 2)
    }

    func testScanAddsProcessMatchesAndDiagnostics() throws {
        let configURL = try makeClaudeConfig(command: "definitely-not-installed-mcp")
        let source = ConfigSource(agent: .claude, path: configURL.path)
        let coordinator = ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: {
                [RawProcessSnapshot(pid: 1234, commandLine: "definitely-not-installed-mcp")]
            }),
            probeProvider: { _ in [] }
        )

        let result = coordinator.scan(sources: [source], includeProbes: false)

        XCTAssertEqual(result.processes.first?.pid, 1234)
        XCTAssertEqual(result.processMatches.first?.serverID, ServerDefinition.canonicalID(agent: .claude, sourcePath: configURL.path, name: "memory"))
        XCTAssertTrue(result.issues.contains { issue in
            issue.severity == .warning && issue.message.contains("Command not found for memory")
        })
    }

    func testScanPreservesSourceHealthFromConfigScanner() throws {
        let configURL = try makeClaudeConfig(command: "npx")
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        let coordinator = ScanCoordinator(
            processScanner: MCPProcessScanner(processProvider: { [] }),
            probeProvider: { _ in [] }
        )

        let result = coordinator.scan(sources: [
            ConfigSource(agent: .claude, path: configURL.path),
            ConfigSource(agent: .cursor, path: missingURL.path),
        ])

        XCTAssertEqual(result.sourceHealth.map(\.state), [.parsed, .missing])
    }

    private func makeClaudeConfig(command: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("claude.json")
        try """
        {
          "mcpServers": {
            "memory": {
              "command": "\(command)",
              "args": ["-y", "@modelcontextprotocol/server-memory"]
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }
}
