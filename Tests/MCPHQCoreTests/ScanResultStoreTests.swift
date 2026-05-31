import XCTest
@testable import MCPHQCore

final class ScanResultStoreTests: XCTestCase {
    func testHealthCacheSaveAndLoadRoundTripsSummaryWithoutSecrets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("health-cache.json")
        let store = JSONHealthCacheStore(fileURL: fileURL)
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")
        let missingSource = ConfigSource(agent: .pi, path: "/tmp/missing.json")
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "claude:/tmp/claude.json:github",
                    displayName: "github",
                    transport: .stdio,
                    command: "npx",
                    args: ["--token", "ghp_healthCacheSecret1234567890"],
                    sourcePath: source.path
                )
            ],
            sources: [source],
            issues: [ScanIssue(source: source, severity: .warning, message: "token=ghp_healthCacheSecret1234567890 missing")]
        )
        let date = Date(timeIntervalSince1970: 1_700_000_100)

        try store.save(result: result, scannedAt: date, sources: [source, missingSource], includesProbes: false)

        let snapshot = try XCTUnwrap(store.load())
        XCTAssertEqual(snapshot.scanStatus, .completed)
        XCTAssertEqual(snapshot.scannedAt, date)
        XCTAssertEqual(snapshot.sourceIDs, [missingSource.id, source.id].sorted())
        XCTAssertEqual(snapshot.counts.serverCount, 1)
        XCTAssertEqual(snapshot.counts.warningCount, 1)
        XCTAssertTrue(snapshot.matches(sources: [source, missingSource], includesProbes: false))
        XCTAssertFalse(String(describing: snapshot).contains("ghp_healthCacheSecret"))
    }

    func testHealthCacheFailureMessageIsRedacted() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONHealthCacheStore(fileURL: tempDirectory.appendingPathComponent("health-cache.json"))
        let source = ConfigSource(agent: .claude, path: "/tmp/claude.json")

        try store.saveFailure(
            message: "scan failed token=ghp_healthCacheFailure1234567890",
            scannedAt: Date(timeIntervalSince1970: 1_700_000_200),
            sources: [source],
            includesProbes: true
        )

        let snapshot = try XCTUnwrap(store.load())
        XCTAssertEqual(snapshot.scanStatus, .failed)
        XCTAssertEqual(snapshot.message, "scan failed token=<redacted>")
        XCTAssertFalse(String(describing: snapshot).contains("ghp_healthCacheFailure"))
    }

    func testSaveAndLoadRoundTripsScanResultWithTimestamp() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("last-scan.json")
        let store = JSONScanResultStore(fileURL: fileURL)
        let source = ConfigSource(agent: .codex, path: "/tmp/config.toml")
        let result = ScanResult(
            servers: [
                ServerDefinition(
                    id: "codex:/tmp/config.toml:memory",
                    displayName: "memory",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-memory"],
                    sourcePath: source.path
                )
            ],
            sources: [source],
            sourceHealth: [ConfigSourceHealth(source: source, state: .parsed, serverCount: 1, message: "Found config")]
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try store.save(result, scannedAt: date)

        let stored = try XCTUnwrap(store.load())
        XCTAssertEqual(stored.result, result)
        XCTAssertEqual(stored.scannedAt, date)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLoadMissingStoreReturnsNil() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.json")
        let store = JSONScanResultStore(fileURL: fileURL)

        XCTAssertNil(try store.load())
    }
}
