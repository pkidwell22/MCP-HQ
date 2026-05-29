import Foundation

public struct ServerDiagnosticChecker {
    private let commandExists: (String, [String: String]) -> Bool
    private let environmentValue: (String) -> String?

    public init() {
        self.commandExists = ServerDiagnosticChecker.defaultCommandExists
        self.environmentValue = { ProcessInfo.processInfo.environment[$0] }
    }

    public init(
        commandExists: @escaping (String, [String: String]) -> Bool,
        environmentValue: @escaping (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) {
        self.commandExists = commandExists
        self.environmentValue = environmentValue
    }

    public func issues(servers: [ServerDefinition], sources: [ConfigSource]) -> [ScanIssue] {
        let sourcesByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.path, $0) })
        return servers.flatMap { server in
            issues(for: server, source: sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath))
        }
    }

    private func issues(for server: ServerDefinition, source: ConfigSource) -> [ScanIssue] {
        var issues: [ScanIssue] = []

        if server.transport == .stdio, let command = server.command, !command.isEmpty, !commandExists(command, server.envBindings) {
            issues.append(ScanIssue(
                source: source,
                severity: .warning,
                message: "Command not found for \(server.displayName): \(command). Install it or update PATH/config before launching this MCP server."
            ))
        }

        for key in server.envBindings.keys.sorted() {
            guard let value = server.envBindings[key] else { continue }
            if let issue = envIssue(server: server, source: source, key: key, value: value) {
                issues.append(issue)
            }
        }

        return issues
    }

    private func envIssue(server: ServerDefinition, source: ConfigSource, key: String, value: String) -> ScanIssue? {
        guard isSensitiveEnvKey(key) else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            return ScanIssue(
                source: source,
                severity: .warning,
                message: "Missing env var for \(server.displayName): \(key). Add it to Keychain or configure the environment before launching this MCP server."
            )
        }

        guard let referencedName = referencedEnvironmentName(from: trimmedValue) else { return nil }
        let referencedValue = environmentValue(referencedName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard referencedValue.isEmpty else { return nil }
        return ScanIssue(
            source: source,
            severity: .warning,
            message: "Missing env var for \(server.displayName): \(referencedName) referenced by \(key). Add it to Keychain or configure the environment before launching this MCP server."
        )
    }

    private func referencedEnvironmentName(from value: String) -> String? {
        if value.hasPrefix("${"), value.hasSuffix("}"), value.count > 3 {
            return String(value.dropFirst(2).dropLast())
        }
        if value.hasPrefix("$"), value.count > 1 {
            return String(value.dropFirst())
        }
        return nil
    }

    private func isSensitiveEnvKey(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        let sensitiveParts = ["token", "api_key", "apikey", "secret", "password", "authorization", "auth"]
        return sensitiveParts.contains { normalized.contains($0) }
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
