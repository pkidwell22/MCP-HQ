import Foundation

public struct MCPHTTPProbe {
    private let timeout: TimeInterval
    private let session: URLSession
    private let processEnvironment: [String: String]

    public init(timeout: TimeInterval = 2, session: URLSession = .shared, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.timeout = timeout
        self.session = session
        self.processEnvironment = processEnvironment
    }

    public func probe(servers: [ServerDefinition]) -> [MCPProbeResult] {
        servers.map { probe(server: $0) }
    }

    public func probe(server: ServerDefinition) -> MCPProbeResult {
        guard server.transport == .http || server.transport == .streamableHTTP else {
            return MCPProbeResult(
                serverID: server.id,
                status: .skipped,
                message: "Only HTTP probing is supported by MCPHTTPProbe."
            )
        }
        guard let urlText = server.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlText.isEmpty,
              let url = URL(string: urlText) else {
            return MCPProbeResult(serverID: server.id, status: .error, message: "Missing or invalid HTTP MCP URL.")
        }
        let configuredHeaders = resolvedHeaders(server.headers)

        do {
            let initialize = try sendJSONRPC(
                initializeRequest(id: 1),
                to: url,
                headers: configuredHeaders,
                sessionID: nil,
                expectsResponse: true
            )
            if let message = errorMessage(in: initialize.object) {
                return MCPProbeResult(serverID: server.id, status: .error, message: "initialize failed: \(sanitize(message))")
            }

            _ = try sendJSONRPC(
                initializedNotification(),
                to: url,
                headers: configuredHeaders,
                sessionID: initialize.sessionID,
                expectsResponse: false
            )
            let pingSucceeded = readPing(from: url, headers: configuredHeaders, sessionID: initialize.sessionID)

            let toolsResponse = try sendJSONRPC(
                toolsListRequest(id: 2),
                to: url,
                headers: configuredHeaders,
                sessionID: initialize.sessionID,
                expectsResponse: true
            )
            if let message = errorMessage(in: toolsResponse.object) {
                return MCPProbeResult(serverID: server.id, status: .error, message: "tools/list failed: \(sanitize(message))")
            }
            guard let result = toolsResponse.object["result"] as? [String: Any],
                  let tools = result["tools"] as? [[String: Any]] else {
                return MCPProbeResult(serverID: server.id, status: .warning, message: "tools/list response did not include tools.")
            }

            let toolNames = tools.compactMap { $0["name"] as? String }
            let toolDetails = tools.compactMap(makeToolDetail)
            let resourceProbe = supportsResources(in: initialize.object)
                ? try readResources(from: url, headers: configuredHeaders, sessionID: initialize.sessionID)
                : nil
            let promptProbe = supportsPrompts(in: initialize.object)
                ? try readPrompts(from: url, headers: configuredHeaders, sessionID: initialize.sessionID)
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
        } catch {
            return MCPProbeResult(serverID: server.id, status: .error, message: diagnosticMessage(for: error, url: url))
        }
    }

    private func sendJSONRPC(
        _ object: [String: Any],
        to url: URL,
        headers: [String: String],
        sessionID: String?,
        expectsResponse: Bool,
        requestTimeout: TimeInterval? = nil
    ) throws -> HTTPProbeResponse {
        let body = try JSONSerialization.data(withJSONObject: object)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let effectiveTimeout = requestTimeout ?? timeout
        request.timeoutInterval = effectiveTimeout
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2024-11-05", forHTTPHeaderField: "Mcp-Protocol-Version")
        if let sessionID, !sessionID.isEmpty {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let response = try perform(request, timeout: effectiveTimeout)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPProbeError.httpStatus(response.statusCode, url)
        }

        let nextSessionID = response.sessionID ?? sessionID
        guard expectsResponse else {
            return HTTPProbeResponse(object: [:], sessionID: nextSessionID)
        }
        let parsed = try parseResponse(data: response.data, contentType: response.contentType)
        return HTTPProbeResponse(object: parsed, sessionID: nextSessionID)
    }

    private func perform(_ request: URLRequest, timeout: TimeInterval) throws -> RawHTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let taskResult = LockedHTTPTaskResult()

        let task = session.dataTask(with: request) { data, response, error in
            taskResult.set(data: data, response: response, error: error)
            semaphore.signal()
        }
        task.resume()

        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        if timeoutResult == .timedOut {
            task.cancel()
            throw HTTPProbeError.timedOut
        }

        let snapshot = taskResult.snapshot()
        if let error = snapshot.error { throw error }
        guard let httpResponse = snapshot.response as? HTTPURLResponse else {
            throw HTTPProbeError.invalidHTTPResponse
        }
        return RawHTTPResponse(
            data: snapshot.data ?? Data(),
            statusCode: httpResponse.statusCode,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "",
            sessionID: httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
        )
    }

    private func parseResponse(data: Data, contentType: String) throws -> [String: Any] {
        if contentType.lowercased().contains("text/event-stream") {
            guard let text = String(data: data, encoding: .utf8) else { throw HTTPProbeError.invalidUTF8 }
            guard let eventData = firstSSEDataPayload(in: text) else { throw HTTPProbeError.missingSSEData }
            guard let payload = eventData.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw HTTPProbeError.invalidJSON
            }
            return object
        }

        guard !data.isEmpty else { throw HTTPProbeError.emptyResponse }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPProbeError.invalidJSON
        }
        return object
    }

    private func firstSSEDataPayload(in text: String) -> String? {
        var dataLines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.isEmpty {
                if !dataLines.isEmpty { return dataLines.joined(separator: "\n") }
                continue
            }
            if rawLine.hasPrefix("data:") {
                let payloadStart = rawLine.index(rawLine.startIndex, offsetBy: 5)
                dataLines.append(String(rawLine[payloadStart...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
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

    private func readPing(from url: URL, headers: [String: String], sessionID: String?) -> Bool? {
        do {
            let response = try sendJSONRPC(
                pingRequest(id: 900),
                to: url,
                headers: headers,
                sessionID: sessionID,
                expectsResponse: true,
                requestTimeout: min(timeout, 0.5)
            )
            if errorMessage(in: response.object) != nil { return nil }
            return response.object["result"] != nil
        } catch {
            return nil
        }
    }

    private func readResources(from url: URL, headers: [String: String], sessionID: String?) throws -> ResourceProbePayload? {
        let response = try sendJSONRPC(
            resourcesListRequest(id: 3),
            to: url,
            headers: headers,
            sessionID: sessionID,
            expectsResponse: true
        )
        if errorMessage(in: response.object) != nil { return nil }
        guard let result = response.object["result"] as? [String: Any],
              let resources = result["resources"] as? [[String: Any]] else { return nil }
        return ResourceProbePayload(resources: resources)
    }

    private func readPrompts(from url: URL, headers: [String: String], sessionID: String?) throws -> PromptProbePayload? {
        let response = try sendJSONRPC(
            promptsListRequest(id: 4),
            to: url,
            headers: headers,
            sessionID: sessionID,
            expectsResponse: true
        )
        if errorMessage(in: response.object) != nil { return nil }
        guard let result = response.object["result"] as? [String: Any],
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

    private func diagnosticMessage(for error: Error, url: URL) -> String {
        if case HTTPProbeError.timedOut = error {
            return "Timed out waiting for MCP HTTP response from \(safeURLText(url))."
        }
        if case HTTPProbeError.httpStatus(let status, let endpoint) = error {
            return "HTTP MCP probe got HTTP \(status) from \(safeURLText(endpoint)). Check that the configured MCP HTTP endpoint and transport are correct."
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed:
                return "HTTP MCP probe could not connect to \(safeURLText(url)). Make sure the server is running and the configured URL is reachable."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "HTTP MCP probe could not establish a secure connection to \(safeURLText(url)). Check TLS certificates or use the correct MCP endpoint URL."
            case .timedOut:
                return "Timed out waiting for MCP HTTP response from \(safeURLText(url))."
            default:
                break
            }
        }

        return "HTTP MCP probe failed for \(safeURLText(url)): \(sanitize(error.localizedDescription))"
    }

    private func safeURLText(_ url: URL) -> String {
        sanitize(url.absoluteString)
    }

    private func sanitize(_ value: String) -> String {
        SecretRedactor.redactText(value)
    }

    private func resolvedHeaders(_ bindings: [String: String]) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in bindings {
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerName.isEmpty else { continue }
            headers[headerName] = resolvedEnvValue(value)
        }
        return headers
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

private final class LockedHTTPTaskResult: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var response: URLResponse?
    private var error: Error?

    func set(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        self.data = data
        self.response = response
        self.error = error
        lock.unlock()
    }

    func snapshot() -> (data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (data, response, error)
    }
}

private struct HTTPProbeResponse {
    let object: [String: Any]
    let sessionID: String?
}

private struct RawHTTPResponse {
    let data: Data
    let statusCode: Int
    let contentType: String
    let sessionID: String?
}

private enum HTTPProbeError: LocalizedError {
    case timedOut
    case httpStatus(Int, URL)
    case invalidHTTPResponse
    case emptyResponse
    case invalidUTF8
    case missingSSEData
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Timed out waiting for MCP HTTP response."
        case .httpStatus(let status, _):
            return "HTTP status \(status)."
        case .invalidHTTPResponse:
            return "Invalid HTTP response."
        case .emptyResponse:
            return "Empty HTTP response."
        case .invalidUTF8:
            return "HTTP response was not valid UTF-8."
        case .missingSSEData:
            return "SSE response did not contain a data payload."
        case .invalidJSON:
            return "HTTP response did not contain a JSON-RPC object."
        }
    }
}
