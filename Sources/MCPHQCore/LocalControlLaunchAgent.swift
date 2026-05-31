import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct LocalControlLaunchAgentConfiguration: Equatable, Sendable {
    public let label: String
    public let programPath: String
    public let endpointFilePath: String
    public let port: UInt16?
    public let token: String?
    public let requiresToken: Bool
    public let standardOutPath: String
    public let standardErrorPath: String
    public let keepAlive: Bool
    public let runAtLoad: Bool
    public let environmentVariables: [String: String]

    public init(
        label: String = "com.mcphq.control",
        programPath: String,
        endpointFilePath: String = LocalControlEndpointStore.defaultStore().fileURL.path,
        port: UInt16? = nil,
        token: String? = nil,
        requiresToken: Bool = true,
        standardOutPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MCP-HQ/logs/control.out.log").path,
        standardErrorPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MCP-HQ/logs/control.err.log").path,
        keepAlive: Bool = true,
        runAtLoad: Bool = true,
        environmentVariables: [String: String] = LocalControlLaunchAgentConfiguration.defaultEnvironmentVariables()
    ) {
        self.label = label
        self.programPath = programPath
        self.endpointFilePath = endpointFilePath
        self.port = port
        self.token = token
        self.requiresToken = requiresToken
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.keepAlive = keepAlive
        self.runAtLoad = runAtLoad
        self.environmentVariables = environmentVariables
    }

    public var programArguments: [String] {
        var arguments = [
            programPath,
            "control",
            "serve",
            "--endpoint-file",
            endpointFilePath,
        ]
        if let port {
            arguments.append(contentsOf: ["--port", String(port)])
        }
        if let token {
            arguments.append(contentsOf: ["--token", token])
        } else if !requiresToken {
            arguments.append("--no-token")
        }
        return arguments
    }

    public var plistDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive,
            "StandardOutPath": standardOutPath,
            "StandardErrorPath": standardErrorPath,
            "WorkingDirectory": URL(fileURLWithPath: programPath).deletingLastPathComponent().path,
        ]
        if !environmentVariables.isEmpty {
            dictionary["EnvironmentVariables"] = environmentVariables
        }
        return dictionary
    }

    public static func defaultEnvironmentVariables(
        currentPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> [String: String] {
        ["PATH": defaultLaunchPath(currentPath: currentPath)]
    }

    public static func defaultLaunchPath(currentPath: String?) -> String {
        var seen = Set<String>()
        var directories: [String] = []
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            directories.append(trimmed)
        }

        currentPath?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
            .forEach(append)

        [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].forEach(append)

        return directories.joined(separator: ":")
    }
}

public struct LocalControlLaunchAgentInstallResult: Equatable, Sendable {
    public let plistPath: String
    public let didWrite: Bool
    public let plistText: String
    public let bootstrapCommand: String
    public let bootoutCommand: String
}

public struct LocalControlLaunchAgentCommandResult: Equatable, Sendable {
    public let command: [String]
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(command: [String], exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.command = command
        self.exitCode = exitCode
        self.stdout = SecretRedactor.redactText(stdout)
        self.stderr = SecretRedactor.redactText(stderr)
    }
}

public enum LocalControlLaunchAgentLoadState: String, Equatable, Sendable {
    case loaded
    case notLoaded
    case unknown
}

public struct LocalControlLaunchAgentStatus: Equatable, Sendable {
    public let plistPath: String
    public let isInstalled: Bool
    public let endpoint: LocalControlEndpoint?
    public let launchdState: LocalControlLaunchAgentLoadState
    public let launchdMessage: String?
}

public enum LocalControlHelperPathSource: String, Equatable, Sendable {
    case bundledAppHelper
    case siblingExecutable
    case pathLookup
    case missing

    public var displayName: String {
        switch self {
        case .bundledAppHelper:
            return "Bundled app helper"
        case .siblingExecutable:
            return "Sibling executable"
        case .pathLookup:
            return "PATH lookup"
        case .missing:
            return "Not found"
        }
    }
}

public struct LocalControlHelperPathResolution: Equatable, Sendable {
    public let path: String
    public let source: LocalControlHelperPathSource
    public let exists: Bool

    public init(path: String, source: LocalControlHelperPathSource, exists: Bool) {
        self.path = path
        self.source = source
        self.exists = exists
    }
}

public struct LocalControlHelperPathResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environmentPath: String?

    public init(
        fileManager: FileManager = .default,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) {
        self.fileManager = fileManager
        self.environmentPath = environmentPath
    }

    public func resolve(
        bundleURL: URL = Bundle.main.bundleURL,
        executablePath: String? = ProcessInfo.processInfo.arguments.first
    ) -> LocalControlHelperPathResolution {
        let bundledHelper = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("mcphq")
            .standardizedFileURL
        if isExecutable(bundledHelper) {
            return LocalControlHelperPathResolution(path: bundledHelper.path, source: .bundledAppHelper, exists: true)
        }

        var fallbackPath = bundledHelper.path
        if let executablePath, !executablePath.isEmpty {
            let siblingHelper = URL(fileURLWithPath: executablePath)
                .standardizedFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("mcphq")
            fallbackPath = siblingHelper.path
            if isExecutable(siblingHelper) {
                return LocalControlHelperPathResolution(path: siblingHelper.path, source: .siblingExecutable, exists: true)
            }
        }

        for directory in environmentPath?.split(separator: ":") ?? [] {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent("mcphq")
            if isExecutable(candidate) {
                return LocalControlHelperPathResolution(path: candidate.path, source: .pathLookup, exists: true)
            }
        }

        return LocalControlHelperPathResolution(path: fallbackPath, source: .missing, exists: false)
    }

    private func isExecutable(_ url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }
}

public enum LocalControlEndpointAvailabilityState: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct LocalControlEndpointAvailability: Codable, Equatable, Sendable {
    public let state: LocalControlEndpointAvailabilityState
    public let message: String

    public init(state: LocalControlEndpointAvailabilityState, message: String) {
        self.state = state
        self.message = SecretRedactor.redactText(message)
    }

    public static let unknown = LocalControlEndpointAvailability(state: .unknown, message: "Not checked")

    public static func metadataOnly(_ endpoint: LocalControlEndpoint?) -> LocalControlEndpointAvailability {
        guard let endpoint else {
            return LocalControlEndpointAvailability(state: .unavailable, message: "No endpoint file found")
        }
        return LocalControlEndpointAvailability(state: .unknown, message: "Endpoint file: \(endpoint.controlURL.absoluteString)")
    }
}

public struct LocalControlEndpointChecker: Sendable {
    private let checkImplementation: @Sendable (LocalControlEndpointStore) -> LocalControlEndpointAvailability

    public init(timeout: TimeInterval = 0.75) {
        self.checkImplementation = { endpointStore in
            do {
                guard FileManager.default.fileExists(atPath: endpointStore.fileURL.path) else {
                    return LocalControlEndpointAvailability(state: .unavailable, message: "No endpoint file found")
                }
                let endpoint = try endpointStore.load()
                let response = try LocalControlHTTPClient(endpointStore: endpointStore, timeout: timeout)
                    .send(LocalControlRequest(route: .status), id: "helper-ui-status")
                var message = endpoint.controlURL.absoluteString
                if let status = response.status,
                   let freshness = status.cacheFreshness,
                   let ageSeconds = status.cacheAgeSeconds {
                    message += " - cache \(freshness.rawValue), age \(HealthCacheAgeFormatter.relativeAge(seconds: ageSeconds))"
                    if status.cacheRefreshRecommended == true {
                        message += ", refresh recommended"
                    }
                }
                return LocalControlEndpointAvailability(state: .available, message: message)
            } catch {
                return LocalControlEndpointAvailability(
                    state: .unavailable,
                    message: SecretRedactor.redactText(String(describing: error))
                )
            }
        }
    }

    public init(checkImplementation: @escaping @Sendable (LocalControlEndpointStore) -> LocalControlEndpointAvailability) {
        self.checkImplementation = checkImplementation
    }

    public func check(endpointStore: LocalControlEndpointStore = .defaultStore()) -> LocalControlEndpointAvailability {
        checkImplementation(endpointStore)
    }
}

public struct LocalControlHelperStatusSnapshot: Equatable, Sendable {
    public let launchAgentStatus: LocalControlLaunchAgentStatus
    public let helperPath: LocalControlHelperPathResolution
    public let endpointAvailability: LocalControlEndpointAvailability

    public init(
        launchAgentStatus: LocalControlLaunchAgentStatus,
        helperPath: LocalControlHelperPathResolution,
        endpointAvailability: LocalControlEndpointAvailability = .unknown
    ) {
        self.launchAgentStatus = launchAgentStatus
        self.helperPath = helperPath
        self.endpointAvailability = endpointAvailability
    }

    public var installedLabel: String {
        launchAgentStatus.isInstalled ? "Installed" : "Not installed"
    }

    public var launchdLabel: String {
        switch launchAgentStatus.launchdState {
        case .loaded:
            return "Loaded"
        case .notLoaded:
            return "Not loaded"
        case .unknown:
            return "Unknown"
        }
    }

    public var endpointLabel: String {
        switch endpointAvailability.state {
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        case .unknown:
            return "Unknown"
        }
    }

    public var helperPathLabel: String {
        helperPath.exists ? "\(helperPath.source.displayName): \(helperPath.path)" : "Missing: \(helperPath.path)"
    }

    public var canInstallPlist: Bool {
        helperPath.exists
    }

    public var canBootstrap: Bool {
        launchAgentStatus.isInstalled && helperPath.exists && launchAgentStatus.launchdState != .loaded
    }

    public var canBootout: Bool {
        launchAgentStatus.launchdState == .loaded
    }

    public var canInstallAndBootstrap: Bool {
        helperPath.exists && launchAgentStatus.launchdState != .loaded
    }

    public var installDisabledReason: String? {
        helperPath.exists ? nil : "The mcphq helper executable was not found. Build/package the app so Contents/MacOS/mcphq is present."
    }

    public var bootstrapDisabledReason: String? {
        if !helperPath.exists {
            return installDisabledReason
        }
        if !launchAgentStatus.isInstalled {
            return "Install the LaunchAgent plist before starting the helper."
        }
        if launchAgentStatus.launchdState == .loaded {
            return "The helper is already loaded."
        }
        return nil
    }

    public var bootoutDisabledReason: String? {
        launchAgentStatus.launchdState == .loaded ? nil : "The helper is not loaded."
    }

    public var installAndBootstrapDisabledReason: String? {
        if !helperPath.exists {
            return installDisabledReason
        }
        if launchAgentStatus.launchdState == .loaded {
            return "The helper is already loaded."
        }
        return nil
    }
}

public struct LocalControlLaunchAgentManager: @unchecked Sendable {
    public let launchAgentsDirectory: URL
    private let fileManager: FileManager
    private let commandRunner: @Sendable ([String]) throws -> LocalControlLaunchAgentCommandResult

    public init(
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        fileManager: FileManager = .default,
        commandRunner: @escaping @Sendable ([String]) throws -> LocalControlLaunchAgentCommandResult = LocalControlLaunchAgentManager.defaultCommandRunner
    ) {
        self.launchAgentsDirectory = launchAgentsDirectory
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func plistURL(label: String = "com.mcphq.control") -> URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    public func renderPlist(_ configuration: LocalControlLaunchAgentConfiguration) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: configuration.plistDictionary,
            format: .xml,
            options: 0
        )
    }

    public func install(_ configuration: LocalControlLaunchAgentConfiguration, dryRun: Bool = false) throws -> LocalControlLaunchAgentInstallResult {
        let plistURL = plistURL(label: configuration.label)
        let data = try renderPlist(configuration)
        let plistText = String(data: data, encoding: .utf8) ?? ""
        if !dryRun {
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: URL(fileURLWithPath: configuration.standardOutPath).deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL, options: [.atomic])
        }

        return LocalControlLaunchAgentInstallResult(
            plistPath: plistURL.path,
            didWrite: !dryRun,
            plistText: plistText,
            bootstrapCommand: "launchctl bootstrap gui/$(id -u) \(shellEscaped(plistURL.path))",
            bootoutCommand: "launchctl bootout gui/$(id -u)/\(configuration.label)"
        )
    }

    public func remove(label: String = "com.mcphq.control", dryRun: Bool = false) throws -> LocalControlLaunchAgentInstallResult {
        let plistURL = plistURL(label: label)
        if !dryRun, fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
        return LocalControlLaunchAgentInstallResult(
            plistPath: plistURL.path,
            didWrite: !dryRun,
            plistText: "",
            bootstrapCommand: "launchctl bootstrap gui/$(id -u) \(shellEscaped(plistURL.path))",
            bootoutCommand: "launchctl bootout gui/$(id -u)/\(label)"
        )
    }

    public func bootstrap(label: String = "com.mcphq.control") throws -> LocalControlLaunchAgentCommandResult {
        try commandRunner([
            "/bin/launchctl",
            "bootstrap",
            launchdDomain,
            plistURL(label: label).path,
        ])
    }

    public func bootout(label: String = "com.mcphq.control") throws -> LocalControlLaunchAgentCommandResult {
        try commandRunner([
            "/bin/launchctl",
            "bootout",
            "\(launchdDomain)/\(label)",
        ])
    }

    public func printStatus(label: String = "com.mcphq.control") throws -> LocalControlLaunchAgentCommandResult {
        try commandRunner([
            "/bin/launchctl",
            "print",
            "\(launchdDomain)/\(label)",
        ])
    }

    public func status(
        label: String = "com.mcphq.control",
        endpointStore: LocalControlEndpointStore = .defaultStore(),
        checkLaunchd: Bool = false
    ) -> LocalControlLaunchAgentStatus {
        let launchdResult = checkLaunchd ? try? printStatus(label: label) : nil
        let launchdMessage = launchdResult.map { result in
            [result.stdout, result.stderr]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        }
        return LocalControlLaunchAgentStatus(
            plistPath: plistURL(label: label).path,
            isInstalled: fileManager.fileExists(atPath: plistURL(label: label).path),
            endpoint: try? endpointStore.load(),
            launchdState: launchdState(for: launchdResult, checked: checkLaunchd),
            launchdMessage: launchdMessage.flatMap { $0.isEmpty ? nil : SecretRedactor.redactText($0) }
        )
    }

    private var launchdDomain: String {
        #if canImport(Darwin)
        return "gui/\(getuid())"
        #else
        return "gui/$(id -u)"
        #endif
    }

    private func launchdState(
        for result: LocalControlLaunchAgentCommandResult?,
        checked: Bool
    ) -> LocalControlLaunchAgentLoadState {
        guard checked else { return .unknown }
        guard let result else { return .unknown }
        return result.exitCode == 0 ? .loaded : .notLoaded
    }

    private func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func defaultCommandRunner(_ command: [String]) throws -> LocalControlLaunchAgentCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return LocalControlLaunchAgentCommandResult(
            command: command,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
