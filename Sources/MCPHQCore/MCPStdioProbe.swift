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
            try writeJSONLine(toolsListRequest(id: 2), to: stdin.fileHandleForWriting)
            let toolsResponse = try waitForResponse(id: 2, process: process, buffer: stdoutBuffer, timeout: timeout)
            if let message = errorMessage(in: toolsResponse) {
                return MCPProbeResult(serverID: server.id, status: .error, message: "tools/list failed: \(sanitize(message))")
            }
            guard let result = toolsResponse["result"] as? [String: Any], let tools = result["tools"] as? [[String: Any]] else {
                return MCPProbeResult(serverID: server.id, status: .warning, message: "tools/list response did not include tools.")
            }
            return MCPProbeResult(serverID: server.id, status: .healthy, toolCount: tools.count, message: "tools/list succeeded")
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
