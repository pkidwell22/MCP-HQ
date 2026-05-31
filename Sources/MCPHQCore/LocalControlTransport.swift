import Foundation

public enum LocalControlTransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidRequestEnvelope(String)
    case invalidResponseEnvelope(String)
    case invalidHTTPResponse(String)
    case httpStatus(Int, String)
    case remoteError(String)

    public var description: String {
        switch self {
        case .invalidRequestEnvelope(let reason):
            return "Invalid local control request envelope: \(reason)"
        case .invalidResponseEnvelope(let reason):
            return "Invalid local control response envelope: \(reason)"
        case .invalidHTTPResponse(let reason):
            return "Invalid local control HTTP response: \(reason)"
        case .httpStatus(let status, let message):
            return "Local control HTTP \(status): \(SecretRedactor.redactText(message))"
        case .remoteError(let message):
            return SecretRedactor.redactText(message)
        }
    }
}

public struct LocalControlEnvelope: Codable, Equatable, Sendable {
    public let id: String
    public let request: LocalControlRequest?
    public let response: LocalControlResponse?
    public let error: String?

    public init(
        id: String,
        request: LocalControlRequest? = nil,
        response: LocalControlResponse? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.request = request
        self.response = response
        self.error = error.map(SecretRedactor.redactText)
    }
}

public struct LocalControlJSONCodec: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func encodeRequest(_ request: LocalControlRequest, id: String = UUID().uuidString) throws -> Data {
        try encoder.encode(LocalControlEnvelope(id: id, request: request))
    }

    public func decodeRequest(_ data: Data) throws -> LocalControlEnvelope {
        let envelope = try decoder.decode(LocalControlEnvelope.self, from: data)
        guard envelope.request != nil else {
            throw LocalControlTransportError.invalidRequestEnvelope("missing request")
        }
        guard envelope.response == nil else {
            throw LocalControlTransportError.invalidRequestEnvelope("contains response")
        }
        return envelope
    }

    public func encodeResponse(_ response: LocalControlResponse, id: String) throws -> Data {
        try encoder.encode(LocalControlEnvelope(id: id, response: response))
    }

    public func encodeError(_ error: String, id: String) throws -> Data {
        try encoder.encode(LocalControlEnvelope(id: id, error: error))
    }

    public func decodeResponse(_ data: Data) throws -> LocalControlEnvelope {
        let envelope = try decoder.decode(LocalControlEnvelope.self, from: data)
        guard envelope.request == nil else {
            throw LocalControlTransportError.invalidResponseEnvelope("contains request")
        }
        if let error = envelope.error {
            throw LocalControlTransportError.remoteError(error)
        }
        guard envelope.response != nil else {
            throw LocalControlTransportError.invalidResponseEnvelope("missing response")
        }
        return envelope
    }
}

public struct LocalControlInProcessClient: Sendable {
    private let router: LocalControlRouter
    private let codec: LocalControlJSONCodec

    public init(router: LocalControlRouter = LocalControlRouter(), codec: LocalControlJSONCodec = LocalControlJSONCodec()) {
        self.router = router
        self.codec = codec
    }

    public func send(_ request: LocalControlRequest, id: String = UUID().uuidString) throws -> LocalControlResponse {
        let envelope = try sendEnvelope(request, id: id)
        guard let response = envelope.response else {
            throw LocalControlTransportError.invalidResponseEnvelope("missing response")
        }
        return response
    }

    public func sendEnvelope(_ request: LocalControlRequest, id: String = UUID().uuidString) throws -> LocalControlEnvelope {
        let encodedRequest = try codec.encodeRequest(request, id: id)
        let decodedRequest = try codec.decodeRequest(encodedRequest)
        guard let request = decodedRequest.request else {
            throw LocalControlTransportError.invalidRequestEnvelope("missing request")
        }
        let response = router.handle(request)
        let encodedResponse = try codec.encodeResponse(response, id: decodedRequest.id)
        return try codec.decodeResponse(encodedResponse)
    }
}

public struct LocalControlHTTPClient: Sendable {
    private let endpointStore: LocalControlEndpointStore
    private let codec: LocalControlJSONCodec
    private let timeout: TimeInterval

    public init(
        endpointStore: LocalControlEndpointStore = .defaultStore(),
        codec: LocalControlJSONCodec = LocalControlJSONCodec(),
        timeout: TimeInterval = 5
    ) {
        self.endpointStore = endpointStore
        self.codec = codec
        self.timeout = timeout
    }

    public func send(_ request: LocalControlRequest, id: String = UUID().uuidString) throws -> LocalControlResponse {
        let envelope = try sendEnvelope(request, id: id)
        guard let response = envelope.response else {
            throw LocalControlTransportError.invalidResponseEnvelope("missing response")
        }
        return response
    }

    public func sendEnvelope(_ request: LocalControlRequest, id: String = UUID().uuidString) throws -> LocalControlEnvelope {
        let endpoint = try endpointStore.load()
        var urlRequest = URLRequest(url: endpoint.controlURL, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = endpoint.token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try codec.encodeRequest(request, id: id)

        let result = try perform(urlRequest)
        guard let httpResponse = result.response as? HTTPURLResponse else {
            throw LocalControlTransportError.invalidHTTPResponse("missing HTTPURLResponse")
        }
        if (200..<300).contains(httpResponse.statusCode) {
            return try codec.decodeResponse(result.data)
        }
        do {
            _ = try codec.decodeResponse(result.data)
            throw LocalControlTransportError.httpStatus(httpResponse.statusCode, "unexpected non-error response")
        } catch let error as LocalControlTransportError {
            if case .remoteError(let message) = error {
                throw LocalControlTransportError.httpStatus(httpResponse.statusCode, message)
            }
            throw error
        }
    }

    private func perform(_ request: URLRequest) throws -> (data: Data, response: URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        final class ResultBox: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = ResultBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            semaphore.signal()
        }.resume()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw LocalControlTransportError.invalidHTTPResponse("timed out")
        }
        if let error = box.error { throw error }
        guard let data = box.data, let response = box.response else {
            throw LocalControlTransportError.invalidHTTPResponse("missing response data")
        }
        return (data, response)
    }
}
