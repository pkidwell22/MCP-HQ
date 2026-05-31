import Foundation

public enum LocalControlClientBackend: String, Codable, Equatable, Sendable {
    case directCore = "direct_core"
    case endpointHTTP = "endpoint_http"

    public var displayName: String {
        switch self {
        case .directCore:
            return "Direct core"
        case .endpointHTTP:
            return "Endpoint HTTP"
        }
    }
}

public struct LocalControlClientState: Codable, Equatable, Sendable {
    public let backend: LocalControlClientBackend
    public let endpointFilePath: String?
    public let endpointURL: String?
    public let endpointPID: Int32?
    public let endpointStartedAt: Date?
    public let endpointHasToken: Bool
    public let availability: LocalControlEndpointAvailability

    public init(
        backend: LocalControlClientBackend,
        endpointFilePath: String? = nil,
        endpoint: LocalControlEndpoint? = nil,
        availability: LocalControlEndpointAvailability
    ) {
        self.backend = backend
        self.endpointFilePath = endpointFilePath.map(SecretRedactor.redactText)
        self.endpointURL = endpoint.map { SecretRedactor.redactText($0.controlURL.absoluteString) }
        self.endpointPID = endpoint?.pid
        self.endpointStartedAt = endpoint?.startedAt
        self.endpointHasToken = endpoint?.token?.isEmpty == false
        self.availability = availability
    }
}

public struct LocalControlClientExchange: Sendable {
    public let response: LocalControlResponse
    public let state: LocalControlClientState

    public init(response: LocalControlResponse, state: LocalControlClientState) {
        self.response = response
        self.state = state
    }
}

public struct LocalControlClientStateHelper: Sendable {
    private let endpointClientFactory: @Sendable (LocalControlEndpointStore) -> LocalControlHTTPClient

    public init(
        endpointClientFactory: @escaping @Sendable (LocalControlEndpointStore) -> LocalControlHTTPClient = { LocalControlHTTPClient(endpointStore: $0) }
    ) {
        self.endpointClientFactory = endpointClientFactory
    }

    public func state(endpointFile: String?) -> LocalControlClientState {
        guard let endpointFile else {
            return LocalControlClientState(
                backend: .directCore,
                availability: LocalControlEndpointAvailability(state: .unknown, message: "Using direct in-process core")
            )
        }
        return state(endpointStore: LocalControlEndpointStore(fileURL: URL(fileURLWithPath: endpointFile)))
    }

    public func state(endpointStore: LocalControlEndpointStore) -> LocalControlClientState {
        do {
            let endpoint = try endpointStore.load()
            return endpointState(
                endpointStore: endpointStore,
                endpoint: endpoint,
                availability: LocalControlEndpointAvailability.metadataOnly(endpoint)
            )
        } catch {
            return LocalControlClientState(
                backend: .endpointHTTP,
                endpointFilePath: endpointStore.fileURL.path,
                availability: LocalControlEndpointAvailability(
                    state: .unavailable,
                    message: "Endpoint unavailable: \(SecretRedactor.redactText(String(describing: error)))"
                )
            )
        }
    }

    public func send(
        _ request: LocalControlRequest,
        endpointFile: String?,
        directClient: @Sendable () throws -> LocalControlInProcessClient
    ) throws -> LocalControlClientExchange {
        if let endpointFile {
            let endpointStore = LocalControlEndpointStore(fileURL: URL(fileURLWithPath: endpointFile))
            let response = try endpointClientFactory(endpointStore).send(request)
            return LocalControlClientExchange(response: response, state: state(endpointStore: endpointStore))
        }

        let response = try directClient().send(request)
        return LocalControlClientExchange(response: response, state: state(endpointFile: nil))
    }

    public func sendPreferringEndpoint(
        _ request: LocalControlRequest,
        endpointStore: LocalControlEndpointStore,
        directResponse: @Sendable () throws -> LocalControlResponse
    ) throws -> LocalControlClientExchange {
        do {
            let endpoint = try endpointStore.load()
            let response = try endpointClientFactory(endpointStore).send(request)
            return LocalControlClientExchange(
                response: response,
                state: endpointState(
                    endpointStore: endpointStore,
                    endpoint: endpoint,
                    availability: LocalControlEndpointAvailability(
                        state: .available,
                        message: "Endpoint responded: \(SecretRedactor.redactText(endpoint.controlURL.absoluteString))"
                    )
                )
            )
        } catch {
            guard request.allowsDirectCoreFallback else { throw error }
            let response = try directResponse()
            return LocalControlClientExchange(
                response: response,
                state: directFallbackState(endpointStore: endpointStore, error: error)
            )
        }
    }

    public func sendPreferringEndpoint(
        _ request: LocalControlRequest,
        endpointFile: String?,
        directResponse: @Sendable () throws -> LocalControlResponse
    ) throws -> LocalControlClientExchange {
        guard let endpointFile else {
            return LocalControlClientExchange(response: try directResponse(), state: state(endpointFile: nil))
        }
        return try sendPreferringEndpoint(
            request,
            endpointStore: LocalControlEndpointStore(fileURL: URL(fileURLWithPath: endpointFile)),
            directResponse: directResponse
        )
    }

    private func endpointState(
        endpointStore: LocalControlEndpointStore,
        endpoint: LocalControlEndpoint,
        availability: LocalControlEndpointAvailability
    ) -> LocalControlClientState {
        LocalControlClientState(
            backend: .endpointHTTP,
            endpointFilePath: endpointStore.fileURL.path,
            endpoint: endpoint,
            availability: availability
        )
    }

    private func directFallbackState(endpointStore: LocalControlEndpointStore, error: Error) -> LocalControlClientState {
        LocalControlClientState(
            backend: .directCore,
            endpointFilePath: endpointStore.fileURL.path,
            availability: LocalControlEndpointAvailability(
                state: .unavailable,
                message: "Endpoint unavailable; using direct in-process core: \(SecretRedactor.redactText(String(describing: error)))"
            )
        )
    }
}
