import XCTest
@testable import MCPHQCore

final class MCPStdioProbeTests: XCTestCase {
    func testProbeInitializesServerAndCountsTools() throws {
        let scriptURL = try makeExecutableScript("fake-mcp.py", contents: """
        #!/usr/bin/env python3
        import json
        import sys

        for line in sys.stdin:
            request = json.loads(line)
            method = request.get("method")
            if method == "initialize":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "fake", "version": "1.0.0"}
                    }
                }), flush=True)
            elif method == "notifications/initialized":
                continue
            elif method == "tools/list":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "tools": [{"name": "alpha"}, {"name": "beta"}]
                    }
                }), flush=True)
                break
        """)
        let server = ServerDefinition(
            id: "fake",
            displayName: "Fake",
            transport: .stdio,
            command: scriptURL.path,
            sourcePath: "/tmp/claude.json"
        )

        let result = MCPStdioProbe(timeout: 2).probe(server: server)

        XCTAssertEqual(result.serverID, "fake")
        XCTAssertEqual(result.status, .healthy)
        XCTAssertEqual(result.toolCount, 2)
        XCTAssertEqual(result.message, "tools/list succeeded")
    }

    func testProbeReturnsErrorWhenServerTimesOut() throws {
        let scriptURL = try makeExecutableScript("hanging-mcp.py", contents: """
        #!/usr/bin/env python3
        import time
        time.sleep(10)
        """)
        let server = ServerDefinition(
            id: "hanging",
            displayName: "Hanging",
            transport: .stdio,
            command: scriptURL.path,
            sourcePath: "/tmp/claude.json"
        )

        let result = MCPStdioProbe(timeout: 0.2).probe(server: server)

        XCTAssertEqual(result.serverID, "hanging")
        XCTAssertEqual(result.status, .error)
        XCTAssertNil(result.toolCount)
        XCTAssertTrue(result.message.contains("Timed out"), result.message)
    }

    func testProbeSkipsRemoteServers() {
        let server = ServerDefinition(
            id: "remote",
            displayName: "Remote",
            transport: .http,
            url: "https://example.com/mcp",
            sourcePath: "/tmp/claude.json"
        )

        let result = MCPStdioProbe(timeout: 0.2).probe(server: server)

        XCTAssertEqual(result.serverID, "remote")
        XCTAssertEqual(result.status, .skipped)
        XCTAssertNil(result.toolCount)
        XCTAssertTrue(result.message.contains("Only stdio probing is supported"), result.message)
    }

    private func makeExecutableScript(_ name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent(name)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}
