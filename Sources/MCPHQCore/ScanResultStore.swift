import Foundation

public struct StoredScanResult: Codable, Equatable, Sendable {
    public let result: ScanResult
    public let scannedAt: Date

    public init(result: ScanResult, scannedAt: Date) {
        self.result = result
        self.scannedAt = scannedAt
    }
}

public enum ScanResultStoreError: Error, Equatable, CustomStringConvertible {
    case invalidApplicationSupportDirectory
    case invalidUTF8

    public var description: String {
        switch self {
        case .invalidApplicationSupportDirectory:
            return "Could not resolve the Application Support directory"
        case .invalidUTF8:
            return "Stored scan result was not valid UTF-8"
        }
    }
}

public struct JSONScanResultStore: @unchecked Sendable {
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

    public static func applicationSupport(fileManager: FileManager = .default) throws -> JSONScanResultStore {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ScanResultStoreError.invalidApplicationSupportDirectory
        }
        let fileURL = directory
            .appendingPathComponent("MCP-HQ", isDirectory: true)
            .appendingPathComponent("last-scan.json")
        return JSONScanResultStore(fileURL: fileURL, fileManager: fileManager)
    }

    public func load() throws -> StoredScanResult? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(StoredScanResult.self, from: data)
    }

    public func save(_ result: ScanResult, scannedAt: Date = Date()) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = StoredScanResult(result: result, scannedAt: scannedAt)
        let data = try encoder.encode(stored)
        try data.write(to: fileURL, options: [.atomic])
    }
}
