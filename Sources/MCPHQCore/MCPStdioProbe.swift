import Foundation
#if os(macOS)
import Darwin
#endif

public struct MCPStdioProbe: Sendable {
    private let timeout: TimeInterval
    private let processEnvironment: [String: String]

    public init(timeout: TimeInterval = 2, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.timeout = timeout
        self.processEnvironment = processEnvironment
    }

    public func probe(servers: [ServerDefinition]) -> [MCPProbeResult] {
        servers.map { probe(server: $0) }
    }

    public func probe(server: ServerDefinition) -> MCPProbeResult {
        guard server.transport == .stdio else {
            return MCPProbeResult(
                serverID: server.id,
                status: .skipped,
                message: "Only stdio probing is supported in this slice."
            )
        }

        guard let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            return MCPProbeResult(
                serverID: server.id,
                status: .error,
                message: "Missing stdio command."
            )
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutBuffer.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }

        configure(process: process, command: command, args: server.args, envBindings: server.envBindings)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning {
                terminate(process)
            }
        }

        do {
            try process.run()
            try writeJSONLine(initializeRequest(id: 1), to: stdin.fileHandleForWriting)
            let initializeResponse = try waitForResponse(id: 1, process: process, buffer: stdoutBuffer, timeout: timeout)
            if let message = errorMessage(in: initializeResponse) {
                return MCPProbeResult(serverID: server.id, status: .error, message: "initialize failed: \(sanitize(message))")
            }

            try writeJSONLine(initializedNotification(), to: stdin.fileHandleForWriting)
            let pingSucceeded = readPing(process: process, stdin: stdin.fileHandleForWriting, stdoutBuffer: stdoutBuffer)
            try writeJSONLine(toolsListRequest(id: 2), to: stdin.fileHandleForWriting)
            let toolsResponse = try waitForResponse(id: 2, process: process, buffer: stdoutBuffer, timeout: timeout)
            if let message = errorMessage(in: toolsResponse) {
                return MCPProbeResult(serverID: server.id, status: .error, message: "tools/list failed: \(sanitize(message))")
            }
            guard let result = toolsResponse["result"] as? [String: Any], let tools = result["tools"] as? [[String: Any]] else {
                return MCPProbeResult(serverID: server.id, status: .warning, message: "tools/list response did not include tools.")
            }
            let toolNames = tools.compactMap { $0["name"] as? String }
            let toolDetails = tools.compactMap(makeToolDetail)
            let resourceProbe = supportsResources(in: initializeResponse)
                ? try readResources(process: process, stdin: stdin.fileHandleForWriting, stdoutBuffer: stdoutBuffer)
                : nil
            let promptProbe = supportsPrompts(in: initializeResponse)
                ? try readPrompts(process: process, stdin: stdin.fileHandleForWriting, stdoutBuffer: stdoutBuffer)
                : nil
            return MCPProbeResult(
                serverID: server.id,
                status: .healthy,
                toolCount: tools.count,
                toolNames: toolNames,
                toolDetails: toolDetails,
                resourceCount: resourceProbe?.resources.count,
                resourceNames: resourceProbe?.resourceNames ?? [],
                resourceDetails: resourceProbe?.resourceDetails ?? [],
                pingSucceeded: pingSucceeded,
                promptCount: promptProbe?.prompts.count,
                promptNames: promptProbe?.promptNames ?? [],
                promptDetails: promptProbe?.promptDetails ?? [],
                message: resourceProbe == nil && promptProbe == nil ? "tools/list succeeded" : "capability discovery succeeded"
            )
        } catch ProbeError.timedOut {
            terminate(process)
            return MCPProbeResult(serverID: server.id, status: .error, message: "Timed out waiting for MCP response.")
        } catch ProbeError.processExited {
            return MCPProbeResult(serverID: server.id, status: .error, message: "MCP server exited before probe completed.")
        } catch {
            return MCPProbeResult(serverID: server.id, status: .error, message: "Probe failed: \(sanitize(error.localizedDescription))")
        }
    }

    private func configure(process: Process, command: String, args: [String], envBindings: [String: String]) {
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: expandedHomePath(command))
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        process.environment = environment(overrides: envBindings)
    }

    private func environment(overrides: [String: String]) -> [String: String] {
        let inheritedKeys = ["PATH", "HOME", "USER", "LANG", "LC_ALL", "TERM", "SHELL", "TMPDIR"]
        var env: [String: String] = [:]
        for key in inheritedKeys {
            if let value = processEnvironment[key] { env[key] = value }
        }
        for (key, value) in processEnvironment where key.hasPrefix("XDG_") {
            env[key] = value
        }
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        for (key, value) in overrides {
            env[key] = resolvedEnvValue(value)
        }
        return env
    }

    private func resolvedEnvValue(_ value: String) -> String {
        if value.hasPrefix("${"), value.hasSuffix("}"), value.count > 3 {
            return processEnvironment[String(value.dropFirst(2).dropLast())] ?? ""
        }
        if value.hasPrefix("$"), value.count > 1 {
            return processEnvironment[String(value.dropFirst())] ?? ""
        }
        return value
    }

    private func writeJSONLine(_ object: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        handle.write(data)
        handle.write(Data([10]))
    }

    private func waitForResponse(id: Int, process: Process, buffer: LockedDataBuffer, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while let line = buffer.popLine() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let responseID = object["id"] as? Int, responseID == id {
                    return object
                }
            }
            if !process.isRunning { throw ProbeError.processExited }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw ProbeError.timedOut
    }

    private func initializeRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "MCP-HQ",
                    "version": "0.1.0"
                ]
            ]
        ]
    }

    private func initializedNotification() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:]
        ]
    }

    private func toolsListRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/list",
            "params": [:]
        ]
    }

    private func pingRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "ping",
            "params": [:]
        ]
    }

    private func resourcesListRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "resources/list",
            "params": [:]
        ]
    }

    private func promptsListRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "prompts/list",
            "params": [:]
        ]
    }

    private func readPing(process: Process, stdin: FileHandle, stdoutBuffer: LockedDataBuffer) -> Bool? {
        do {
            try writeJSONLine(pingRequest(id: 900), to: stdin)
            let response = try waitForResponse(id: 900, process: process, buffer: stdoutBuffer, timeout: min(timeout, 0.5))
            if errorMessage(in: response) != nil { return nil }
            return response["result"] != nil
        } catch {
            return nil
        }
    }

    private func readResources(process: Process, stdin: FileHandle, stdoutBuffer: LockedDataBuffer) throws -> ResourceProbePayload? {
        try writeJSONLine(resourcesListRequest(id: 3), to: stdin)
        let response = try waitForResponse(id: 3, process: process, buffer: stdoutBuffer, timeout: timeout)
        if errorMessage(in: response) != nil { return nil }
        guard let result = response["result"] as? [String: Any],
              let resources = result["resources"] as? [[String: Any]] else { return nil }
        return ResourceProbePayload(resources: resources)
    }

    private func readPrompts(process: Process, stdin: FileHandle, stdoutBuffer: LockedDataBuffer) throws -> PromptProbePayload? {
        try writeJSONLine(promptsListRequest(id: 4), to: stdin)
        let response = try waitForResponse(id: 4, process: process, buffer: stdoutBuffer, timeout: timeout)
        if errorMessage(in: response) != nil { return nil }
        guard let result = response["result"] as? [String: Any],
              let prompts = result["prompts"] as? [[String: Any]] else { return nil }
        return PromptProbePayload(prompts: prompts)
    }

    private func supportsResources(in initializeResponse: [String: Any]) -> Bool {
        supportsCapability("resources", in: initializeResponse)
    }

    private func supportsPrompts(in initializeResponse: [String: Any]) -> Bool {
        supportsCapability("prompts", in: initializeResponse)
    }

    private func supportsCapability(_ key: String, in initializeResponse: [String: Any]) -> Bool {
        guard let result = initializeResponse["result"] as? [String: Any],
              let capabilities = result["capabilities"] as? [String: Any] else { return false }
        return capabilities[key] != nil
    }

    private func makeToolDetail(from tool: [String: Any]) -> MCPToolDetail? {
        guard let name = tool["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return MCPToolDetail(
            name: name,
            description: tool["description"] as? String ?? "",
            inputSchemaSummary: schemaSummary(from: tool["inputSchema"])
        )
    }

    private func schemaSummary(from value: Any?) -> String {
        guard let schema = value as? [String: Any] else { return "" }
        var parts: [String] = []
        if let type = schema["type"] as? String, !type.isEmpty {
            parts.append(type)
        } else {
            parts.append("schema")
        }
        if let required = schema["required"] as? [String], !required.isEmpty {
            parts.append("required: \(required.joined(separator: ", "))")
        }
        if let properties = schema["properties"] as? [String: Any], !properties.isEmpty {
            parts.append("properties: \(properties.keys.sorted().joined(separator: ", "))")
        }
        return parts.joined(separator: " • ")
    }

    private func errorMessage(in response: [String: Any]) -> String? {
        guard let error = response["error"] as? [String: Any] else { return nil }
        return error["message"] as? String ?? "MCP server returned an error."
    }

    private func sanitize(_ value: String) -> String {
        SecretRedactor.redactText(value)
    }

    private func expandedHomePath(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" { return home }
        return home + String(path.dropFirst())
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        #if os(macOS)
        usleep(50_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        #endif
    }
}

private struct ResourceProbePayload {
    let resources: [[String: Any]]
    let resourceNames: [String]
    let resourceDetails: [MCPResourceDetail]

    init(resources: [[String: Any]]) {
        self.resources = resources
        self.resourceDetails = resources.compactMap { resource in
            guard let uri = resource["uri"] as? String, !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return MCPResourceDetail(
                uri: uri,
                name: resource["name"] as? String ?? "",
                description: resource["description"] as? String ?? "",
                mimeType: resource["mimeType"] as? String ?? ""
            )
        }
        self.resourceNames = resources.compactMap { resource in
            if let name = resource["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
            return resource["uri"] as? String
        }
    }
}

private struct PromptProbePayload {
    let prompts: [[String: Any]]
    let promptNames: [String]
    let promptDetails: [MCPPromptDetail]

    init(prompts: [[String: Any]]) {
        self.prompts = prompts
        self.promptNames = prompts.compactMap { $0["name"] as? String }
        self.promptDetails = prompts.compactMap { prompt in
            guard let name = prompt["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return MCPPromptDetail(
                name: name,
                description: prompt["description"] as? String ?? "",
                argumentSummary: Self.argumentSummary(from: prompt["arguments"])
            )
        }
    }

    private static func argumentSummary(from value: Any?) -> String {
        guard let arguments = value as? [[String: Any]], !arguments.isEmpty else { return "" }
        let required = arguments.compactMap { argument -> String? in
            guard argument["required"] as? Bool == true else { return nil }
            return argument["name"] as? String
        }
        let optional = arguments.compactMap { argument -> String? in
            guard argument["required"] as? Bool != true else { return nil }
            return argument["name"] as? String
        }
        var parts: [String] = []
        if !required.isEmpty { parts.append("required: \(required.joined(separator: ", "))") }
        if !optional.isEmpty { parts.append("optional: \(optional.joined(separator: ", "))") }
        return parts.joined(separator: " • ")
    }
}

private enum ProbeError: Error {
    case timedOut
    case processExited
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func popLine() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let newline = data.firstIndex(of: 10) else { return nil }
        let lineData = data[..<newline]
        data.removeSubrange(...newline)
        return String(data: lineData, encoding: .utf8)
    }
}
