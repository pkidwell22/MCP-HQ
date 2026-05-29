import Foundation

public enum MCPTransport: String, Codable, Equatable, Sendable {
    case stdio
    case http
    case sse
    case streamableHTTP = "streamable_http"
}

public struct ServerDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let transport: MCPTransport
    public let command: String?
    public let args: [String]
    public let url: String?
    public let envBindings: [String: String]
    public let sourcePath: String

    public init(
        id: String,
        displayName: String,
        transport: MCPTransport,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        envBindings: [String: String] = [:],
        sourcePath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.envBindings = envBindings
        self.sourcePath = sourcePath
    }
}
