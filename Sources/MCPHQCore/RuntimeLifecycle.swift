import Foundation

public enum RuntimeLifecycleAction: String, Codable, CaseIterable, Equatable, Sendable {
    case start
    case stop
    case restart

    public var displayLabel: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Restart"
        }
    }
}

public struct RuntimeLifecycleCapability: Codable, Equatable, Sendable, Identifiable {
    public var id: String { action.rawValue }
    public let action: RuntimeLifecycleAction
    public let isAvailable: Bool
    public let reason: String

    public init(action: RuntimeLifecycleAction, isAvailable: Bool, reason: String) {
        self.action = action
        self.isAvailable = isAvailable
        self.reason = SecretRedactor.redactText(reason)
    }
}

public struct RuntimeLifecycleExplanation: Codable, Equatable, Sendable, Identifiable {
    public var id: String { runtimeInstanceID }
    public let runtimeInstanceID: String
    public let serverID: String?
    public let pid: Int32?
    public let ownership: RuntimeOwnership
    public let status: RuntimeInstanceStatus
    public let controlSummary: String
    public let logSummary: String
    public let logFilePath: String?
    public let capabilities: [RuntimeLifecycleCapability]

    public init(
        runtimeInstanceID: String,
        serverID: String?,
        pid: Int32?,
        ownership: RuntimeOwnership,
        status: RuntimeInstanceStatus,
        controlSummary: String,
        logSummary: String,
        logFilePath: String? = nil,
        capabilities: [RuntimeLifecycleCapability]
    ) {
        self.runtimeInstanceID = runtimeInstanceID
        self.serverID = serverID
        self.pid = pid
        self.ownership = ownership
        self.status = status
        self.controlSummary = SecretRedactor.redactText(controlSummary)
        self.logSummary = SecretRedactor.redactText(logSummary)
        self.logFilePath = logFilePath.map(SecretRedactor.redactText)
        self.capabilities = capabilities
    }
}

public struct RuntimeLifecycleExplainer: Sendable {
    public init() {}

    public func explain(instance: RuntimeInstance) -> RuntimeLifecycleExplanation {
        RuntimeLifecycleExplanation(
            runtimeInstanceID: instance.id,
            serverID: instance.serverID,
            pid: instance.pid,
            ownership: instance.ownership,
            status: instance.status,
            controlSummary: controlSummary(for: instance),
            logSummary: logSummary(for: instance),
            logFilePath: instance.logPath,
            capabilities: RuntimeLifecycleAction.allCases.map { capability(for: $0, instance: instance) }
        )
    }

    public func explain(scanResult: ScanResult) -> [RuntimeLifecycleExplanation] {
        RuntimeLifecycleRuntimeReconciler()
            .instances(scanResult: scanResult, knownHubRuntimes: [])
            .map { explain(instance: $0) }
    }

    public func explain(scanResult: ScanResult, knownHubRuntimes: [RuntimeInstance]) -> [RuntimeLifecycleExplanation] {
        explain(scanResult: scanResult, knownHubRuntimes: knownHubRuntimes, logDirectory: nil)
    }

    public func explain(scanResult: ScanResult, knownHubRuntimes: [RuntimeInstance], logDirectory: String?) -> [RuntimeLifecycleExplanation] {
        let enrichedHubRuntimes = RuntimeLifecycleLogPathResolver()
            .enrich(instances: knownHubRuntimes, scanResult: scanResult, logDirectory: logDirectory)
        return RuntimeLifecycleRuntimeReconciler()
            .instances(scanResult: scanResult, knownHubRuntimes: enrichedHubRuntimes)
            .map { explain(instance: $0) }
    }

    private func capability(for action: RuntimeLifecycleAction, instance: RuntimeInstance) -> RuntimeLifecycleCapability {
        switch instance.ownership {
        case .agentOwned:
            return RuntimeLifecycleCapability(
                action: action,
                isAvailable: false,
                reason: "Process is owned by its agent; MCP-HQ is observing it only. Use the owning agent to \(action.rawValue) it."
            )
        case .unknown:
            return RuntimeLifecycleCapability(
                action: action,
                isAvailable: false,
                reason: "Process ownership is unknown; MCP-HQ will not \(action.rawValue) it."
            )
        case .hubOwned:
            return hubOwnedCapability(for: action, instance: instance)
        }
    }

    private func hubOwnedCapability(for action: RuntimeLifecycleAction, instance: RuntimeInstance) -> RuntimeLifecycleCapability {
        let isStale = instance.status == .degraded && instance.pid == nil
        switch action {
        case .start:
            if isStale {
                return RuntimeLifecycleCapability(action: .start, isAvailable: true, reason: "Stale hub-owned runtime record has no observed PID; starting launches a fresh helper-owned process.")
            }
            if instance.status == .stopped || instance.pid == nil {
                return RuntimeLifecycleCapability(action: .start, isAvailable: true, reason: "Hub-owned runtime is stopped and can be started by MCP-HQ.")
            }
            return RuntimeLifecycleCapability(action: .start, isAvailable: false, reason: "Hub-owned runtime already has an active process; use restart instead.")
        case .stop:
            if isStale {
                return RuntimeLifecycleCapability(action: .stop, isAvailable: false, reason: "Stale hub-owned runtime has no observed PID; MCP-HQ will not stop an unknown process.")
            }
            if instance.pid != nil, instance.status != .stopped, instance.status != .stopping {
                return RuntimeLifecycleCapability(action: .stop, isAvailable: true, reason: "Hub-owned runtime can be stopped by MCP-HQ.")
            }
            return RuntimeLifecycleCapability(action: .stop, isAvailable: false, reason: "Hub-owned runtime is not currently running.")
        case .restart:
            if isStale {
                return RuntimeLifecycleCapability(action: .restart, isAvailable: false, reason: "Stale hub-owned runtime has no observed PID; start a fresh helper-owned process instead of restarting.")
            }
            if instance.pid != nil, instance.status != .stopped, instance.status != .stopping {
                return RuntimeLifecycleCapability(action: .restart, isAvailable: true, reason: "Hub-owned runtime can be restarted by MCP-HQ.")
            }
            return RuntimeLifecycleCapability(action: .restart, isAvailable: false, reason: "Hub-owned runtime must be running before restart is available.")
        }
    }

    private func controlSummary(for instance: RuntimeInstance) -> String {
        if instance.ownership == .hubOwned, instance.status == .degraded, instance.pid == nil {
            let detail = instance.lastError.map { " \($0)" } ?? ""
            return "Stale hub-owned runtime record: the helper previously recorded this runtime, but no matching PID is visible now. Stop and restart are disabled to avoid controlling an unknown process.\(detail)"
        }
        if let lastError = instance.lastError, instance.status == .error || instance.status == .degraded {
            return "Runtime status is \(instance.status.rawValue): \(lastError)"
        }

        switch instance.ownership {
        case .hubOwned:
            return "Hub-owned runtime: MCP-HQ may start, stop, or restart it when the action is available."
        case .agentOwned:
            return "Read-only external runtime: owned by an agent; MCP-HQ will not start, stop, or restart it."
        case .unknown:
            return "Read-only observed runtime: ownership is unknown, so lifecycle controls are disabled."
        }
    }

    private func logSummary(for instance: RuntimeInstance) -> String {
        if let logPath = instance.logPath, !logPath.isEmpty {
            return "Log tail available: \(SecretRedactor.redactText(logPath))"
        }

        switch instance.ownership {
        case .hubOwned:
            return "No hub-owned log path has been recorded yet."
        case .agentOwned:
            return "No MCP-HQ log capture for this external process; check the owning agent's logs."
        case .unknown:
            return "No MCP-HQ log capture for this observed process."
        }
    }
}

public struct RuntimeLifecycleLogPathResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let maxDirectoryEntries: Int

    public init(fileManager: FileManager = .default, maxDirectoryEntries: Int = 200) {
        self.fileManager = fileManager
        self.maxDirectoryEntries = max(1, min(maxDirectoryEntries, 1_000))
    }

    public func enrich(instances: [RuntimeInstance], scanResult: ScanResult, logDirectory: String?) -> [RuntimeInstance] {
        let serverNamesByID = scanResult.servers.reduce(into: [String: Set<String>]()) { lookup, server in
            var names = lookup[server.id] ?? []
            names.insert(server.id)
            names.insert(server.displayName)
            lookup[server.id] = names
        }
        return instances.map { instance in
            guard instance.ownership == .hubOwned, missingLogPath(instance.logPath) else { return instance }
            guard let resolvedPath = resolveLogPath(
                for: instance,
                serverNamesByID: serverNamesByID,
                logDirectory: logDirectory
            ) else { return instance }
            return RuntimeInstance(
                id: instance.id,
                serverID: instance.serverID,
                pid: instance.pid,
                ownership: instance.ownership,
                commandLine: instance.commandLine,
                startedAt: instance.startedAt,
                cpuPercent: instance.cpuPercent,
                memoryBytes: instance.memoryBytes,
                status: instance.status,
                lastError: instance.lastError,
                logPath: resolvedPath
            )
        }
    }

    public func resolveLogPath(for instance: RuntimeInstance, scanResult: ScanResult, logDirectory: String?) -> String? {
        let serverNamesByID = scanResult.servers.reduce(into: [String: Set<String>]()) { lookup, server in
            var names = lookup[server.id] ?? []
            names.insert(server.id)
            names.insert(server.displayName)
            lookup[server.id] = names
        }
        return resolveLogPath(for: instance, serverNamesByID: serverNamesByID, logDirectory: logDirectory)
    }

    private func resolveLogPath(
        for instance: RuntimeInstance,
        serverNamesByID: [String: Set<String>],
        logDirectory: String?
    ) -> String? {
        guard instance.ownership == .hubOwned else { return nil }
        guard let directory = logDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !directory.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }

        let names = knownNames(for: instance, serverNamesByID: serverNamesByID)
        let prefixes = Set(names.map(Self.safeFileComponent).filter { !$0.isEmpty })
        guard !prefixes.isEmpty else { return nil }

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return entries
            .prefix(maxDirectoryEntries)
            .compactMap { candidate(url: $0, prefixes: prefixes) }
            .sorted(by: candidateSort)
            .last?
            .url.path
    }

    private func knownNames(for instance: RuntimeInstance, serverNamesByID: [String: Set<String>]) -> Set<String> {
        var names = Set<String>()
        if let serverID = instance.serverID, !serverID.isEmpty {
            names.insert(serverID)
            names.formUnion(serverNamesByID[serverID] ?? [])
        }
        if instance.id.hasPrefix("hub:") {
            let suffix = String(instance.id.dropFirst("hub:".count))
            if !suffix.isEmpty {
                names.insert(suffix)
                names.formUnion(serverNamesByID[suffix] ?? [])
            }
        }
        return names
    }

    private func candidate(url: URL, prefixes: Set<String>) -> LogPathCandidate? {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else { return nil }
        let fileName = url.lastPathComponent
        for prefix in prefixes {
            guard fileName.hasPrefix("\(prefix)-") else { continue }
            let suffix = String(fileName.dropFirst(prefix.count + 1))
            let parts = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts[2] == "log" else { continue }
            guard parts[0].count == 14, parts[0].allSatisfy(\.isNumber) else { continue }
            guard let stream = RuntimeLogStream(rawValue: parts[1]), stream == .stdout || stream == .stderr else { continue }
            return LogPathCandidate(url: url, timestamp: parts[0], stream: stream)
        }
        return nil
    }

    private func candidateSort(lhs: LogPathCandidate, rhs: LogPathCandidate) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return streamRank(lhs.stream) < streamRank(rhs.stream)
    }

    private func streamRank(_ stream: RuntimeLogStream) -> Int {
        switch stream {
        case .stderr: return 0
        case .stdout: return 1
        case .supervisor: return 2
        }
    }

    private func missingLogPath(_ path: String?) -> Bool {
        path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "runtime" : component
    }

    private struct LogPathCandidate {
        let url: URL
        let timestamp: String
        let stream: RuntimeLogStream
    }
}

public struct RuntimeLifecycleRuntimeReconciler: Sendable {
    public init() {}

    public func instances(scanResult: ScanResult, knownHubRuntimes: [RuntimeInstance]) -> [RuntimeInstance] {
        let knownHubRuntimes = knownHubRuntimes.filter { $0.ownership == .hubOwned }
        let hubByPID = knownHubRuntimeLookupByPID(knownHubRuntimes)
        let ownershipByPID = ownershipLookup(from: scanResult.processMatches)
        let serverByPID = serverLookup(from: scanResult.processMatches)
        var emittedHubRuntimeIDs = Set<String>()

        let observedInstances = scanResult.processes
            .sorted { $0.pid < $1.pid }
            .map { process -> RuntimeInstance in
                if let hubRuntime = hubByPID[process.pid] {
                    emittedHubRuntimeIDs.insert(hubRuntime.id)
                    return RuntimeInstance(
                        id: hubRuntime.id,
                        serverID: hubRuntime.serverID ?? serverByPID[process.pid],
                        pid: process.pid,
                        ownership: .hubOwned,
                        commandLine: process.commandLine.isEmpty ? hubRuntime.commandLine : process.commandLine,
                        startedAt: hubRuntime.startedAt,
                        cpuPercent: process.cpuPercent ?? hubRuntime.cpuPercent,
                        memoryBytes: process.memoryBytes ?? hubRuntime.memoryBytes,
                        status: observedStatus(for: hubRuntime),
                        lastError: hubRuntime.status == .error ? hubRuntime.lastError : nil,
                        logPath: hubRuntime.logPath
                    )
                }

                return RuntimeInstance(
                    id: "pid:\(process.pid)",
                    serverID: serverByPID[process.pid],
                    pid: process.pid,
                    ownership: ownershipByPID[process.pid] ?? .unknown,
                    commandLine: process.commandLine,
                    cpuPercent: process.cpuPercent,
                    memoryBytes: process.memoryBytes,
                    status: .observed
                )
            }

        let observedPIDs = Set(scanResult.processes.map(\.pid))
        let remainingHubRuntimes = knownHubRuntimes
            .filter { !emittedHubRuntimeIDs.contains($0.id) }
            .map { reconcileStoredHubRuntime($0, observedPIDs: observedPIDs) }

        return observedInstances + remainingHubRuntimes
    }

    private func knownHubRuntimeLookupByPID(_ runtimes: [RuntimeInstance]) -> [Int32: RuntimeInstance] {
        runtimes.reduce(into: [:]) { lookup, runtime in
            guard let pid = runtime.pid, lookup[pid] == nil else { return }
            lookup[pid] = runtime
        }
    }

    private func observedStatus(for hubRuntime: RuntimeInstance) -> RuntimeInstanceStatus {
        switch hubRuntime.status {
        case .stopped, .stopping, .degraded:
            return .healthy
        default:
            return hubRuntime.status
        }
    }

    private func reconcileStoredHubRuntime(_ instance: RuntimeInstance, observedPIDs: Set<Int32>) -> RuntimeInstance {
        guard instance.status != .stopped, let pid = instance.pid, !observedPIDs.contains(pid) else {
            return instance
        }
        return RuntimeInstance(
            id: instance.id,
            serverID: instance.serverID,
            pid: nil,
            ownership: .hubOwned,
            commandLine: instance.commandLine,
            startedAt: instance.startedAt,
            cpuPercent: instance.cpuPercent,
            memoryBytes: instance.memoryBytes,
            status: .degraded,
            lastError: "Persisted hub-owned runtime was not found in the latest process scan. Start it again through the helper before using stop or restart.",
            logPath: instance.logPath
        )
    }

    private func ownershipLookup(from matches: [ServerProcessMatch]) -> [Int32: RuntimeOwnership] {
        matches.reduce(into: [:]) { lookup, match in
            let existing = lookup[match.processID] ?? .unknown
            lookup[match.processID] = strongestOwnership(existing, match.ownership)
        }
    }

    private func serverLookup(from matches: [ServerProcessMatch]) -> [Int32: String] {
        matches.reduce(into: [:]) { lookup, match in
            if lookup[match.processID] == nil {
                lookup[match.processID] = match.serverID
            }
        }
    }

    private func strongestOwnership(_ lhs: RuntimeOwnership, _ rhs: RuntimeOwnership) -> RuntimeOwnership {
        if lhs == .hubOwned || rhs == .hubOwned { return .hubOwned }
        if lhs == .agentOwned || rhs == .agentOwned { return .agentOwned }
        return .unknown
    }
}

public enum RuntimeLifecycleControlPlaneState: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct RuntimeLifecycleControlPlaneAvailability: Codable, Equatable, Sendable {
    public let state: RuntimeLifecycleControlPlaneState
    public let message: String

    public init(state: RuntimeLifecycleControlPlaneState, message: String) {
        self.state = state
        self.message = SecretRedactor.redactText(message)
    }

    public init(endpointAvailability: LocalControlEndpointAvailability) {
        switch endpointAvailability.state {
        case .available:
            self.init(state: .available, message: "Helper available: \(endpointAvailability.message)")
        case .unavailable:
            self.init(state: .unavailable, message: "Helper unavailable: \(endpointAvailability.message)")
        case .unknown:
            self.init(state: .unknown, message: "Helper availability unknown: \(endpointAvailability.message)")
        }
    }

    public static let assumedAvailable = RuntimeLifecycleControlPlaneAvailability(
        state: .available,
        message: "Helper control paths available."
    )

    public var allowsControlActions: Bool { state == .available }
}

public enum RuntimeLifecycleSafeActionKind: String, Codable, Equatable, Sendable {
    case copyRuntimeID
    case copyLogTailCommand
}

public struct RuntimeLifecycleSafeAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: RuntimeLifecycleSafeActionKind
    public let title: String
    public let detail: String
    public let textToCopy: String

    public init(kind: RuntimeLifecycleSafeActionKind, title: String, detail: String, textToCopy: String) {
        self.kind = kind
        self.id = kind.rawValue
        self.title = title
        self.detail = SecretRedactor.redactText(detail)
        self.textToCopy = SecretRedactor.redactText(textToCopy)
    }
}

public struct RuntimeLifecyclePanelLogView: Codable, Equatable, Sendable {
    public let isLoadable: Bool
    public let message: String
    public let displayPath: String?
    public let filePath: String?
    public let defaultLineLimit: Int

    public init(
        isLoadable: Bool,
        message: String,
        displayPath: String? = nil,
        filePath: String? = nil,
        defaultLineLimit: Int = 100
    ) {
        self.isLoadable = isLoadable
        self.message = SecretRedactor.redactText(message)
        self.displayPath = displayPath.map(SecretRedactor.redactText)
        self.filePath = filePath.map(SecretRedactor.redactText)
        self.defaultLineLimit = defaultLineLimit
    }
}

public struct RuntimeLifecyclePanelRow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let runtimeInstanceID: String
    public let serverID: String?
    public let title: String
    public let subtitle: String
    public let pidText: String
    public let serverText: String
    public let ownershipLabel: String
    public let statusLabel: String
    public let controlExplanation: String
    public let controlAvailabilityText: String
    public let logHint: String
    public let logView: RuntimeLifecyclePanelLogView
    public let capabilitySummaries: [String]
    public let availableControlActions: [RuntimeLifecycleAction]
    public let safeActions: [RuntimeLifecycleSafeAction]

    public init(
        runtimeInstanceID: String,
        serverID: String? = nil,
        title: String,
        subtitle: String,
        pidText: String,
        serverText: String,
        ownershipLabel: String,
        statusLabel: String,
        controlExplanation: String,
        controlAvailabilityText: String,
        logHint: String,
        logView: RuntimeLifecyclePanelLogView,
        capabilitySummaries: [String],
        availableControlActions: [RuntimeLifecycleAction] = [],
        safeActions: [RuntimeLifecycleSafeAction]
    ) {
        self.id = runtimeInstanceID
        self.runtimeInstanceID = runtimeInstanceID
        self.serverID = serverID.map(SecretRedactor.redactText)
        self.title = SecretRedactor.redactText(title)
        self.subtitle = SecretRedactor.redactText(subtitle)
        self.pidText = pidText
        self.serverText = SecretRedactor.redactText(serverText)
        self.ownershipLabel = ownershipLabel
        self.statusLabel = statusLabel
        self.controlExplanation = SecretRedactor.redactText(controlExplanation)
        self.controlAvailabilityText = SecretRedactor.redactText(controlAvailabilityText)
        self.logHint = SecretRedactor.redactText(logHint)
        self.logView = logView
        self.capabilitySummaries = capabilitySummaries.map(SecretRedactor.redactText)
        self.availableControlActions = availableControlActions
        self.safeActions = safeActions
    }
}

public struct RuntimeLifecyclePanelState: Codable, Equatable, Sendable {
    public let summaryText: String
    public let controlPlaneText: String
    public let controlPlaneAllowsActions: Bool
    public let rows: [RuntimeLifecyclePanelRow]
    public let footerText: String

    public init(
        summaryText: String,
        controlPlaneText: String = RuntimeLifecycleControlPlaneAvailability.assumedAvailable.message,
        controlPlaneAllowsActions: Bool = true,
        rows: [RuntimeLifecyclePanelRow],
        footerText: String
    ) {
        self.summaryText = SecretRedactor.redactText(summaryText)
        self.controlPlaneText = SecretRedactor.redactText(controlPlaneText)
        self.controlPlaneAllowsActions = controlPlaneAllowsActions
        self.rows = rows
        self.footerText = SecretRedactor.redactText(footerText)
    }
}

public struct RuntimeLifecyclePanelStateBuilder: Sendable {
    private let controlPlaneAvailability: RuntimeLifecycleControlPlaneAvailability

    public init(controlPlaneAvailability: RuntimeLifecycleControlPlaneAvailability = .assumedAvailable) {
        self.controlPlaneAvailability = controlPlaneAvailability
    }

    public func build(from scanResult: ScanResult) -> RuntimeLifecyclePanelState {
        build(from: RuntimeLifecycleExplainer().explain(scanResult: scanResult))
    }

    public func build(from instances: [RuntimeInstance]) -> RuntimeLifecyclePanelState {
        let explainer = RuntimeLifecycleExplainer()
        return build(from: instances.map { explainer.explain(instance: $0) })
    }

    public func build(from explanations: [RuntimeLifecycleExplanation]) -> RuntimeLifecyclePanelState {
        let sorted = explanations.sorted { lhs, rhs in
            switch (lhs.pid, rhs.pid) {
            case let (left?, right?): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.runtimeInstanceID.localizedCaseInsensitiveCompare(rhs.runtimeInstanceID) == .orderedAscending
            }
        }
        let rows = sorted.map(makeRow)
        let agentOwned = rows.filter { $0.ownershipLabel == RuntimeOwnership.agentOwned.displayLabel }.count
        let hubOwned = rows.filter { $0.ownershipLabel == RuntimeOwnership.hubOwned.displayLabel }.count
        let unknown = rows.filter { $0.ownershipLabel == RuntimeOwnership.unknown.displayLabel }.count
        let summary = rows.isEmpty
            ? "No MCP-like runtime processes found."
            : "\(rows.count) runtime\(rows.count == 1 ? "" : "s") - \(agentOwned) agent-owned - \(hubOwned) hub-owned - \(unknown) unknown"
        return RuntimeLifecyclePanelState(
            summaryText: summary,
            controlPlaneText: controlPlaneAvailability.message,
            controlPlaneAllowsActions: controlPlaneAvailability.allowsControlActions,
            rows: rows,
            footerText: "Lifecycle controls are available only for hub-owned runtimes through the supervised helper. MCP-HQ does not kill externally owned or unknown processes from the UI."
        )
    }

    private func makeRow(from explanation: RuntimeLifecycleExplanation) -> RuntimeLifecyclePanelRow {
        let pidText = explanation.pid.map { "pid \($0)" } ?? "no pid"
        let serverText = explanation.serverID.map { "server \($0)" } ?? "no matched server"
        let title = explanation.serverID ?? explanation.runtimeInstanceID
        let subtitle = [pidText, explanation.ownership.displayLabel, explanation.status.rawValue].joined(separator: " - ")
        let capabilitySummaries = explanation.capabilities.map { capability in
            let availability = capability.isAvailable ? "available" : "disabled"
            return "\(capability.action.displayLabel): \(availability) - \(capability.reason)"
        }
        let modelAvailableControls = explanation.capabilities.filter(\.isAvailable)
        let availableControls = controlPlaneAvailability.allowsControlActions ? modelAvailableControls.map { $0.action.displayLabel } : []
        let controlAvailabilityText: String
        if modelAvailableControls.isEmpty {
            controlAvailabilityText = "No lifecycle controls are available for this runtime."
        } else if controlPlaneAvailability.allowsControlActions {
            controlAvailabilityText = "\(availableControls.joined(separator: ", ")) available through supervised helper control paths."
        } else {
            controlAvailabilityText = "Lifecycle controls are disabled because \(controlPlaneAvailability.message)"
        }

        return RuntimeLifecyclePanelRow(
            runtimeInstanceID: explanation.runtimeInstanceID,
            serverID: explanation.serverID,
            title: title,
            subtitle: subtitle,
            pidText: pidText,
            serverText: serverText,
            ownershipLabel: explanation.ownership.displayLabel,
            statusLabel: explanation.status.rawValue,
            controlExplanation: explanation.controlSummary,
            controlAvailabilityText: controlAvailabilityText,
            logHint: explanation.logSummary,
            logView: logView(for: explanation),
            capabilitySummaries: capabilitySummaries,
            availableControlActions: controlPlaneAvailability.allowsControlActions ? modelAvailableControls.map(\.action) : [],
            safeActions: safeActions(for: explanation)
        )
    }

    private func logView(for explanation: RuntimeLifecycleExplanation) -> RuntimeLifecyclePanelLogView {
        if let logFilePath = explanation.logFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !logFilePath.isEmpty {
            return RuntimeLifecyclePanelLogView(
                isLoadable: true,
                message: "Load a bounded, redacted tail from this known log path. This is read-only and does not control the runtime process.",
                displayPath: logFilePath,
                filePath: logFilePath
            )
        }
        return RuntimeLifecyclePanelLogView(isLoadable: false, message: explanation.logSummary)
    }

    private func safeActions(for explanation: RuntimeLifecycleExplanation) -> [RuntimeLifecycleSafeAction] {
        var actions = [RuntimeLifecycleSafeAction(
            kind: .copyRuntimeID,
            title: "Copy runtime ID",
            detail: "Copy this runtime identifier for CLI/API diagnostics.",
            textToCopy: explanation.runtimeInstanceID
        )]
        if let logFilePath = explanation.logFilePath, !logFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let command = "mcphq logs --file \(shellQuoted(logFilePath)) --runtime-id \(shellQuoted(explanation.runtimeInstanceID)) --lines 100"
            actions.append(RuntimeLifecycleSafeAction(
                kind: .copyLogTailCommand,
                title: "Copy log tail command",
                detail: "Copy a read-only redacted log-tail command for this runtime.",
                textToCopy: command
            ))
        }
        return actions
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct RuntimeLaunchCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let displayName: String
    public let agentName: String
    public let sourcePath: String
    public let transport: MCPTransport
    public let commandSummary: String
    public let isStartable: Bool
    public let disabledReason: String?

    public init(
        serverID: String,
        displayName: String,
        agentName: String,
        sourcePath: String,
        transport: MCPTransport,
        commandSummary: String,
        isStartable: Bool,
        disabledReason: String? = nil
    ) {
        self.id = serverID
        self.serverID = serverID
        self.displayName = SecretRedactor.redactText(displayName)
        self.agentName = agentName
        self.sourcePath = SecretRedactor.redactText(sourcePath)
        self.transport = transport
        self.commandSummary = SecretRedactor.redactText(commandSummary)
        self.isStartable = isStartable
        self.disabledReason = disabledReason.map(SecretRedactor.redactText)
    }
}

public struct RuntimeLaunchCandidateBuilder: Sendable {
    public init() {}

    public func build(from result: ScanResult) -> [RuntimeLaunchCandidate] {
        let sourceLookup = Dictionary(uniqueKeysWithValues: result.sources.map { ($0.path, $0.agent) })
        let healthLookup = Dictionary(uniqueKeysWithValues: result.sourceHealth.map { ($0.source.path, $0.source.agent) })
        return result.servers
            .map { server in
                let agent = sourceLookup[server.sourcePath] ?? healthLookup[server.sourcePath] ?? .unknown
                let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isStdio = server.transport == .stdio
                let hasCommand = command?.isEmpty == false
                let disabledReason: String?
                if !isStdio {
                    disabledReason = "Only stdio MCP servers can be launched by the hub-owned supervisor right now."
                } else if !hasCommand {
                    disabledReason = "This server has no command to launch."
                } else {
                    disabledReason = nil
                }
                let redactedCommand = command.map(SecretRedactor.redactText) ?? ""
                let redactedArgs = SecretRedactor.redactCommandArguments(server.args)
                return RuntimeLaunchCandidate(
                    serverID: server.id,
                    displayName: server.displayName,
                    agentName: AgentRegistry.displayName(for: agent),
                    sourcePath: server.sourcePath,
                    transport: server.transport,
                    commandSummary: ([redactedCommand] + redactedArgs).filter { !$0.isEmpty }.joined(separator: " "),
                    isStartable: disabledReason == nil,
                    disabledReason: disabledReason
                )
            }
            .sorted { lhs, rhs in
                if lhs.isStartable != rhs.isStartable { return lhs.isStartable && !rhs.isStartable }
                let agentCompare = lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName)
                if agentCompare != .orderedSame { return agentCompare == .orderedAscending }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
}

public struct RuntimeLifecyclePanelFormatter: Sendable {
    public init() {}

    public func formatText(_ state: RuntimeLifecyclePanelState) -> String {
        var lines = ["MCP-HQ runtime lifecycle", state.summaryText, state.controlPlaneText, ""]
        if state.rows.isEmpty {
            lines.append(state.footerText)
            return lines.joined(separator: "\n") + "\n"
        }
        for row in state.rows {
            lines.append(row.title)
            lines.append("  \(row.subtitle)")
            lines.append("  \(row.serverText)")
            lines.append("  Control: \(row.controlExplanation)")
            lines.append("  Availability: \(row.controlAvailabilityText)")
            lines.append("  Logs: \(row.logHint)")
            for action in row.safeActions {
                lines.append("  Safe action: \(action.title) - \(action.textToCopy)")
            }
            lines.append("")
        }
        lines.append(state.footerText)
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum RuntimeLifecyclePanelLogLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    case unavailable(String)

    public var description: String {
        switch self {
        case .unavailable(let reason):
            return SecretRedactor.redactText(reason)
        }
    }
}

public struct RuntimeLifecyclePanelLogResult: Codable, Equatable, Sendable {
    public let runtimeInstanceID: String
    public let displayPath: String
    public let entries: [RuntimeLogEntry]
    public let truncated: Bool
    public let summaryText: String

    public init(runtimeInstanceID: String, displayPath: String, entries: [RuntimeLogEntry], truncated: Bool, summaryText: String) {
        self.runtimeInstanceID = runtimeInstanceID
        self.displayPath = SecretRedactor.redactText(displayPath)
        self.entries = entries
        self.truncated = truncated
        self.summaryText = SecretRedactor.redactText(summaryText)
    }
}

public struct RuntimeLifecyclePanelLogLoader: Sendable {
    private let tailer: RuntimeLogTailer

    public init(tailer: RuntimeLogTailer = RuntimeLogTailer()) {
        self.tailer = tailer
    }

    public func load(row: RuntimeLifecyclePanelRow, lineLimit: Int = 100) throws -> RuntimeLifecyclePanelLogResult {
        guard row.logView.isLoadable, let filePath = row.logView.filePath, !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeLifecyclePanelLogLoadError.unavailable(row.logView.message)
        }
        let request = RuntimeLogTailRequest(runtimeInstanceID: row.runtimeInstanceID, filePath: filePath, lineLimit: lineLimit)
        let result = try tailer.tail(request: request)
        let displayPath = row.logView.displayPath ?? result.filePath
        let truncatedSuffix = result.truncated ? " (truncated)" : ""
        return RuntimeLifecyclePanelLogResult(
            runtimeInstanceID: result.runtimeInstanceID,
            displayPath: displayPath,
            entries: result.entries,
            truncated: result.truncated,
            summaryText: "Loaded last \(lineLimit) lines from \(displayPath)\(truncatedSuffix)."
        )
    }
}

public struct RuntimeLogTailRequest: Codable, Equatable, Sendable {
    public let runtimeInstanceID: String
    public let filePath: String
    public let lineLimit: Int
    public let stream: RuntimeLogStream

    public init(runtimeInstanceID: String, filePath: String, lineLimit: Int = 100, stream: RuntimeLogStream = .supervisor) {
        self.runtimeInstanceID = runtimeInstanceID
        self.filePath = filePath
        self.lineLimit = lineLimit
        self.stream = stream
    }
}

public struct RuntimeLogTailResult: Codable, Equatable, Sendable {
    public let runtimeInstanceID: String
    public let filePath: String
    public let entries: [RuntimeLogEntry]
    public let truncated: Bool

    public init(runtimeInstanceID: String, filePath: String, entries: [RuntimeLogEntry], truncated: Bool) {
        self.runtimeInstanceID = runtimeInstanceID
        self.filePath = SecretRedactor.redactText(filePath)
        self.entries = entries
        self.truncated = truncated
    }
}

public enum RuntimeLogTailError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidLineLimit(Int)
    case fileNotFound(String)
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .invalidLineLimit(let limit):
            return "Invalid log line limit: \(limit). Use a value from 1 to 500."
        case .fileNotFound(let path):
            return "Log file not found: \(SecretRedactor.redactText(path))"
        case .unreadableFile(let path):
            return "Log file is not readable as UTF-8 text: \(SecretRedactor.redactText(path))"
        }
    }
}

public struct RuntimeLogTailer: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func tail(request: RuntimeLogTailRequest) throws -> RuntimeLogTailResult {
        guard request.lineLimit >= 1, request.lineLimit <= 500 else {
            throw RuntimeLogTailError.invalidLineLimit(request.lineLimit)
        }
        guard FileManager.default.fileExists(atPath: request.filePath) else {
            throw RuntimeLogTailError.fileNotFound(request.filePath)
        }
        guard let text = try? String(contentsOfFile: request.filePath, encoding: .utf8) else {
            throw RuntimeLogTailError.unreadableFile(request.filePath)
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        let selectedLines = Array(lines.suffix(request.lineLimit))
        let timestamp = now()
        let entries = selectedLines.enumerated().map { offset, line in
            RuntimeLogEntry(
                id: "\(request.runtimeInstanceID):\(max(0, lines.count - selectedLines.count + offset))",
                runtimeInstanceID: request.runtimeInstanceID,
                stream: request.stream,
                timestamp: timestamp,
                message: line
            )
        }
        return RuntimeLogTailResult(
            runtimeInstanceID: request.runtimeInstanceID,
            filePath: request.filePath,
            entries: entries,
            truncated: lines.count > selectedLines.count
        )
    }
}
