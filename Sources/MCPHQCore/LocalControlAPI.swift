import Foundation

public enum LocalControlRoute: String, Codable, Equatable, Sendable {
    case status
    case scan
    case servers
    case doctor
    case configPreview = "config_preview"
    case configApply = "config_apply"
    case configConnectAllPreview = "config_connect_all_preview"
    case configConnectAllApply = "config_connect_all_apply"
    case runtimeExplain = "runtime_explain"
    case runtimeStart = "runtime_start"
    case runtimeStop = "runtime_stop"
    case runtimeRestart = "runtime_restart"

    public var allowsDirectCoreFallback: Bool {
        switch self {
        case .status, .scan, .servers, .doctor, .configPreview, .configConnectAllPreview, .runtimeExplain:
            return true
        case .configApply, .configConnectAllApply, .runtimeStart, .runtimeStop, .runtimeRestart:
            return false
        }
    }
}

public struct LocalControlRequest: Codable, Equatable, Sendable {
    public let route: LocalControlRoute
    public let includeProbes: Bool
    public let source: ConfigSource?
    public let serverSource: ConfigSource?
    public let templateSource: ConfigSource?
    public let targetSources: [ConfigSource]
    public let dryRun: Bool
    public let runtimeInstance: RuntimeInstance?
    public let runtimeInstanceID: String?
    public let server: ServerDefinition?
    public let logDirectory: String?

    public init(
        route: LocalControlRoute,
        includeProbes: Bool = false,
        source: ConfigSource? = nil,
        serverSource: ConfigSource? = nil,
        templateSource: ConfigSource? = nil,
        targetSources: [ConfigSource] = [],
        dryRun: Bool = true,
        runtimeInstance: RuntimeInstance? = nil,
        runtimeInstanceID: String? = nil,
        server: ServerDefinition? = nil,
        logDirectory: String? = nil
    ) {
        self.route = route
        self.includeProbes = includeProbes
        self.source = source
        self.serverSource = serverSource
        self.templateSource = templateSource
        self.targetSources = targetSources
        self.dryRun = dryRun
        self.runtimeInstance = runtimeInstance
        self.runtimeInstanceID = runtimeInstanceID.map(SecretRedactor.redactText)
        self.server = server
        self.logDirectory = logDirectory
    }

    public var allowsDirectCoreFallback: Bool {
        route.allowsDirectCoreFallback
    }
}

public struct LocalControlStatus: Codable, Equatable, Sendable {
    public let serverCount: Int
    public let sourceCount: Int
    public let processCount: Int
    public let issueCount: Int
    public let warningCount: Int
    public let errorCount: Int
    public let scannedAt: Date?
    public let scanStatus: HealthCacheScanStatus?
    public let servedFromHealthCache: Bool?
    public let cacheAgeSeconds: Int?
    public let cacheStaleAfterSeconds: Int?
    public let cacheFreshness: HealthCacheFreshness?
    public let cacheRefreshRecommended: Bool?

    public init(result: ScanResult) {
        self.init(counts: HealthSummaryCounts(result: result))
    }

    public init(
        snapshot: HealthCacheSnapshot,
        servedFromHealthCache: Bool = true,
        now: Date = Date(),
        staleAfterSeconds: Int = HealthCacheSnapshot.defaultStaleAfterSeconds
    ) {
        let cacheAgeSeconds = snapshot.ageSeconds(at: now)
        let freshness = snapshot.freshness(at: now, staleAfterSeconds: staleAfterSeconds)
        self.init(
            counts: snapshot.counts,
            scannedAt: snapshot.scannedAt,
            scanStatus: snapshot.scanStatus,
            servedFromHealthCache: servedFromHealthCache,
            cacheAgeSeconds: cacheAgeSeconds,
            cacheStaleAfterSeconds: staleAfterSeconds,
            cacheFreshness: freshness,
            cacheRefreshRecommended: freshness == .stale
        )
    }

    public init(
        counts: HealthSummaryCounts,
        scannedAt: Date? = nil,
        scanStatus: HealthCacheScanStatus? = nil,
        servedFromHealthCache: Bool? = nil,
        cacheAgeSeconds: Int? = nil,
        cacheStaleAfterSeconds: Int? = nil,
        cacheFreshness: HealthCacheFreshness? = nil,
        cacheRefreshRecommended: Bool? = nil
    ) {
        self.serverCount = counts.serverCount
        self.sourceCount = counts.sourceCount
        self.processCount = counts.processCount
        self.issueCount = counts.issueCount
        self.warningCount = counts.warningCount
        self.errorCount = counts.errorCount
        self.scannedAt = scannedAt
        self.scanStatus = scanStatus
        self.servedFromHealthCache = servedFromHealthCache
        self.cacheAgeSeconds = cacheAgeSeconds
        self.cacheStaleAfterSeconds = cacheStaleAfterSeconds
        self.cacheFreshness = cacheFreshness
        self.cacheRefreshRecommended = cacheRefreshRecommended
    }
}

public struct LocalControlConfigPreview: Codable, Equatable, Sendable {
    public let target: ConfigSource
    public let serverSource: ConfigSource
    public let renderedText: String
    public let reparsedServerCount: Int

    public init(target: ConfigSource, serverSource: ConfigSource, renderedText: String, reparsedServerCount: Int) {
        self.target = target
        self.serverSource = serverSource
        self.renderedText = SecretRedactor.redactConfigText(renderedText)
        self.reparsedServerCount = reparsedServerCount
    }
}

public struct LocalControlConfigApply: Codable, Equatable, Sendable {
    public let target: ConfigSource
    public let serverSource: ConfigSource
    public let dryRun: Bool
    public let didWrite: Bool
    public let backupPath: String?
    public let renderedText: String
    public let reparsedServerCount: Int

    public init(target: ConfigSource, serverSource: ConfigSource, dryRun: Bool, result: ConfigApplyResult) {
        self.target = target
        self.serverSource = serverSource
        self.dryRun = dryRun
        self.didWrite = result.didWrite
        self.backupPath = result.backupPath.map(SecretRedactor.redactText)
        self.renderedText = SecretRedactor.redactConfigText(result.preview.renderedText)
        self.reparsedServerCount = result.preview.reparsedServers.count
    }
}

public struct LocalControlConfigBulkPreview: Codable, Equatable, Sendable {
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let targetCount: Int
    public let changedTargetCount: Int
    public let summaryText: String
    public let text: String

    public init(draft: AgentBulkBindingDraftPreview, text: String) {
        self.templateSource = draft.templateSource
        self.templateBindingCount = draft.templateBindingCount
        self.targetCount = draft.targetPreviews.count
        self.changedTargetCount = draft.changedPreviews.count
        self.summaryText = SecretRedactor.redactText(draft.summaryText)
        self.text = SecretRedactor.redactConfigText(text)
    }
}

public struct LocalControlConfigBulkApply: Codable, Equatable, Sendable {
    public let dryRun: Bool
    public let didWrite: Bool
    public let templateSource: ConfigSource?
    public let templateBindingCount: Int
    public let affectedTargetCount: Int
    public let summaryText: String
    public let text: String

    public init(dryRun: Bool, draft: AgentBulkBindingDraftPreview, text: String) {
        self.dryRun = dryRun
        self.didWrite = false
        self.templateSource = draft.templateSource
        self.templateBindingCount = draft.templateBindingCount
        self.affectedTargetCount = draft.changedPreviews.count
        self.summaryText = SecretRedactor.redactText(draft.summaryText)
        self.text = SecretRedactor.redactConfigText(text)
    }

    public init(result: AgentBulkBindingDraftApplyResult, text: String) {
        self.dryRun = false
        self.didWrite = !result.appliedTargets.isEmpty
        self.templateSource = result.templateSource
        self.templateBindingCount = result.templateBindingCount
        self.affectedTargetCount = result.appliedTargets.count
        self.summaryText = SecretRedactor.redactText(result.summaryText)
        self.text = SecretRedactor.redactConfigText(text)
    }
}

public struct LocalControlResponse: Codable, Equatable, Sendable {
    public let status: LocalControlStatus?
    public let scanResult: ScanResult?
    public let healthCache: HealthCacheSnapshot?
    public let servers: [ServerDefinition]?
    public let doctorReport: DoctorReport?
    public let configPreview: LocalControlConfigPreview?
    public let configApply: LocalControlConfigApply?
    public let configBulkPreview: LocalControlConfigBulkPreview?
    public let configBulkApply: LocalControlConfigBulkApply?
    public let runtimeExplanations: [RuntimeLifecycleExplanation]?
    public let runtimeInstance: RuntimeInstance?
    public let error: String?

    public init(
        status: LocalControlStatus? = nil,
        scanResult: ScanResult? = nil,
        healthCache: HealthCacheSnapshot? = nil,
        servers: [ServerDefinition]? = nil,
        doctorReport: DoctorReport? = nil,
        configPreview: LocalControlConfigPreview? = nil,
        configApply: LocalControlConfigApply? = nil,
        configBulkPreview: LocalControlConfigBulkPreview? = nil,
        configBulkApply: LocalControlConfigBulkApply? = nil,
        runtimeExplanations: [RuntimeLifecycleExplanation]? = nil,
        runtimeInstance: RuntimeInstance? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.scanResult = scanResult
        self.healthCache = healthCache
        self.servers = servers
        self.doctorReport = doctorReport
        self.configPreview = configPreview
        self.configApply = configApply
        self.configBulkPreview = configBulkPreview
        self.configBulkApply = configBulkApply
        self.runtimeExplanations = runtimeExplanations
        self.runtimeInstance = runtimeInstance
        self.error = error.map(SecretRedactor.redactText)
    }
}

private enum LocalControlConfigError: Error, CustomStringConvertible {
    case sourceFileMissing(ConfigSource)
    case unsupportedAgent(AgentID)

    var description: String {
        switch self {
        case .sourceFileMissing(let source):
            return "Config source does not exist: \(source.agent.rawValue):\(source.path)"
        case .unsupportedAgent(let agent):
            return "Config parsing is not supported for \(agent.rawValue)"
        }
    }
}

public struct LocalControlRouter: @unchecked Sendable {
    private let defaultSourceProvider: DefaultConfigSourceProvider
    private let scanCoordinator: ScanCoordinator
    private let doctorBuilder: DoctorReportBuilder
    private let parser: AgentConfigParser
    private let applier: AgentConfigSafeApplier
    private let runtimeSupervisor: HubRuntimeSupervisor
    private let controlPlaneStore: SQLiteScanHistoryStore?
    private let healthCacheStore: JSONHealthCacheStore?
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        defaultSourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        scanCoordinator: ScanCoordinator = ScanCoordinator(secretStore: MacOSKeychainSecretStore()),
        doctorBuilder: DoctorReportBuilder = DoctorReportBuilder(),
        parser: AgentConfigParser = AgentConfigParser(),
        applier: AgentConfigSafeApplier = AgentConfigSafeApplier(),
        runtimeSupervisor: HubRuntimeSupervisor = HubRuntimeSupervisor(),
        controlPlaneStore: SQLiteScanHistoryStore? = nil,
        healthCacheStore: JSONHealthCacheStore? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaultSourceProvider = defaultSourceProvider
        self.scanCoordinator = scanCoordinator
        self.doctorBuilder = doctorBuilder
        self.parser = parser
        self.applier = applier
        self.runtimeSupervisor = runtimeSupervisor
        self.controlPlaneStore = controlPlaneStore
        self.healthCacheStore = healthCacheStore
        self.fileManager = fileManager
        self.now = now
    }

    public func handle(_ request: LocalControlRequest) -> LocalControlResponse {
        switch request.route {
        case .status:
            return statusResponse(request)
        case .scan:
            let sources = resolvedSources(request: request)
            let result = scan(sources: sources, includeProbes: request.includeProbes)
            let snapshot = updateHealthCache(result: result, scannedAt: now(), sources: sources, includeProbes: request.includeProbes)
            return LocalControlResponse(scanResult: redacted(result), healthCache: snapshot)
        case .servers:
            return LocalControlResponse(servers: redactedServers(scan(request: request).servers))
        case .doctor:
            return LocalControlResponse(doctorReport: doctorBuilder.build(from: scan(request: request)))
        case .configPreview:
            return configPreviewResponse(request)
        case .configApply:
            return configApplyResponse(request)
        case .configConnectAllPreview:
            return configConnectAllPreviewResponse(request)
        case .configConnectAllApply:
            return configConnectAllApplyResponse(request)
        case .runtimeExplain:
            return LocalControlResponse(runtimeExplanations: runtimeExplanations(request: request))
        case .runtimeStart:
            return runtimeStartResponse(request)
        case .runtimeStop:
            return runtimeStopResponse(request)
        case .runtimeRestart:
            return runtimeRestartResponse(request)
        }
    }

    private func statusResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        let sources = resolvedSources(request: request)
        if canServeCachedStatus(for: request),
           let snapshot = try? healthCacheStore?.load(),
           snapshot.matches(sources: sources, includesProbes: request.includeProbes) {
            return LocalControlResponse(
                status: LocalControlStatus(snapshot: snapshot, now: now()),
                healthCache: snapshot
            )
        }

        let result = scan(sources: sources, includeProbes: request.includeProbes)
        let snapshot = updateHealthCache(result: result, scannedAt: now(), sources: sources, includeProbes: request.includeProbes)
        if let snapshot {
            return LocalControlResponse(
                status: LocalControlStatus(snapshot: snapshot, servedFromHealthCache: false, now: now()),
                healthCache: snapshot
            )
        }
        return LocalControlResponse(status: LocalControlStatus(result: result))
    }

    private func canServeCachedStatus(for request: LocalControlRequest) -> Bool {
        request.source == nil && request.targetSources.isEmpty && !request.includeProbes
    }

    private func resolvedSources(request: LocalControlRequest) -> [ConfigSource] {
        if let source = request.source {
            return [source]
        }
        if !request.targetSources.isEmpty {
            return request.targetSources
        }
        return defaultSourceProvider.sources()
    }

    private func scan(request: LocalControlRequest) -> ScanResult {
        scan(sources: resolvedSources(request: request), includeProbes: request.includeProbes)
    }

    private func scan(sources: [ConfigSource], includeProbes: Bool) -> ScanResult {
        scanCoordinator.scan(sources: sources, includeProbes: includeProbes)
    }

    private func updateHealthCache(
        result: ScanResult,
        scannedAt: Date,
        sources: [ConfigSource],
        includeProbes: Bool
    ) -> HealthCacheSnapshot? {
        let snapshot = HealthCacheSnapshot(result: result, scannedAt: scannedAt, sources: sources, includesProbes: includeProbes)
        try? healthCacheStore?.save(snapshot)
        return snapshot
    }

    private func redacted(_ result: ScanResult) -> ScanResult {
        ScanResult(
            servers: redactedServers(result.servers),
            sources: result.sources,
            sourceHealth: result.sourceHealth,
            issues: result.issues.map { issue in
                ScanIssue(source: issue.source, severity: issue.severity, message: SecretRedactor.redactText(issue.message))
            },
            processes: result.processes,
            processMatches: result.processMatches,
            probeResults: result.probeResults
        )
    }

    private func redactedServers(_ servers: [ServerDefinition]) -> [ServerDefinition] {
        servers.map { server in
            ServerDefinition(
                id: server.id,
                displayName: server.displayName,
                transport: server.transport,
                command: server.command.map(SecretRedactor.redactText),
                args: SecretRedactor.redactCommandArguments(server.args),
                url: server.url.map(SecretRedactor.redactText),
                headers: server.headers.reduce(into: [:]) { result, pair in
                    result[pair.key] = SecretRedactor.redactIfSensitive(SecretRedactor.redactText(pair.value))
                },
                envBindings: server.envBindings.reduce(into: [:]) { result, pair in
                    result[pair.key] = SecretRedactor.redactIfSensitive(SecretRedactor.redactText(pair.value))
                },
                sourcePath: server.sourcePath
            )
        }
    }

    private func configPreviewResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let target = request.source else {
            return LocalControlResponse(error: "Missing target source for config preview")
        }
        let inputSource = request.serverSource ?? target
        do {
            guard fileManager.fileExists(atPath: inputSource.path) else {
                return LocalControlResponse(error: "Config source does not exist: \(inputSource.agent.rawValue):\(inputSource.path)")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: inputSource.path))
            try ConfigSyntaxValidator.validate(data: data, agent: inputSource.agent)
            let servers = try parser.parse(data: data, source: inputSource)
            let preview = try applier.preview(source: target, servers: servers)
            return LocalControlResponse(configPreview: LocalControlConfigPreview(
                target: target,
                serverSource: inputSource,
                renderedText: preview.renderedText,
                reparsedServerCount: preview.reparsedServers.count
            ))
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func configApplyResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let target = request.source else {
            return LocalControlResponse(error: "Missing target source for config apply")
        }
        let inputSource = request.serverSource ?? target
        do {
            guard fileManager.fileExists(atPath: inputSource.path) else {
                return LocalControlResponse(error: "Config source does not exist: \(inputSource.agent.rawValue):\(inputSource.path)")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: inputSource.path))
            try ConfigSyntaxValidator.validate(data: data, agent: inputSource.agent)
            let servers = try parser.parse(data: data, source: inputSource)
            let result = try applier.apply(source: target, servers: servers, dryRun: request.dryRun)
            return LocalControlResponse(configApply: LocalControlConfigApply(
                target: target,
                serverSource: inputSource,
                dryRun: request.dryRun,
                result: result
            ))
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func configConnectAllPreviewResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let templateSource = request.templateSource else {
            return LocalControlResponse(error: "Missing template source for config connect-all preview")
        }
        guard !request.targetSources.isEmpty else {
            return LocalControlResponse(error: "Missing target sources for config connect-all preview")
        }

        do {
            let draft = try previewConnectAllDraft(templateSource: templateSource, targetSources: request.targetSources)
            return LocalControlResponse(configBulkPreview: LocalControlConfigBulkPreview(
                draft: draft,
                text: Self.formatConnectAllPreview(draft)
            ))
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func configConnectAllApplyResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let templateSource = request.templateSource else {
            return LocalControlResponse(error: "Missing template source for config connect-all apply")
        }
        guard !request.targetSources.isEmpty else {
            return LocalControlResponse(error: "Missing target sources for config connect-all apply")
        }

        do {
            if request.dryRun {
                let draft = try previewConnectAllDraft(templateSource: templateSource, targetSources: request.targetSources)
                return LocalControlResponse(configBulkApply: LocalControlConfigBulkApply(
                    dryRun: true,
                    draft: draft,
                    text: Self.formatConnectAllPreview(draft, title: "Config connect-all apply dry run")
                ))
            }

            let templateServers = try loadServers(from: templateSource, requireExisting: true)
            let existingServers = try loadExistingServers(from: request.targetSources)
            let enabledSourceIDs = Set(request.targetSources.map(\.id))
            let result = try AgentBulkConfigAuthoringPlanner().applyConnectAll(
                templateServers: templateServers,
                templateSource: templateSource,
                targetSources: request.targetSources,
                existingServers: existingServers,
                enabledSourceIDs: enabledSourceIDs
            )
            let responseResult: AgentBulkBindingDraftApplyResult
            if request.includeProbes {
                let scanResult = scanCoordinator.scan(sources: request.targetSources, includeProbes: true)
                let verificationReport = AgentBulkConnectVerifier().verify(
                    templateServers: templateServers,
                    targetSources: request.targetSources,
                    probeResults: scanResult.probeResults
                )
                responseResult = AgentBulkBindingDraftApplyResult(
                    templateSource: result.templateSource,
                    templateBindingCount: result.templateBindingCount,
                    appliedTargets: result.appliedTargets,
                    verificationReport: verificationReport,
                    rollbackPlan: result.rollbackPlan
                )
            } else {
                responseResult = result
            }
            return LocalControlResponse(configBulkApply: LocalControlConfigBulkApply(
                result: responseResult,
                text: Self.formatConnectAllApply(responseResult)
            ))
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func previewConnectAllDraft(templateSource: ConfigSource, targetSources: [ConfigSource]) throws -> AgentBulkBindingDraftPreview {
        let templateServers = try loadServers(from: templateSource, requireExisting: true)
        let existingServers = try loadExistingServers(from: targetSources)
        return try AgentBulkConfigAuthoringPlanner().previewConnectAll(
            templateServers: templateServers,
            templateSource: templateSource,
            targetSources: targetSources,
            existingServers: existingServers,
            enabledSourceIDs: Set(targetSources.map(\.id))
        )
    }

    private func loadServers(from source: ConfigSource, requireExisting: Bool) throws -> [ServerDefinition] {
        if requireExisting || fileManager.fileExists(atPath: source.path) {
            guard fileManager.fileExists(atPath: source.path) else {
                throw LocalControlConfigError.sourceFileMissing(source)
            }
            guard parser.supports(source.agent) else {
                throw LocalControlConfigError.unsupportedAgent(source.agent)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
            try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
            return try parser.parse(data: data, source: source)
        }
        return []
    }

    private func loadExistingServers(from sources: [ConfigSource]) throws -> [ServerDefinition] {
        var result: [ServerDefinition] = []
        for source in sources {
            result.append(contentsOf: try loadServers(from: source, requireExisting: false))
        }
        return result
    }

    private static func formatConnectAllPreview(_ draft: AgentBulkBindingDraftPreview, title: String = "Config connect-all preview") -> String {
        var lines = [
            title,
            draft.summaryText,
            "Template source: \(draft.templateSource.map { "\($0.agent.rawValue):\($0.path)" } ?? "selected bindings")",
            "Target sources: \(draft.targetPreviews.count)",
            "",
        ]

        if draft.targetPreviews.isEmpty {
            lines.append("No config files would change for the selected targets.")
            return lines.joined(separator: "\n") + "\n"
        }

        for target in draft.targetPreviews {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.agent.rawValue):\(target.source.path)")
            lines.append("Will create missing config: \(FileManager.default.fileExists(atPath: target.source.path) ? "no" : "yes")")
            lines.append("Bindings to ensure: \(target.bindingCount)")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("")
            lines.append("Diff:")
            lines.append(SecretRedactor.redactConfigText(target.preview.diffText))
            lines.append("")
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n")) + "\n"
    }

    private static func formatConnectAllApply(_ result: AgentBulkBindingDraftApplyResult) -> String {
        var lines = [
            "Config connect-all apply",
            result.summaryText,
            "Template source: \(result.templateSource.map { "\($0.agent.rawValue):\($0.path)" } ?? "selected bindings")",
            "",
        ]

        if result.appliedTargets.isEmpty {
            lines.append("No config files changed.")
            return lines.joined(separator: "\n") + "\n"
        }

        for target in result.appliedTargets {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.agent.rawValue):\(target.source.path)")
            lines.append("Bindings applied: \(target.bindingCount)")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("Rollback: \(target.backupPath.map { "restore \($0)" } ?? "delete newly created file")")
            lines.append("")
        }

        if let report = result.verificationReport {
            lines.append("Verification:")
            lines.append(report.summaryText)
            if report.targets.contains(where: { $0.probeStatus != .notRun }) {
                lines.append(report.probeSummaryText)
            }
            lines.append("Note: this proves config files are parseable and contain the expected bindings; it does not prove each external agent is using the changed config.")
            lines.append("Verification matrix:")
            lines.append(contentsOf: AgentBulkConnectVerificationMatrixFormatter.markdownTableLines(for: report))
            for target in report.targets {
                lines.append("- \(target.agentName): \(target.status.rawValue) (\(target.presentBindingCount)/\(target.expectedBindingCount) bindings)")
                if !target.missingBindingNames.isEmpty {
                    lines.append("  Missing: \(target.missingBindingNames.joined(separator: ", "))")
                }
                lines.append("  \(target.message)")
                if target.probeStatus != .notRun {
                    lines.append("  Probe: \(target.probeStatus.rawValue) - \(target.probeMessage)")
                }
            }
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n")) + "\n"
    }

    private func runtimeStartResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let server = request.server else {
            return LocalControlResponse(error: "Missing server for runtime start")
        }
        guard let logDirectory = request.logDirectory, !logDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LocalControlResponse(error: "Missing log directory for runtime start")
        }

        do {
            let instance = try runtimeSupervisor.start(request: HubRuntimeLaunchRequest(server: server, logDirectory: logDirectory))
            return LocalControlResponse(runtimeInstance: instance)
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func runtimeStopResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let instance = request.runtimeInstance ?? request.runtimeInstanceID.map(Self.placeholderHubRuntimeInstance) else {
            return LocalControlResponse(error: "Missing runtime instance for runtime stop")
        }

        do {
            return LocalControlResponse(runtimeInstance: try runtimeSupervisor.stop(instance: instance))
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func runtimeRestartResponse(_ request: LocalControlRequest) -> LocalControlResponse {
        guard let instance = request.runtimeInstance ?? request.runtimeInstanceID.map(Self.placeholderHubRuntimeInstance) else {
            return LocalControlResponse(error: "Missing runtime instance for runtime restart")
        }
        guard let server = request.server else {
            return LocalControlResponse(error: "Missing server for runtime restart")
        }
        guard let logDirectory = request.logDirectory, !logDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LocalControlResponse(error: "Missing log directory for runtime restart")
        }

        do {
            let next = try runtimeSupervisor.restart(
                instance: instance,
                request: HubRuntimeLaunchRequest(server: server, logDirectory: logDirectory)
            )
            return LocalControlResponse(runtimeInstance: next)
        } catch {
            return LocalControlResponse(error: String(describing: error))
        }
    }

    private func runtimeExplanations(request: LocalControlRequest) -> [RuntimeLifecycleExplanation] {
        let scanResult = scan(request: request)
        let storedHubInstances = ((try? controlPlaneStore?.listRuntimeInstanceRecords(ownership: .hubOwned)) ?? [])
            .map(\.instance)
        return RuntimeLifecycleExplainer().explain(
            scanResult: scanResult,
            knownHubRuntimes: storedHubInstances,
            logDirectory: request.logDirectory
        )
    }

    private static func placeholderHubRuntimeInstance(id: String) -> RuntimeInstance {
        RuntimeInstance(
            id: id,
            ownership: .hubOwned,
            commandLine: "",
            status: .healthy
        )
    }
}
