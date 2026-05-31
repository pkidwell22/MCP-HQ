import Foundation

public struct LocalControlHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public struct LocalControlHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct LocalControlHTTPAdapter: Sendable {
    public static let controlPath = "/api/v1/control"

    private let client: LocalControlInProcessClient
    private let codec: LocalControlJSONCodec
    private let authToken: String?

    public init(
        client: LocalControlInProcessClient = LocalControlInProcessClient(),
        codec: LocalControlJSONCodec = LocalControlJSONCodec(),
        authToken: String? = nil
    ) {
        self.client = client
        self.codec = codec
        self.authToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func handle(_ request: LocalControlHTTPRequest) -> LocalControlHTTPResponse {
        guard request.path == Self.controlPath else {
            return errorResponse(statusCode: 404, message: "Unknown local control path")
        }
        guard request.method.uppercased() == "POST" else {
            return errorResponse(statusCode: 405, message: "Local control endpoint requires POST")
        }
        guard isAuthorized(request) else {
            return errorResponse(statusCode: 401, message: "Unauthorized local control request")
        }

        do {
            let envelope = try codec.decodeRequest(request.body)
            guard let controlRequest = envelope.request else {
                return errorResponse(statusCode: 400, message: "Missing local control request", id: envelope.id)
            }
            let responseEnvelope = try client.sendEnvelope(controlRequest, id: envelope.id)
            return jsonResponse(statusCode: 200, body: try encodeResponseEnvelope(responseEnvelope))
        } catch let error as LocalControlTransportError {
            return errorResponse(statusCode: 400, message: error.description)
        } catch {
            return errorResponse(statusCode: 400, message: String(describing: error))
        }
    }

    private func isAuthorized(_ request: LocalControlHTTPRequest) -> Bool {
        guard let authToken, !authToken.isEmpty else { return true }
        if request.header("X-MCPHQ-Token") == authToken {
            return true
        }
        let authorization = request.header("Authorization") ?? ""
        return authorization == "Bearer \(authToken)"
    }

    private func encodeResponseEnvelope(_ envelope: LocalControlEnvelope) throws -> Data {
        if let response = envelope.response {
            return try codec.encodeResponse(response, id: envelope.id)
        }
        if let error = envelope.error {
            return try codec.encodeError(error, id: envelope.id)
        }
        return try codec.encodeError("Missing local control response", id: envelope.id)
    }

    private func jsonResponse(statusCode: Int, body: Data) -> LocalControlHTTPResponse {
        LocalControlHTTPResponse(
            statusCode: statusCode,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Cache-Control": "no-store",
            ],
            body: body
        )
    }

    private func errorResponse(statusCode: Int, message: String, id: String = "error") -> LocalControlHTTPResponse {
        let body = (try? codec.encodeError(message, id: id)) ?? Data()
        return jsonResponse(statusCode: statusCode, body: body)
    }
}
