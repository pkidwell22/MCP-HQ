import Foundation

public struct AgentBindingDesiredStateIndex: Sendable {
    private let statesByName: [String: [SQLiteDesiredServerState]]

    public init(states: [SQLiteDesiredServerState]) {
        self.statesByName = Dictionary(grouping: states) { state in
            Self.normalizedName(state.serverName)
        }
    }

    public var normalizedBindingNames: Set<String> {
        Set(statesByName.keys)
    }

    public func states(named name: String) -> [SQLiteDesiredServerState] {
        statesByName[Self.normalizedName(name)] ?? []
    }

    public func hasDesiredState(named name: String) -> Bool {
        !states(named: name).isEmpty
    }

    public func templateServer(named name: String) -> ServerDefinition? {
        states(named: name).sorted(by: sourceSort).first?.server
    }

    public func enabledSourceIDs(named name: String, currentSourceIDs: Set<String>) -> Set<String> {
        states(named: name).reduce(into: currentSourceIDs) { result, state in
            if state.enabled {
                result.insert(state.source.id)
            } else {
                result.remove(state.source.id)
            }
        }
    }

    public func enabledDesiredSourceIDs(named name: String) -> Set<String> {
        Set(states(named: name).filter(\.enabled).map { $0.source.id })
    }

    public static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sourceSort(_ lhs: SQLiteDesiredServerState, _ rhs: SQLiteDesiredServerState) -> Bool {
        if lhs.source.agent != rhs.source.agent {
            return lhs.source.agent.rawValue < rhs.source.agent.rawValue
        }
        if lhs.source.path != rhs.source.path {
            return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

public struct AgentCanonicalServerIdentity: Codable, Equatable, Sendable, Identifiable {
    public var id: String { normalizedName }
    public let normalizedName: String
    public let displayName: String

    public init(normalizedName: String, displayName: String) {
        self.normalizedName = normalizedName
        self.displayName = displayName
    }
}

public enum AgentCanonicalSourceBindingIntent: String, Codable, Equatable, Sendable {
    case desiredEnabled = "desired_enabled"
    case desiredDisabled = "desired_disabled"
    case observedOnly = "observed_only"
}

public enum AgentCanonicalBindingDriftStatus: String, Codable, Equatable, Sendable {
    case inSync = "in_sync"
    case missingFromScan = "missing_from_scan"
    case presentButDisabled = "present_but_disabled"
    case payloadMismatch = "payload_mismatch"
    case observedOnly = "observed_only"

    public var isDrift: Bool {
        switch self {
        case .missingFromScan, .presentButDisabled, .payloadMismatch:
            return true
        case .inSync, .observedOnly:
            return false
        }
    }
}

public struct AgentCanonicalSourceBinding: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(identity.normalizedName):\(source.id)" }
    public let identity: AgentCanonicalServerIdentity
    public let source: ConfigSource
    public let agentName: String
    public let intent: AgentCanonicalSourceBindingIntent
    public let driftStatus: AgentCanonicalBindingDriftStatus
    public let payloadDriftDetails: [String]
    public let isPresentInScan: Bool
    public let scannedServerID: String?
    public let desiredUpdatedAt: Date?

    public init(
        identity: AgentCanonicalServerIdentity,
        source: ConfigSource,
        agentName: String,
        intent: AgentCanonicalSourceBindingIntent,
        driftStatus: AgentCanonicalBindingDriftStatus,
        payloadDriftDetails: [String] = [],
        isPresentInScan: Bool,
        scannedServerID: String?,
        desiredUpdatedAt: Date?
    ) {
        self.identity = identity
        self.source = source
        self.agentName = agentName
        self.intent = intent
        self.driftStatus = driftStatus
        self.payloadDriftDetails = payloadDriftDetails.map(SecretRedactor.redactText)
        self.isPresentInScan = isPresentInScan
        self.scannedServerID = scannedServerID
        self.desiredUpdatedAt = desiredUpdatedAt
    }
}

public struct AgentCanonicalBindingSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { identity.id }
    public let identity: AgentCanonicalServerIdentity
    public let templateServer: ServerDefinition
    public let sourceBindings: [AgentCanonicalSourceBinding]

    public var desiredEnabledCount: Int {
        sourceBindings.filter { $0.intent == .desiredEnabled }.count
    }

    public var desiredDisabledCount: Int {
        sourceBindings.filter { $0.intent == .desiredDisabled }.count
    }

    public var observedOnlyCount: Int {
        sourceBindings.filter { $0.intent == .observedOnly }.count
    }

    public var driftCount: Int {
        sourceBindings.filter { $0.driftStatus.isDrift }.count
    }

    public var isDrifted: Bool {
        driftCount > 0
    }

    public var summaryText: String {
        "\(identity.displayName): \(desiredEnabledCount) desired on, \(desiredDisabledCount) desired off, \(observedOnlyCount) observed only, \(driftCount) drift\(driftCount == 1 ? "" : "s")"
    }

    public init(
        identity: AgentCanonicalServerIdentity,
        templateServer: ServerDefinition,
        sourceBindings: [AgentCanonicalSourceBinding]
    ) {
        self.identity = identity
        self.templateServer = templateServer
        self.sourceBindings = sourceBindings
    }
}

public struct AgentCanonicalAuthoringModel: Codable, Equatable, Sendable {
    public let bindings: [AgentCanonicalBindingSummary]

    public var bindingCount: Int { bindings.count }

    public var sourceBindingCount: Int {
        bindings.reduce(0) { $0 + $1.sourceBindings.count }
    }

    public var desiredEnabledCount: Int {
        bindings.reduce(0) { $0 + $1.desiredEnabledCount }
    }

    public var observedOnlyCount: Int {
        bindings.reduce(0) { $0 + $1.observedOnlyCount }
    }

    public var driftCount: Int {
        bindings.reduce(0) { $0 + $1.driftCount }
    }

    public var driftedBindingCount: Int {
        bindings.filter(\.isDrifted).count
    }

    public var summaryText: String {
        "\(bindingCount) canonical binding\(bindingCount == 1 ? "" : "s"), \(desiredEnabledCount) desired enabled, \(observedOnlyCount) observed only, \(driftCount) drift\(driftCount == 1 ? "" : "s")"
    }

    public init(bindings: [AgentCanonicalBindingSummary]) {
        self.bindings = bindings
    }

    public init(scanResult: ScanResult, desiredStates: [SQLiteDesiredServerState]) {
        self.bindings = Self.buildBindings(scanResult: scanResult, desiredStates: desiredStates)
    }

    public static func build(scanResult: ScanResult, desiredStates: [SQLiteDesiredServerState]) -> AgentCanonicalAuthoringModel {
        AgentCanonicalAuthoringModel(scanResult: scanResult, desiredStates: desiredStates)
    }

    private static func buildBindings(
        scanResult: ScanResult,
        desiredStates: [SQLiteDesiredServerState]
    ) -> [AgentCanonicalBindingSummary] {
        let scannedByName = Dictionary(grouping: scanResult.servers) { server in
            normalizedName(server.displayName)
        }
        let desiredByName = Dictionary(grouping: desiredStates) { state in
            normalizedName(state.serverName)
        }
        let keys = Set(scannedByName.keys).union(desiredByName.keys)
        let sourcesByPath = sourceLookup(from: scanResult, desiredStates: desiredStates)

        return keys.compactMap { key -> AgentCanonicalBindingSummary? in
            let scannedServers = (scannedByName[key] ?? []).sorted(by: serverSort)
            let desiredStatesForBinding = (desiredByName[key] ?? []).sorted(by: desiredStateSort)
            guard let template = desiredStatesForBinding.first?.server ?? scannedServers.first else { return nil }
            let displayName = displayName(for: key, desiredStates: desiredStatesForBinding, scannedServers: scannedServers)
            let identity = AgentCanonicalServerIdentity(normalizedName: key, displayName: displayName)
            let sourceIDs = sourceIDsForBinding(
                scannedServers: scannedServers,
                desiredStates: desiredStatesForBinding,
                sourcesByPath: sourcesByPath
            )
            let sourceBindings = sourceIDs.compactMap { sourceID -> AgentCanonicalSourceBinding? in
                let source = sourceForID(
                    sourceID,
                    sourcesByPath: sourcesByPath,
                    desiredStates: desiredStatesForBinding,
                    scannedServers: scannedServers
                )
                guard let source else { return nil }
                let scannedServer = scannedServers.first { server in
                    (sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath)).id == sourceID
                }
                let desiredState = latestDesiredState(for: sourceID, in: desiredStatesForBinding)
                let intent = intent(for: desiredState)
                let present = scannedServer != nil
                let payloadDetails = desiredState.flatMap { desiredState in
                    scannedServer.map { payloadDriftDetails(desired: desiredState.server, scanned: $0) }
                } ?? []
                return AgentCanonicalSourceBinding(
                    identity: identity,
                    source: source,
                    agentName: AgentRegistry.displayName(for: source.agent),
                    intent: intent,
                    driftStatus: driftStatus(intent: intent, isPresentInScan: present, payloadDriftDetails: payloadDetails),
                    payloadDriftDetails: payloadDetails,
                    isPresentInScan: present,
                    scannedServerID: scannedServer?.id,
                    desiredUpdatedAt: desiredState?.updatedAt
                )
            }
            .sorted(by: sourceBindingSort)

            return AgentCanonicalBindingSummary(
                identity: identity,
                templateServer: template,
                sourceBindings: sourceBindings
            )
        }
        .sorted { lhs, rhs in
            lhs.identity.displayName.localizedCaseInsensitiveCompare(rhs.identity.displayName) == .orderedAscending
        }
    }

    private static func sourceLookup(
        from scanResult: ScanResult,
        desiredStates: [SQLiteDesiredServerState]
    ) -> [String: ConfigSource] {
        var sourcesByPath: [String: ConfigSource] = [:]
        for source in scanResult.sources {
            sourcesByPath[source.path] = source
        }
        for health in scanResult.sourceHealth {
            sourcesByPath[health.source.path] = health.source
        }
        for server in scanResult.servers where sourcesByPath[server.sourcePath] == nil {
            sourcesByPath[server.sourcePath] = ConfigSource(agent: .unknown, path: server.sourcePath)
        }
        for state in desiredStates where sourcesByPath[state.source.path] == nil {
            sourcesByPath[state.source.path] = state.source
        }
        return sourcesByPath
    }

    private static func sourceIDsForBinding(
        scannedServers: [ServerDefinition],
        desiredStates: [SQLiteDesiredServerState],
        sourcesByPath: [String: ConfigSource]
    ) -> [String] {
        var ids: Set<String> = []
        for server in scannedServers {
            ids.insert((sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath)).id)
        }
        for state in desiredStates {
            ids.insert(state.source.id)
        }
        return Array(ids).sorted()
    }

    private static func sourceForID(
        _ sourceID: String,
        sourcesByPath: [String: ConfigSource],
        desiredStates: [SQLiteDesiredServerState],
        scannedServers: [ServerDefinition]
    ) -> ConfigSource? {
        if let source = sourcesByPath.values.first(where: { $0.id == sourceID }) {
            return source
        }
        if let source = desiredStates.first(where: { $0.source.id == sourceID })?.source {
            return source
        }
        if let server = scannedServers.first(where: { server in
            (sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath)).id == sourceID
        }) {
            return sourcesByPath[server.sourcePath] ?? ConfigSource(agent: .unknown, path: server.sourcePath)
        }
        return nil
    }

    private static func latestDesiredState(
        for sourceID: String,
        in desiredStates: [SQLiteDesiredServerState]
    ) -> SQLiteDesiredServerState? {
        desiredStates
            .filter { $0.source.id == sourceID }
            .sorted(by: desiredStateSort)
            .first
    }

    private static func intent(for desiredState: SQLiteDesiredServerState?) -> AgentCanonicalSourceBindingIntent {
        guard let desiredState else { return .observedOnly }
        return desiredState.enabled ? .desiredEnabled : .desiredDisabled
    }

    private static func driftStatus(
        intent: AgentCanonicalSourceBindingIntent,
        isPresentInScan: Bool,
        payloadDriftDetails: [String]
    ) -> AgentCanonicalBindingDriftStatus {
        switch (intent, isPresentInScan) {
        case (.desiredEnabled, true):
            return payloadDriftDetails.isEmpty ? .inSync : .payloadMismatch
        case (.desiredDisabled, false):
            return .inSync
        case (.desiredEnabled, false):
            return .missingFromScan
        case (.desiredDisabled, true):
            return .presentButDisabled
        case (.observedOnly, _):
            return .observedOnly
        }
    }

    private static func payloadDriftDetails(desired: ServerDefinition, scanned: ServerDefinition) -> [String] {
        var details: [String] = []
        if desired.transport != scanned.transport {
            details.append("transport differs: desired \(desired.transport.rawValue), scanned \(scanned.transport.rawValue)")
        }
        if normalizedOptional(desired.command) != normalizedOptional(scanned.command) {
            details.append("command differs: desired \(redactedOptional(desired.command)), scanned \(redactedOptional(scanned.command))")
        }
        if desired.args != scanned.args {
            details.append("args differ: desired \(redactedList(desired.args)), scanned \(redactedList(scanned.args))")
        }
        if normalizedOptional(desired.url) != normalizedOptional(scanned.url) {
            details.append("url differs: desired \(redactedOptional(desired.url)), scanned \(redactedOptional(scanned.url))")
        }
        if redactedMap(desired.envBindings) != redactedMap(scanned.envBindings) {
            details.append("environment differs")
        }
        if redactedMap(desired.headers) != redactedMap(scanned.headers) {
            details.append("headers differ")
        }
        return details.map(SecretRedactor.redactText)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func redactedOptional(_ value: String?) -> String {
        guard let value else { return "none" }
        return SecretRedactor.redactText(value)
    }

    private static func redactedList(_ values: [String]) -> String {
        "[\(SecretRedactor.redactCommandArguments(values).joined(separator: ", "))]"
    }

    private static func redactedMap(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, pair in
            result[pair.key] = SecretRedactor.redactIfSensitive(SecretRedactor.redactText(pair.value))
        }
    }

    private static func displayName(
        for normalizedName: String,
        desiredStates: [SQLiteDesiredServerState],
        scannedServers: [ServerDefinition]
    ) -> String {
        if let desiredName = desiredStates.first?.server.displayName, !desiredName.isEmpty {
            return desiredName
        }
        if let serverName = desiredStates.first?.serverName, !serverName.isEmpty {
            return serverName
        }
        if let scannedName = scannedServers.first?.displayName, !scannedName.isEmpty {
            return scannedName
        }
        return normalizedName
    }

    private static func desiredStateSort(_ lhs: SQLiteDesiredServerState, _ rhs: SQLiteDesiredServerState) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.source.agent != rhs.source.agent {
            return lhs.source.agent.rawValue < rhs.source.agent.rawValue
        }
        return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
    }

    private static func serverSort(_ lhs: ServerDefinition, _ rhs: ServerDefinition) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath) == .orderedAscending
    }

    private static func sourceBindingSort(_ lhs: AgentCanonicalSourceBinding, _ rhs: AgentCanonicalSourceBinding) -> Bool {
        if lhs.agentName != rhs.agentName {
            return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
        }
        return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
    }

    private static func normalizedName(_ value: String) -> String {
        AgentBindingDesiredStateIndex.normalizedName(value)
    }
}
