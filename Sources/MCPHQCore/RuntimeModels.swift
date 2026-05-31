import Foundation

public enum RuntimeOwnership: String, Codable, Equatable, Sendable {
    case agentOwned
    case hubOwned
    case unknown

    public var displayLabel: String {
        switch self {
        case .agentOwned:
            return "Agent-owned"
        case .hubOwned:
            return "Hub-owned"
        case .unknown:
            return "Unknown ownership"
        }
    }
}

public enum RuntimeInstanceStatus: String, Codable, Equatable, Sendable {
    case observed
    case starting
    case healthy
    case degraded
    case stopping
    case stopped
    case error
}

public enum RuntimeLogStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
    case supervisor
}

public struct RuntimeLogEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let runtimeInstanceID: String
    public let stream: RuntimeLogStream
    public let timestamp: Date
    public let message: String

    public init(
        id: String = UUID().uuidString,
        runtimeInstanceID: String,
        stream: RuntimeLogStream,
        timestamp: Date = Date(),
        message: String
    ) {
        self.id = id
        self.runtimeInstanceID = runtimeInstanceID
        self.stream = stream
        self.timestamp = timestamp
        self.message = SecretRedactor.redactText(message)
    }
}

public struct RuntimeInstance: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let serverID: String?
    public let pid: Int32?
    public let ownership: RuntimeOwnership
    public let commandLine: String
    public let startedAt: Date?
    public let cpuPercent: Double?
    public let memoryBytes: UInt64?
    public let status: RuntimeInstanceStatus
    public let lastError: String?
    public let logPath: String?

    public init(
        id: String,
        serverID: String? = nil,
        pid: Int32? = nil,
        ownership: RuntimeOwnership,
        commandLine: String,
        startedAt: Date? = nil,
        cpuPercent: Double? = nil,
        memoryBytes: UInt64? = nil,
        status: RuntimeInstanceStatus,
        lastError: String? = nil,
        logPath: String? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.pid = pid
        self.ownership = ownership
        self.commandLine = SecretRedactor.redactText(commandLine)
        self.startedAt = startedAt
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.status = status
        self.lastError = lastError.map(SecretRedactor.redactText)
        self.logPath = logPath
    }
}
