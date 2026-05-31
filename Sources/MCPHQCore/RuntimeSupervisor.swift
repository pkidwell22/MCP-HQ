import Foundation

public enum RuntimeSupervisorError: Error, Equatable, CustomStringConvertible {
    case missingCommand(String)
    case launchFailed(String)
    case nonHubOwnedRuntime(String)
    case runtimeNotManaged(String)
    case runtimeAlreadyRunning(String)
    case missingEnvironmentReference(name: String, referencedBy: String)
    case secretStoreUnavailable(KeychainSecretReference)
    case missingSecret(KeychainSecretReference)
    case secretReadFailed(KeychainSecretReference, String)

    public var description: String {
        switch self {
        case .missingCommand(let command):
            return "Runtime command is not available: \(SecretRedactor.redactText(command))"
        case .launchFailed(let message):
            return "Runtime launch failed: \(SecretRedactor.redactText(message))"
        case .nonHubOwnedRuntime(let id):
            return "Runtime is not hub-owned and cannot be controlled by MCP-HQ: \(SecretRedactor.redactText(id))"
        case .runtimeNotManaged(let id):
            return "Runtime is not managed by this MCP-HQ supervisor: \(SecretRedactor.redactText(id))"
        case .runtimeAlreadyRunning(let id):
            return "Runtime is already running under this MCP-HQ supervisor: \(SecretRedactor.redactText(id))"
        case .missingEnvironmentReference(let name, let referencedBy):
            return "Runtime environment reference \(SecretRedactor.redactText(name)) used by \(SecretRedactor.redactText(referencedBy)) is not set"
        case .secretStoreUnavailable(let reference):
            return "Runtime requires Keychain secret \(reference.configValue), but no secret store is available"
        case .missingSecret(let reference):
            return "Runtime requires missing Keychain secret \(reference.configValue)"
        case .secretReadFailed(let reference, let message):
            return "Runtime could not read Keychain secret \(reference.configValue): \(SecretRedactor.redactText(message))"
        }
    }
}

public struct HubRuntimeLaunchRequest: Equatable, Sendable {
    public let server: ServerDefinition
    public let logDirectory: String
    public let extraEnvironment: [String: String]

    public init(server: ServerDefinition, logDirectory: String, extraEnvironment: [String: String] = [:]) {
        self.server = server
        self.logDirectory = logDirectory
        self.extraEnvironment = extraEnvironment
    }
}

public protocol RuntimeProcessHandle: AnyObject {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    func terminate()
}

extension Process: RuntimeProcessHandle {}

public protocol RuntimeProcessLaunching {
    func launch(
        command: String,
        args: [String],
        environment: [String: String],
        stdoutURL: URL,
        stderrURL: URL
    ) throws -> RuntimeProcessHandle
}

public struct FoundationRuntimeProcessLauncher: RuntimeProcessLaunching {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func launch(
        command: String,
        args: [String],
        environment: [String: String],
        stdoutURL: URL,
        stderrURL: URL
    ) throws -> RuntimeProcessHandle {
        let executablePath = try resolveExecutable(command, environment: environment)
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.environment = environment
        process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
        process.standardError = try FileHandle(forWritingTo: stderrURL)
        do {
            try process.run()
        } catch {
            throw RuntimeSupervisorError.launchFailed(String(describing: error))
        }
        return process
    }

    private func resolveExecutable(_ command: String, environment: [String: String]) throws -> String {
        if command.contains("/") {
            guard fileManager.isExecutableFile(atPath: command) else {
                throw RuntimeSupervisorError.missingCommand(command)
            }
            return command
        }

        let pathValue = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in pathValue.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw RuntimeSupervisorError.missingCommand(command)
    }
}

public final class HubRuntimeSupervisor {
    private let launcher: RuntimeProcessLaunching
    private let fileManager: FileManager
    private let controlPlaneStore: SQLiteScanHistoryStore?
    private let launchEnvironmentResolver: RuntimeLaunchEnvironmentResolver
    private let now: () -> Date
    private var activeHandles: [String: RuntimeProcessHandle] = [:]

    public init(
        launcher: RuntimeProcessLaunching = FoundationRuntimeProcessLauncher(),
        fileManager: FileManager = .default,
        controlPlaneStore: SQLiteScanHistoryStore? = nil,
        secretStore: SecretStore? = MacOSKeychainSecretStore(),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping () -> Date = Date.init
    ) {
        self.launcher = launcher
        self.fileManager = fileManager
        self.controlPlaneStore = controlPlaneStore
        self.launchEnvironmentResolver = RuntimeLaunchEnvironmentResolver(
            secretStore: secretStore,
            processEnvironment: processEnvironment
        )
        self.now = now
    }

    public func start(request: HubRuntimeLaunchRequest) throws -> RuntimeInstance {
        guard let command = request.server.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeSupervisorError.missingCommand(request.server.displayName)
        }

        let runtimeID = Self.runtimeID(for: request.server)
        if let handle = activeHandles[runtimeID], handle.isRunning {
            throw RuntimeSupervisorError.runtimeAlreadyRunning(runtimeID)
        }

        let logDirectory = URL(fileURLWithPath: request.logDirectory, isDirectory: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logPrefix = Self.safeFileComponent(request.server.displayName)
        let timestamp = Self.timestampFormatter.string(from: now())
        let stdoutURL = logDirectory.appendingPathComponent("\(logPrefix)-\(timestamp).stdout.log")
        let stderrURL = logDirectory.appendingPathComponent("\(logPrefix)-\(timestamp).stderr.log")
        let environment = try launchEnvironmentResolver.environment(server: request.server, extraEnvironment: request.extraEnvironment)
        let handle = try launcher.launch(
            command: command,
            args: request.server.args,
            environment: environment,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL
        )
        activeHandles[runtimeID] = handle

        let instance = RuntimeInstance(
            id: runtimeID,
            serverID: request.server.id,
            pid: handle.processIdentifier,
            ownership: .hubOwned,
            commandLine: ([command] + request.server.args).joined(separator: " "),
            startedAt: now(),
            status: .healthy,
            logPath: stdoutURL.path
        )
        do {
            try controlPlaneStore?.upsertRuntimeInstance(instance, updatedAt: now())
        } catch {
            activeHandles.removeValue(forKey: runtimeID)
            if handle.isRunning {
                handle.terminate()
            }
            throw RuntimeSupervisorError.launchFailed("Runtime started but persistence failed: \(error)")
        }
        return instance
    }

    public func stop(instance: RuntimeInstance) throws -> RuntimeInstance {
        guard instance.ownership == .hubOwned else {
            throw RuntimeSupervisorError.nonHubOwnedRuntime(instance.id)
        }
        guard let handle = activeHandles[instance.id] else {
            throw RuntimeSupervisorError.runtimeNotManaged(instance.id)
        }
        if handle.isRunning {
            handle.terminate()
        }
        activeHandles.removeValue(forKey: instance.id)
        let stopped = RuntimeInstance(
            id: instance.id,
            serverID: instance.serverID,
            pid: nil,
            ownership: .hubOwned,
            commandLine: instance.commandLine,
            startedAt: instance.startedAt,
            status: .stopped,
            logPath: instance.logPath
        )
        try controlPlaneStore?.upsertRuntimeInstance(stopped, updatedAt: now())
        return stopped
    }

    public func restart(instance: RuntimeInstance, request: HubRuntimeLaunchRequest) throws -> RuntimeInstance {
        _ = try stop(instance: instance)
        return try start(request: request)
    }

    private static func runtimeID(for server: ServerDefinition) -> String {
        "hub:\(server.id)"
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "runtime" : component
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()
}

public struct RuntimeLaunchEnvironmentResolver: Sendable {
    private let secretStore: SecretStore?
    private let processEnvironment: [String: String]

    public init(
        secretStore: SecretStore? = MacOSKeychainSecretStore(),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.secretStore = secretStore
        self.processEnvironment = processEnvironment
    }

    public func environment(server: ServerDefinition, extraEnvironment: [String: String] = [:]) throws -> [String: String] {
        var environment = processEnvironment
        for key in server.envBindings.keys.sorted() {
            guard let value = server.envBindings[key] else { continue }
            environment[key] = try resolvedValue(value, referencedBy: key)
        }
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        return environment
    }

    private func resolvedValue(_ value: String, referencedBy: String) throws -> String {
        if let reference = KeychainSecretReference.parse(from: value) {
            let secret = try readSecret(reference)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("bearer keychain://") {
                return "Bearer \(secret)"
            }
            return secret
        }

        if let exactName = exactEnvironmentReferenceName(value) {
            guard let resolved = processEnvironment[exactName] else {
                throw RuntimeSupervisorError.missingEnvironmentReference(name: exactName, referencedBy: referencedBy)
            }
            return resolved
        }

        return try interpolatingEnvironmentReferences(in: value, referencedBy: referencedBy)
    }

    private func readSecret(_ reference: KeychainSecretReference) throws -> String {
        guard let secretStore else {
            throw RuntimeSupervisorError.secretStoreUnavailable(reference)
        }
        do {
            guard let value = try secretStore.readSecret(for: reference) else {
                throw RuntimeSupervisorError.missingSecret(reference)
            }
            return value
        } catch let error as RuntimeSupervisorError {
            throw error
        } catch {
            throw RuntimeSupervisorError.secretReadFailed(reference, String(describing: error))
        }
    }

    private func exactEnvironmentReferenceName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            let name = String(trimmed.dropFirst(2).dropLast())
            return isValidEnvironmentName(name) ? name : nil
        }
        if trimmed.hasPrefix("$"), !trimmed.contains("{") {
            let name = String(trimmed.dropFirst())
            return isValidEnvironmentName(name) ? name : nil
        }
        return nil
    }

    private func interpolatingEnvironmentReferences(in value: String, referencedBy: String) throws -> String {
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else { return value }

        var result = value
        for match in matches.reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let name = nsValue.substring(with: match.range(at: 1))
            guard let resolved = processEnvironment[name] else {
                throw RuntimeSupervisorError.missingEnvironmentReference(name: name, referencedBy: referencedBy)
            }
            let range = Range(match.range(at: 0), in: result)!
            result.replaceSubrange(range, with: resolved)
        }
        return result
    }

    private func isValidEnvironmentName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}
