import Foundation

public enum MCPTransport: String, Codable, Equatable, Sendable {
    case stdio
    case http
    case sse
    case streamableHTTP = "streamable_http"

    public init(configValue: String?) {
        switch configValue?.lowercased() {
        case "sse":
            self = .sse
        case "streamable_http", "streamablehttp":
            self = .streamableHTTP
        case "http":
            self = .http
        default:
            self = .http
        }
    }
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

    public var redactedEnvBindings: [String: String] {
        envBindings.mapValues { SecretRedactor.redactIfSensitive($0) }
    }

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

public enum SecretRedactor {
    public static func redactIfSensitive(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("${") && trimmed.hasSuffix("}") { return value }
        if trimmed.hasPrefix("$") { return value }
        if trimmed.count < 8 { return value }

        let lowercased = trimmed.lowercased()
        let sensitivePrefixes = ["ghp_", "github_pat_", "sk-", "xoxb-", "xoxp-"]
        if sensitivePrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return "<redacted>"
        }

        let hasLetters = trimmed.rangeOfCharacter(from: .letters) != nil
        let hasDigits = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let looksTokenLike = trimmed.count >= 20 && hasLetters && hasDigits
        return looksTokenLike ? "<redacted>" : value
    }
}
