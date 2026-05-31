import XCTest
@testable import MCPHQCore

final class MCPProcessScannerTests: XCTestCase {
    func testScannerFindsLikelyMCPProcessesAndRedactsSensitiveArguments() {
        let scanner = MCPProcessScanner(processProvider: {
            [
                RawProcessSnapshot(pid: 101, commandLine: "node /opt/homebrew/bin/mcp-server-github --token github_pat_fakeSecret1234567890"),
                RawProcessSnapshot(pid: 102, commandLine: "/Users/example/.local/bin/qmd mcp"),
                RawProcessSnapshot(pid: 103, commandLine: "uvx blender-mcp --api-key sk-fakeSecret1234567890"),
                RawProcessSnapshot(pid: 104, commandLine: "/Applications/Safari.app/Contents/MacOS/Safari"),
            ]
        })

        let processes = scanner.scan()

        XCTAssertEqual(processes.map(\.pid), [101, 102, 103])
        XCTAssertEqual(processes[0].executableName, "node")
        XCTAssertEqual(processes[0].matchReason, "mcp command pattern")
        XCTAssertTrue(processes[0].commandLine.contains("<redacted>"))
        XCTAssertFalse(processes[0].commandLine.contains("github_pat_fakeSecret1234567890"))
        XCTAssertTrue(processes[2].commandLine.contains("--api-key <redacted>"))
    }

    func testScannerParsesMacOSPSOutput() {
        let output = """
          501 /usr/bin/python3 -m some_mcp_server
         1201 npx -y @modelcontextprotocol/server-filesystem /Users/example
         7777 /usr/libexec/trustd
        """

        let processes = MCPProcessScanner.parsePSOutput(output)

        XCTAssertEqual(processes, [
            RawProcessSnapshot(pid: 501, commandLine: "/usr/bin/python3 -m some_mcp_server"),
            RawProcessSnapshot(pid: 1201, commandLine: "npx -y @modelcontextprotocol/server-filesystem /Users/example"),
            RawProcessSnapshot(pid: 7777, commandLine: "/usr/libexec/trustd"),
        ])
    }

    func testScannerParsesMacOSPSOutputWithCPUAndMemory() {
        let output = """
          501   3.5  2048 /usr/bin/python3 -m some_mcp_server
         1201   0.0 16384 npx -y @modelcontextprotocol/server-filesystem /Users/example
        """

        let processes = MCPProcessScanner.parsePSOutput(output)

        XCTAssertEqual(processes, [
            RawProcessSnapshot(pid: 501, commandLine: "/usr/bin/python3 -m some_mcp_server", cpuPercent: 3.5, memoryBytes: 2_097_152),
            RawProcessSnapshot(pid: 1201, commandLine: "npx -y @modelcontextprotocol/server-filesystem /Users/example", cpuPercent: 0.0, memoryBytes: 16_777_216),
        ])
    }

    func testScannerPropagatesCPUAndMemoryToSnapshots() {
        let scanner = MCPProcessScanner(processProvider: {
            [
                RawProcessSnapshot(
                    pid: 301,
                    commandLine: "npx -y @modelcontextprotocol/server-memory",
                    cpuPercent: 1.25,
                    memoryBytes: 42_000
                ),
            ]
        })

        let process = scanner.scan().first

        XCTAssertEqual(process?.cpuPercent, 1.25)
        XCTAssertEqual(process?.memoryBytes, 42_000)
    }

    func testScannerIgnoresDiagnosticSearchCommands() {
        let scanner = MCPProcessScanner(processProvider: {
            [
                RawProcessSnapshot(pid: 401, commandLine: "/bin/bash -lc ps aux | rg -i 'mcp|modelcontextprotocol|qmd'"),
                RawProcessSnapshot(pid: 402, commandLine: "rg -i mcp Sources/MCPHQCore"),
                RawProcessSnapshot(pid: 403, commandLine: "/bin/bash -lc swift run mcphq scan"),
                RawProcessSnapshot(pid: 404, commandLine: "/Users/example/MCP-HQ/.build/debug/MCPHQPackageTests.xctest/Contents/MacOS/MCPHQPackageTests --filter MCPProcessScannerTests"),
                RawProcessSnapshot(pid: 405, commandLine: "npx -y @modelcontextprotocol/server-memory"),
            ]
        })

        XCTAssertEqual(scanner.scan().map(\.pid), [405])
    }

    func testScannerRedactsEqualsFormSensitiveArgumentsEvenWhenValuesLookNonTokenLike() {
        let scanner = MCPProcessScanner(processProvider: {
            [
                RawProcessSnapshot(
                    pid: 201,
                    commandLine: "npx mcp-server-example --api-key=shortsecret --key=localonly AUTH_TOKEN=lettersOnlySecret"
                ),
            ]
        })

        let process = scanner.scan().first

        XCTAssertEqual(process?.commandLine, "npx mcp-server-example --api-key=<redacted> --key=<redacted> AUTH_TOKEN=<redacted>")
        XCTAssertFalse(process?.commandLine.contains("shortsecret") == true)
        XCTAssertFalse(process?.commandLine.contains("localonly") == true)
        XCTAssertFalse(process?.commandLine.contains("lettersOnlySecret") == true)
    }
}
