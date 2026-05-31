import Foundation
import XCTest
@testable import MCPHQCore

final class AgentCanonicalDriftActionExecutorTests: XCTestCase {
    func testExecutorRestoresMissingDesiredBindingWithSingleSourcePreviewAndApply() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourcePath = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{}}"#.write(to: sourcePath, atomically: true, encoding: .utf8)
        let source = ConfigSource(agent: .claude, path: sourcePath.path)
        let template = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: directory.appendingPathComponent("hermes.yaml").path
        )

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [], sources: [source]),
            desiredStates: [
                SQLiteDesiredServerState(
                    source: source,
                    serverName: "memory",
                    enabled: true,
                    server: template,
                    updatedAt: Date(timeIntervalSince1970: 1)
                )
            ]
        )
        let action = try XCTUnwrap(
            AgentCanonicalDriftActionPlanner().suggestedActions(for: model).first(where: { $0.operation == .bindingDraftEnable })
        )
        let executor = AgentCanonicalDriftActionExecutor()
        let draft = try executor.draft(for: action, templateServer: template, targetSource: source, existingServers: [])

        XCTAssertEqual(draft.changedPreviews.count, 1)
        XCTAssertEqual(draft.changedPreviews.first?.source, source)
        XCTAssertEqual(draft.changedPreviews.first?.isEnabled, true)

        let result = try executor.apply(for: action, templateServer: template, targetSource: source, existingServers: [])
        XCTAssertEqual(result.appliedTargets.count, 1)

        let data = try Data(contentsOf: sourcePath)
        let parsed = try AgentConfigParser().parse(data: data, source: source)
        XCTAssertEqual(parsed.map(\.displayName), ["memory"])
    }

    func testExecutorDisablesPresentBindingForSingleSourceApply() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourcePath = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: sourcePath, atomically: true, encoding: .utf8)
        let source = ConfigSource(agent: .claude, path: sourcePath.path)
        let template = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: directory.appendingPathComponent("hermes.yaml").path
        )
        let existing = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: source.agent, sourcePath: source.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )

        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [existing], sources: [source]),
            desiredStates: [
                SQLiteDesiredServerState(
                    source: source,
                    serverName: "memory",
                    enabled: false,
                    server: template,
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            ]
        )
        let action = try XCTUnwrap(
            AgentCanonicalDriftActionPlanner().suggestedActions(for: model).first(where: { $0.operation == .bindingDraftDisable })
        )
        let executor = AgentCanonicalDriftActionExecutor()
        let draft = try executor.draft(for: action, templateServer: template, targetSource: source, existingServers: [existing])

        XCTAssertEqual(draft.changedPreviews.count, 1)
        XCTAssertEqual(draft.changedPreviews.first?.isEnabled, false)

        let result = try executor.apply(for: action, templateServer: template, targetSource: source, existingServers: [existing])
        XCTAssertEqual(result.appliedTargets.count, 1)

        let data = try Data(contentsOf: sourcePath)
        let parsed = try AgentConfigParser().parse(data: data, source: source)
        XCTAssertTrue(parsed.isEmpty)
    }

    func testExecutorRejectsPayloadMismatchReplacementApply() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourcePath = directory.appendingPathComponent("claude.json")
        try #"{"mcpServers":{"memory":{"command":"npx","args":["-y","@modelcontextprotocol/server-memory"]}}}"#
            .write(to: sourcePath, atomically: true, encoding: .utf8)
        let source = ConfigSource(agent: .claude, path: sourcePath.path)
        let scanned = ServerDefinition(
            id: ServerDefinition.canonicalID(agent: source.agent, sourcePath: source.path, name: "memory"),
            displayName: "memory",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            sourcePath: source.path
        )
        let desired = ServerDefinition(
            id: "template:memory",
            displayName: "memory",
            transport: .stdio,
            command: "node",
            args: ["server.js"],
            sourcePath: directory.appendingPathComponent("hermes.yaml").path
        )
        let model = AgentCanonicalAuthoringModel(
            scanResult: ScanResult(servers: [scanned], sources: [source]),
            desiredStates: [
                SQLiteDesiredServerState(
                    source: source,
                    serverName: "memory",
                    enabled: true,
                    server: desired,
                    updatedAt: Date(timeIntervalSince1970: 3)
                )
            ]
        )
        let action = try XCTUnwrap(
            AgentCanonicalDriftActionPlanner().suggestedActions(for: model).first(where: { $0.operation == .payloadReplacementPreview })
        )
        let executor = AgentCanonicalDriftActionExecutor()

        let draft = try executor.draft(for: action, templateServer: desired, targetSource: source, existingServers: [scanned])
        XCTAssertEqual(draft.changedPreviews.count, 1)
        XCTAssertFalse(executor.canApply(action))

        XCTAssertThrowsError(try executor.apply(for: action, templateServer: desired, targetSource: source, existingServers: [scanned])) { error in
            guard let error = error as? AgentCanonicalDriftActionExecutorError else {
                return XCTFail("Expected AgentCanonicalDriftActionExecutorError, got \(error)")
            }
            XCTAssertEqual(error, .cannotApplyReviewRequiredAction(.replacePayloadWithDesiredState))
        }
    }
}
