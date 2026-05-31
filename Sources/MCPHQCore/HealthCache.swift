import Foundation

public enum HealthCacheScanStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
}

public enum HealthCacheFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case stale
}

public enum HealthCacheAgeFormatter {
    public static func relativeAge(seconds: Int) -> String {
        let clamped = max(0, seconds)
        if clamped < 5 { return "just now" }
        if clamped < 60 { return "\(clamped)s ago" }
        if clamped < 3_600 { return "\(clamped / 60)m ago" }
        if clamped < 86_400 {
            let hours = clamped / 3_600
            let minutes = (clamped % 3_600) / 60
            return minutes == 0 ? "\(hours)h ago" : "\(hours)h \(minutes)m ago"
        }
        let days = clamped / 86_400
        let hours = (clamped % 86_400) / 3_600
        return hours == 0 ? "\(days)d ago" : "\(days)d \(hours)h ago"
    }

    public static func duration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 { return "\(clamped)s" }
        if clamped < 3_600 { return "\(clamped / 60)m" }
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

public struct HealthSummaryCounts: Codable, Equatable, Sendable {
    public let serverCount: Int
    public let sourceCount: Int
    public let processCount: Int
    public let issueCount: Int
    public let warningCount: Int
    public let errorCount: Int

    public init(
        serverCount: Int,
        sourceCount: Int,
        processCount: Int,
        issueCount: Int,
        warningCount: Int,
        errorCount: Int
    ) {
        self.serverCount = serverCount
        self.sourceCount = sourceCount
        self.processCount = processCount
        self.issueCount = issueCount
        self.warningCount = warningCount
        self.errorCount = errorCount
    }

    public init(result: ScanResult) {
        let probeWarnings = result.probeResults.filter { $0.status == .warning }.count
        let probeErrors = result.probeResults.filter { $0.status == .error }.count
        self.serverCount = result.servers.count
        self.sourceCount = result.sourceHealth.isEmpty ? result.sources.count : result.sourceHealth.count
        self.processCount = result.processes.count
        self.issueCount = result.issues.count + probeWarnings + probeErrors
        self.warningCount = result.issues.filter { $0.severity == .warning }.count + probeWarnings
        self.errorCount = result.issues.filter { $0.severity == .error }.count + probeErrors
    }
}

public struct HealthCacheSnapshot: Codable, Equatable, Sendable {
    public static let defaultStaleAfterSeconds = 300

    public let scanStatus: HealthCacheScanStatus
    public let scannedAt: Date
    public let sourceIDs: [String]
    public let includesProbes: Bool
    public let counts: HealthSummaryCounts
    public let message: String?

    public init(
        scanStatus: HealthCacheScanStatus,
        scannedAt: Date,
        sourceIDs: [String],
        includesProbes: Bool,
        counts: HealthSummaryCounts,
        message: String? = nil
    ) {
        self.scanStatus = scanStatus
        self.scannedAt = scannedAt
        self.sourceIDs = sourceIDs.sorted()
        self.includesProbes = includesProbes
        self.counts = counts
        self.message = message.map(SecretRedactor.redactText)
    }

    public init(result: ScanResult, scannedAt: Date, sources: [ConfigSource], includesProbes: Bool) {
        self.init(
            scanStatus: .completed,
            scannedAt: scannedAt,
            sourceIDs: sources.map(\.id),
            includesProbes: includesProbes,
            counts: HealthSummaryCounts(result: result)
        )
    }

    public func matches(sources: [ConfigSource], includesProbes: Bool) -> Bool {
        self.includesProbes == includesProbes && sourceIDs == sources.map(\.id).sorted()
    }

    public func ageSeconds(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(scannedAt)))
    }

    public func isStale(at date: Date, staleAfterSeconds: Int = HealthCacheSnapshot.defaultStaleAfterSeconds) -> Bool {
        ageSeconds(at: date) >= max(0, staleAfterSeconds)
    }

    public func freshness(at date: Date, staleAfterSeconds: Int = HealthCacheSnapshot.defaultStaleAfterSeconds) -> HealthCacheFreshness {
        isStale(at: date, staleAfterSeconds: staleAfterSeconds) ? .stale : .fresh
    }
}

public enum HealthCacheStoreError: Error, Equatable, CustomStringConvertible {
    case invalidApplicationSupportDirectory

    public var description: String {
        switch self {
        case .invalidApplicationSupportDirectory:
            return "Could not resolve the Application Support directory"
        }
    }
}

public struct JSONHealthCacheStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func applicationSupport(fileManager: FileManager = .default) throws -> JSONHealthCacheStore {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HealthCacheStoreError.invalidApplicationSupportDirectory
        }
        let fileURL = directory
            .appendingPathComponent("MCP-HQ", isDirectory: true)
            .appendingPathComponent("health-cache.json")
        return JSONHealthCacheStore(fileURL: fileURL, fileManager: fileManager)
    }

    public func load() throws -> HealthCacheSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(HealthCacheSnapshot.self, from: data)
    }

    public func save(_ snapshot: HealthCacheSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func save(result: ScanResult, scannedAt: Date = Date(), sources: [ConfigSource], includesProbes: Bool) throws {
        try save(HealthCacheSnapshot(result: result, scannedAt: scannedAt, sources: sources, includesProbes: includesProbes))
    }

    public func saveFailure(
        message: String,
        scannedAt: Date = Date(),
        sources: [ConfigSource],
        includesProbes: Bool,
        previousCounts: HealthSummaryCounts = HealthSummaryCounts(
            serverCount: 0,
            sourceCount: 0,
            processCount: 0,
            issueCount: 0,
            warningCount: 0,
            errorCount: 0
        )
    ) throws {
        try save(HealthCacheSnapshot(
            scanStatus: .failed,
            scannedAt: scannedAt,
            sourceIDs: sources.map(\.id),
            includesProbes: includesProbes,
            counts: previousCounts,
            message: message
        ))
    }
}
