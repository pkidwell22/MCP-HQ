import Foundation

public struct ServerDiagnosticChecker {
    private let commandExists: (String, [String: String]) -> Bool

    public init() {
        self.commandExists = ServerDiagnosticChecker.defaultCommandExists
    }

    public init(commandExists: @escaping (String, [String: String]) -> Bool) {
        self.commandExists = commandExists
    }

    public func issues(servers: [ServerDefinition], sources: [ConfigSource]) -> [ScanIssue] {
        let sourcesByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.path, $0) })
        return servers.compactMap { server in
            guard server.transport == .stdio else { return nil }
            guard let command = server.command, !command.isEmpty else { return nil }
            guard !commandExists(command, server.envBindings) else { return nil }
            let source = sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath)
            return ScanIssue(
                source: source,
                severity: .warning,
                message: "Command not found for \(server.displayName): \(command). Install it or update PATH/config before launching this MCP server."
            )
        }
    }

    private static func defaultCommandExists(command: String, environment: [String: String]) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expandedHomePath(trimmed))
        }

        let pathValue = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? defaultSearchPath
        return pathValue.split(separator: ":").contains { directory in
            let candidate = URL(fileURLWithPath: expandedHomePath(String(directory)))
                .appendingPathComponent(trimmed)
                .path
            return FileManager.default.isExecutableFile(atPath: candidate)
        }
    }

    private static func expandedHomePath(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" { return home }
        return home + String(path.dropFirst())
    }

    private static let defaultSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}
