import XCTest
@testable import MCPHQCore

final class MCPStdioProbeTests: XCTestCase {
    func testProbeInitializesServerAndCountsTools() throws {
        let suspiciousToolName = "danger-" + "ghp_" + "1234567890abcdef"
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
                        "capabilities": {"tools": {}, "resources": {}, "prompts": {}},
                        "serverInfo": {"name": "fake", "version": "1.0.0"}
                    }
                }), flush=True)
            elif method == "notifications/initialized":
                continue
            elif method == "ping":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {}
                }), flush=True)
            elif method == "tools/list":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "tools": [
                            {
                                "name": "alpha",
                                "description": "Read project files safely",
                                "inputSchema": {
                                    "type": "object",
                                    "required": ["path"],
                                    "properties": {
                                        "path": {"type": "string"},
                                        "limit": {"type": "integer"}
                                    }
                                }
                            },
                            {"name": "beta", "description": "Beta tool uses token=\(suspiciousToolName)"},
                            {"name": "\(suspiciousToolName)"}
                        ]
                    }
                }), flush=True)
            elif method == "resources/list":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "resources": [
                            {
                                "uri": "file:///safe/project.md",
                                "name": "Project notes",
                                "description": "Shared planning notes",
                                "mimeType": "text/markdown"
                            },
                            {
                                "uri": "secret://token/\(suspiciousToolName)",
                                "description": "Resource leaks api_key=\(suspiciousToolName)"
                            }
                        ]
                    }
                }), flush=True)
            elif method == "prompts/list":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "prompts": [
                            {
                                "name": "summarize_project",
                                "description": "Summarize project context",
                                "arguments": [
                                    {"name": "topic", "description": "Topic to summarize", "required": True},
                                    {"name": "limit", "required": False}
                                ]
                            },
                            {
                                "name": "\(suspiciousToolName)",
                                "description": "Prompt leaks token=\(suspiciousToolName)",
                                "arguments": [{"name": "secret", "description": "api_key=\(suspiciousToolName)", "required": True}]
                            }
                        ]
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
        XCTAssertEqual(result.toolCount, 3)
        XCTAssertEqual(result.toolNames, ["alpha", "beta", "danger-<redacted>"])
        XCTAssertEqual(result.resourceCount, 2)
        XCTAssertEqual(result.resourceNames, ["Project notes", "secret:<redacted>"])
        XCTAssertEqual(result.pingSucceeded, true)
        XCTAssertEqual(result.promptCount, 2)
        XCTAssertEqual(result.promptNames, ["summarize_project", "danger-<redacted>"])
        XCTAssertEqual(result.toolDetails.map(\.name), ["alpha", "beta", "danger-<redacted>"])
        let alpha = try XCTUnwrap(result.toolDetails.first)
        XCTAssertEqual(alpha.description, "Read project files safely")
        XCTAssertEqual(alpha.inputSchemaSummary, "object • required: path • properties: limit, path")
        let beta = try XCTUnwrap(result.toolDetails.dropFirst().first)
        XCTAssertEqual(beta.description, "Beta tool uses token=<redacted>")
        let firstResource = try XCTUnwrap(result.resourceDetails.first)
        XCTAssertEqual(firstResource.uri, "file:///safe/project.md")
        XCTAssertEqual(firstResource.name, "Project notes")
        XCTAssertEqual(firstResource.description, "Shared planning notes")
        XCTAssertEqual(firstResource.mimeType, "text/markdown")
        let secondResource = try XCTUnwrap(result.resourceDetails.dropFirst().first)
        XCTAssertEqual(secondResource.uri, "secret:<redacted>")
        XCTAssertEqual(secondResource.description, "Resource leaks api_key=<redacted>")
        let firstPrompt = try XCTUnwrap(result.promptDetails.first)
        XCTAssertEqual(firstPrompt.name, "summarize_project")
        XCTAssertEqual(firstPrompt.description, "Summarize project context")
        XCTAssertEqual(firstPrompt.argumentSummary, "required: topic • optional: limit")
        let secondPrompt = try XCTUnwrap(result.promptDetails.dropFirst().first)
        XCTAssertEqual(secondPrompt.name, "danger-<redacted>")
        XCTAssertEqual(secondPrompt.description, "Prompt leaks token=<redacted>")
        XCTAssertEqual(secondPrompt.argumentSummary, "required: secret")
        XCTAssertFalse(String(describing: result).contains(suspiciousToolName))
        XCTAssertEqual(result.message, "capability discovery succeeded")
    }

    func testProbeReturnsExplicitTimeoutMessageForInitialize() throws {
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
        XCTAssertTrue(result.message.contains("Timed out while waiting for MCP stdio initialize response."), result.message)
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
