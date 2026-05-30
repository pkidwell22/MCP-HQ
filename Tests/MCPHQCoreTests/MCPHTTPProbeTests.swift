import XCTest
@testable import MCPHQCore

final class MCPHTTPProbeTests: XCTestCase {
    func testProbePostsInitializeAndToolsListToStreamableHTTPServer() throws {
        let server = try LocalMCPHTTPTestServer(scriptName: "streamable-http-mcp.py", body: """
        import json
        import sys
        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                request = json.loads(self.rfile.read(length))
                method = request.get("method")
                if method == "initialize":
                    response = {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {"tools": {}, "resources": {}, "prompts": {}},
                            "serverInfo": {"name": "http-test", "version": "1.0.0"}
                        }
                    }
                    self.send_json(response, session_id="session-123")
                elif method == "notifications/initialized":
                    self.send_response(202)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                elif method == "ping":
                    if self.headers.get("Mcp-Session-Id") != "session-123":
                        self.send_json({
                            "jsonrpc": "2.0",
                            "id": request["id"],
                            "error": {"code": -32000, "message": "missing session"}
                        })
                        return
                    self.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {}})
                elif method == "tools/list":
                    if self.headers.get("Mcp-Session-Id") != "session-123":
                        self.send_json({
                            "jsonrpc": "2.0",
                            "id": request["id"],
                            "error": {"code": -32000, "message": "missing session"}
                        })
                        return
                    response = {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": {
                            "tools": [
                                {
                                    "name": "remote-alpha",
                                    "description": "Remote tool with api_key=sk-test-secret",
                                    "inputSchema": {
                                        "type": "object",
                                        "required": ["query"],
                                        "properties": {"query": {"type": "string"}}
                                    }
                                }
                            ]
                        }
                    }
                    self.send_json(response)
                elif method == "resources/list":
                    if self.headers.get("Mcp-Session-Id") != "session-123":
                        self.send_json({
                            "jsonrpc": "2.0",
                            "id": request["id"],
                            "error": {"code": -32000, "message": "missing session"}
                        })
                        return
                    response = {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": {
                            "resources": [
                                {
                                    "uri": "https://docs.example.test/project",
                                    "name": "Project docs",
                                    "description": "Docs with token=***",
                                    "mimeType": "text/markdown"
                                }
                            ]
                        }
                    }
                    self.send_json(response)
                elif method == "prompts/list":
                    if self.headers.get("Mcp-Session-Id") != "session-123":
                        self.send_json({
                            "jsonrpc": "2.0",
                            "id": request["id"],
                            "error": {"code": -32000, "message": "missing session"}
                        })
                        return
                    response = {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": {
                            "prompts": [
                                {
                                    "name": "draft_release_notes",
                                    "description": "Draft release notes with token=***",
                                    "arguments": [
                                        {"name": "version", "required": True},
                                        {"name": "audience", "required": False}
                                    ]
                                }
                            ]
                        }
                    }
                    self.send_json(response)
                else:
                    self.send_json({
                        "jsonrpc": "2.0",
                        "id": request.get("id"),
                        "error": {"code": -32601, "message": "unknown method"}
                    })

            def log_message(self, format, *args):
                pass

            def send_json(self, response, session_id=None):
                payload = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                if session_id:
                    self.send_header("Mcp-Session-Id", session_id)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        httpd = HTTPServer(("127.0.0.1", 0), Handler)
        print(httpd.server_port, flush=True)
        httpd.serve_forever()
        """)
        defer { server.stop() }
        let definition = ServerDefinition(
            id: "remote",
            displayName: "Remote",
            transport: .streamableHTTP,
            url: server.url.absoluteString,
            sourcePath: "/tmp/hermes.yaml"
        )

        let result = MCPHTTPProbe(timeout: 2).probe(server: definition)

        XCTAssertEqual(result.serverID, "remote")
        XCTAssertEqual(result.status, .healthy)
        XCTAssertEqual(result.toolCount, 1)
        XCTAssertEqual(result.toolNames, ["remote-alpha"])
        XCTAssertEqual(result.resourceCount, 1)
        XCTAssertEqual(result.resourceNames, ["Project docs"])
        XCTAssertEqual(result.pingSucceeded, true)
        XCTAssertEqual(result.promptCount, 1)
        XCTAssertEqual(result.promptNames, ["draft_release_notes"])
        let detail = try XCTUnwrap(result.toolDetails.first)
        XCTAssertEqual(detail.name, "remote-alpha")
        XCTAssertEqual(detail.description, "Remote tool with api_key=<redacted>")
        XCTAssertEqual(detail.inputSchemaSummary, "object • required: query • properties: query")
        let resource = try XCTUnwrap(result.resourceDetails.first)
        XCTAssertEqual(resource.uri, "https://docs.example.test/project")
        XCTAssertEqual(resource.name, "Project docs")
        XCTAssertEqual(resource.description, "Docs with token=<redacted>")
        XCTAssertEqual(resource.mimeType, "text/markdown")
        let prompt = try XCTUnwrap(result.promptDetails.first)
        XCTAssertEqual(prompt.name, "draft_release_notes")
        XCTAssertEqual(prompt.description, "Draft release notes with token=<redacted>")
        XCTAssertEqual(prompt.argumentSummary, "required: version • optional: audience")
        XCTAssertFalse(String(describing: result).contains("***"))
        XCTAssertEqual(result.message, "capability discovery succeeded")
    }

    func testProbeParsesSSEFramedJSONRPCResponses() throws {
        let server = try LocalMCPHTTPTestServer(scriptName: "sse-framed-mcp.py", body: """
        import json
        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                request = json.loads(self.rfile.read(length))
                method = request.get("method")
                if method == "initialize":
                    self.send_sse({"jsonrpc": "2.0", "id": request["id"], "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}}})
                elif method == "notifications/initialized":
                    self.send_response(202)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                elif method == "tools/list":
                    self.send_sse({"jsonrpc": "2.0", "id": request["id"], "result": {"tools": [{"name": "sse-tool"}]}})

            def log_message(self, format, *args):
                pass

            def send_sse(self, response):
                payload = ("event: message\\ndata: " + json.dumps(response) + "\\n\\n").encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        httpd = HTTPServer(("127.0.0.1", 0), Handler)
        print(httpd.server_port, flush=True)
        httpd.serve_forever()
        """)
        defer { server.stop() }
        let definition = ServerDefinition(
            id: "sse-remote",
            displayName: "SSE Remote",
            transport: .http,
            url: server.url.absoluteString,
            sourcePath: "/tmp/hermes.yaml"
        )

        let result = MCPHTTPProbe(timeout: 2).probe(server: definition)

        XCTAssertEqual(result.status, .healthy)
        XCTAssertEqual(result.toolCount, 1)
        XCTAssertEqual(result.toolNames, ["sse-tool"])
    }

    func testProbeExplainsHTTPStatusFailuresWithRedactedURL() throws {
        let server = try LocalMCPHTTPTestServer(scriptName: "http-error-mcp.py", body: """
        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                payload = b"server exploded"
                self.send_response(500)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):
                pass

        httpd = HTTPServer(("127.0.0.1", 0), Handler)
        print(httpd.server_port, flush=True)
        httpd.serve_forever()
        """)
        defer { server.stop() }
        let definition = ServerDefinition(
            id: "http-error",
            displayName: "HTTP Error",
            transport: .streamableHTTP,
            url: server.url.absoluteString + "?api_key=sk-test-secret-1234567890",
            sourcePath: "/tmp/hermes.yaml"
        )

        let result = MCPHTTPProbe(timeout: 2).probe(server: definition)

        XCTAssertEqual(result.status, .error)
        XCTAssertTrue(result.message.contains("HTTP MCP probe got HTTP 500"), result.message)
        XCTAssertTrue(result.message.contains("127.0.0.1"), result.message)
        XCTAssertFalse(result.message.contains("sk-test-secret"), result.message)
        XCTAssertTrue(result.message.contains("api_key=<redacted>"), result.message)
    }

    func testProbeExplainsConnectionFailuresWithTransportAndEndpoint() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectionFailingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let definition = ServerDefinition(
            id: "offline-http",
            displayName: "Offline HTTP",
            transport: .http,
            url: "http://127.0.0.1:45454/mcp?token=sk-test-secret-1234567890",
            sourcePath: "/tmp/hermes.yaml"
        )

        let result = MCPHTTPProbe(timeout: 0.2, session: session).probe(server: definition)

        XCTAssertEqual(result.status, .error)
        XCTAssertTrue(result.message.contains("HTTP MCP probe could not connect"), result.message)
        XCTAssertTrue(result.message.contains("127.0.0.1:45454"), result.message)
        XCTAssertTrue(result.message.contains("configured URL is reachable"), result.message)
        XCTAssertFalse(result.message.contains("sk-test-secret"), result.message)
    }

    func testProbeSkipsStdioServers() {
        let definition = ServerDefinition(
            id: "stdio",
            displayName: "Stdio",
            transport: .stdio,
            command: "mcp-server",
            sourcePath: "/tmp/claude.json"
        )

        let result = MCPHTTPProbe(timeout: 0.2).probe(server: definition)

        XCTAssertEqual(result.serverID, "stdio")
        XCTAssertEqual(result.status, .skipped)
        XCTAssertNil(result.toolCount)
        XCTAssertTrue(result.message.contains("Only HTTP probing is supported"), result.message)
    }
}

private final class ConnectionFailingURLProtocol: URLProtocol, @unchecked Sendable {
    static let error: Error = URLError(.cannotConnectToHost)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: Self.error)
    }

    override func stopLoading() {}
}

private final class LocalMCPHTTPTestServer {
    let url: URL
    private let process: Process
    private let stdout: Pipe

    init(scriptName: String, body: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent(scriptName)
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path]
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()

        let portLine = try Self.readLine(from: stdout.fileHandleForReading, timeout: 2)
        let port = try XCTUnwrap(Int(portLine.trimmingCharacters(in: .whitespacesAndNewlines)))
        self.url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp"))
        self.process = process
        self.stdout = stdout
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
    }

    private static func readLine(from handle: FileHandle, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        while Date() < deadline {
            let chunk = handle.availableData
            if !chunk.isEmpty {
                data.append(chunk)
                if let newline = data.firstIndex(of: 10) {
                    let lineData = data[..<newline]
                    return String(data: lineData, encoding: .utf8) ?? ""
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail("Timed out waiting for local HTTP test server port")
        return ""
    }
}
