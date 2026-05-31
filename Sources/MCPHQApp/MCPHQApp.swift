import SwiftUI
import MCPHQCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@main
struct MCPHQApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        Window("MCP-HQ", id: "dashboard") {
            DashboardView(model: model)
                .frame(minWidth: 840, minHeight: 560)
                .persistDashboardWindowFrame()
        }

        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            Label(model.statusMenuSnapshot.title, systemImage: model.statusMenuSnapshot.systemImage)
        }
    }
}

#if os(macOS)
private extension View {
    func persistDashboardWindowFrame() -> some View {
        background(
            DashboardWindowFrameAutosaveView(
                autosaveName: NativeAppPreferences.sanitizedWindowFrameAutosaveName(
                    NativeAppPreferences.dashboardWindowFrameAutosaveName
                )
            )
        )
    }
}

private struct DashboardWindowFrameAutosaveView: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAttached(nsView)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let name = NSWindow.FrameAutosaveName(autosaveName)
            guard window.frameAutosaveName != name else { return }
            _ = window.setFrameAutosaveName(name)
        }
    }
}
#endif

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState
    @Published private(set) var doctorReport: DoctorReport
    @Published private(set) var lastRefreshedText: String = "Not refreshed yet"
    @Published private(set) var isProbing: Bool = false
    @Published private(set) var actionMessage: String?
    @Published private(set) var recentHistorySummaries: [SQLiteScanHistoryRunSummary] = []
    @Published private(set) var controlHelperSnapshot: LocalControlHelperStatusSnapshot
    @Published private(set) var controlHelperInstallPreviewText: String?
    @Published private(set) var controlClientState: LocalControlClientState

    private let sourceProvider: DefaultConfigSourceProvider
    private let stateBuilder: DashboardStateBuilder
    private let doctorBuilder: DoctorReportBuilder
    private let scanCoordinator: ScanCoordinator
    private let scanResultStore: JSONScanResultStore?
    private let scanHistoryStore: SQLiteScanHistoryStore?
    private let keychainSecretStore: SecretStore?
    private let controlLaunchAgentManager: LocalControlLaunchAgentManager
    private let controlEndpointStore: LocalControlEndpointStore
    private let controlHelperPathResolver: LocalControlHelperPathResolver
    private let controlEndpointChecker: LocalControlEndpointChecker
    private let controlClientStateHelper: LocalControlClientStateHelper
    private var lastScanResult: ScanResult
    private var lastSecretRecoveryReport: SecretRecoveryReport?

    var statusMenuSnapshot: StatusMenuSnapshot {
        StatusMenuSnapshot(state: state, isProbing: isProbing)
    }

    private var preferredControlEndpointStore: LocalControlEndpointStore {
        Self.controlEndpointStore(from: .standard, fallback: controlEndpointStore)
    }

    private static func historyLimitPreference(defaults: UserDefaults = .standard) -> Int {
        guard let value = defaults.object(forKey: NativeAppPreferences.Key.defaultHistoryLimit) as? NSNumber else {
            return NativeAppPreferences.defaultHistoryLimit
        }
        return NativeAppPreferences.sanitizedHistoryLimit(value.intValue)
    }

    private static func probeOnRefreshPreference(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: NativeAppPreferences.Key.probeOnRefresh) != nil else {
            return NativeAppPreferences.defaultProbeOnRefresh
        }
        return defaults.bool(forKey: NativeAppPreferences.Key.probeOnRefresh)
    }

    private static func controlEndpointStore(
        from defaults: UserDefaults = .standard,
        fallback: LocalControlEndpointStore
    ) -> LocalControlEndpointStore {
        guard let rawPath = defaults.string(forKey: NativeAppPreferences.Key.controlEndpointFilePath) else {
            return fallback
        }
        return NativeAppPreferences.endpointStore(for: rawPath)
    }

    init(
        sourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        stateBuilder: DashboardStateBuilder = DashboardStateBuilder(),
        doctorBuilder: DoctorReportBuilder = DoctorReportBuilder(),
        scanCoordinator: ScanCoordinator = ScanCoordinator(secretStore: MacOSKeychainSecretStore()),
        scanResultStore: JSONScanResultStore? = try? JSONScanResultStore.applicationSupport(),
        scanHistoryStore: SQLiteScanHistoryStore? = try? SQLiteScanHistoryStore.applicationSupport(),
        keychainSecretStore: SecretStore? = MacOSKeychainSecretStore(),
        controlLaunchAgentManager: LocalControlLaunchAgentManager = LocalControlLaunchAgentManager(),
        controlEndpointStore: LocalControlEndpointStore = .defaultStore(),
        controlHelperPathResolver: LocalControlHelperPathResolver = LocalControlHelperPathResolver(),
        controlEndpointChecker: LocalControlEndpointChecker = LocalControlEndpointChecker(),
        controlClientStateHelper: LocalControlClientStateHelper = LocalControlClientStateHelper()
    ) {
        self.sourceProvider = sourceProvider
        self.stateBuilder = stateBuilder
        self.doctorBuilder = doctorBuilder
        self.scanCoordinator = scanCoordinator
        self.scanResultStore = scanResultStore
        self.scanHistoryStore = scanHistoryStore
        self.keychainSecretStore = keychainSecretStore
        self.controlLaunchAgentManager = controlLaunchAgentManager
        self.controlEndpointStore = controlEndpointStore
        self.controlHelperPathResolver = controlHelperPathResolver
        self.controlEndpointChecker = controlEndpointChecker
        self.controlClientStateHelper = controlClientStateHelper
        let emptyResult = ScanResult(servers: [], sources: [], issues: [])
        let stored = try? scanResultStore?.load()
        let storedHistory = try? scanHistoryStore?.loadLatest()
        let initialResult = stored?.result ?? storedHistory?.result ?? emptyResult
        let initialDoctorReport: DoctorReport
        if let keychainSecretStore {
            do {
                let validatedAt = Date()
                let persistedReport = try scanHistoryStore?.validateSecretBindings(
                    store: keychainSecretStore,
                    validatedAt: validatedAt
                ) ?? SecretRecoveryReport(states: [])
                let persistedIDs = Set(persistedReport.states.compactMap(\.secretID))
                let currentRecords = Self.currentKeychainReferenceRecords(
                    from: initialResult.servers,
                    updatedAt: validatedAt
                ).filter { !persistedIDs.contains($0.secretID) }
                let currentReport = SecretRecoveryReporter(store: keychainSecretStore).report(
                    records: currentRecords,
                    validatedAt: validatedAt
                )
                initialDoctorReport = doctorBuilder.build(
                    from: initialResult,
                    keychainRecoveryReport: SecretRecoveryReport(states: persistedReport.states + currentReport.states)
                )
            } catch {
                initialDoctorReport = doctorBuilder.build(from: initialResult)
            }
        } else {
            initialDoctorReport = doctorBuilder.build(from: initialResult)
        }
        self.lastScanResult = initialResult
        self.state = stateBuilder.build(from: initialResult)
        self.doctorReport = initialDoctorReport
        let initialEndpointStore = Self.controlEndpointStore(from: .standard, fallback: controlEndpointStore)
        let initialLaunchAgentStatus = controlLaunchAgentManager.status(endpointStore: initialEndpointStore, checkLaunchd: false)
        self.controlHelperSnapshot = LocalControlHelperStatusSnapshot(
            launchAgentStatus: initialLaunchAgentStatus,
            helperPath: controlHelperPathResolver.resolve(),
            endpointAvailability: LocalControlEndpointAvailability.metadataOnly(initialLaunchAgentStatus.endpoint)
        )
        self.controlClientState = controlClientStateHelper.state(endpointStore: initialEndpointStore)
        if let scannedAt = stored?.scannedAt ?? storedHistory?.scannedAt {
            self.lastRefreshedText = Self.relativeRefreshText(date: scannedAt)
        }
        refreshHistorySummaries()
        refresh()
    }

    func refresh() {
        if Self.probeOnRefreshPreference() {
            runProbes()
            return
        }

        let request = dashboardScanRequest(includeProbes: false)
        let endpointStore = preferredControlEndpointStore
        let router = localControlRouter()
        do {
            let exchange = try controlClientStateHelper.sendPreferringEndpoint(
                request,
                endpointStore: endpointStore
            ) {
                router.handle(request)
            }
            controlClientState = exchange.state
            if let error = exchange.response.error {
                actionMessage = "Refresh failed: \(error)"
                return
            }
            guard let result = exchange.response.scanResult else {
                actionMessage = "Refresh failed: missing scan response"
                return
            }
            lastScanResult = result
            state = stateBuilder.build(from: result)
            doctorReport = buildDoctorReport(from: result)
            let refreshedAt = Date()
            persist(result, scannedAt: refreshedAt)
            rerunKeychainValidation(reportsSuccess: false)
            lastRefreshedText = Self.relativeRefreshText(date: refreshedAt)
            refreshHistorySummaries()
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlClientState = controlClientStateHelper.state(endpointStore: endpointStore)
            actionMessage = "Refresh failed: \(message)"
        }
    }

    @discardableResult
    func runProbes(completionMessage: String? = nil) -> Bool {
        guard !isProbing else { return false }
        isProbing = true
        let request = dashboardScanRequest(includeProbes: true)
        let endpointStore = preferredControlEndpointStore
        let clientStateHelper = controlClientStateHelper
        let router = localControlRouter()
        let stateBuilder = stateBuilder
        let scanResultStore = scanResultStore
        let scanHistoryStore = scanHistoryStore
        Task.detached(priority: .userInitiated) {
            do {
                let exchange = try clientStateHelper.sendPreferringEndpoint(
                    request,
                    endpointStore: endpointStore
                ) {
                    router.handle(request)
                }
                if let error = exchange.response.error {
                    await MainActor.run {
                        self.controlClientState = exchange.state
                        self.actionMessage = "Probe refresh failed: \(error)"
                        self.isProbing = false
                    }
                    return
                }
                guard let result = exchange.response.scanResult else {
                    await MainActor.run {
                        self.controlClientState = exchange.state
                        self.actionMessage = "Probe refresh failed: missing scan response"
                        self.isProbing = false
                    }
                    return
                }
                let nextState = stateBuilder.build(from: result)
                let nextDoctorReport = await MainActor.run { self.buildDoctorReport(from: result) }
                let refreshedAt = Date()
                Self.persist(result, scannedAt: refreshedAt, cache: scanResultStore, history: scanHistoryStore)
                await MainActor.run {
                    self.controlClientState = exchange.state
                    self.lastScanResult = result
                    self.state = nextState
                    self.doctorReport = nextDoctorReport
                    self.rerunKeychainValidation(reportsSuccess: false)
                    self.lastRefreshedText = Self.relativeRefreshText(date: refreshedAt)
                    self.isProbing = false
                    if let completionMessage {
                        self.actionMessage = completionMessage
                    }
                    self.refreshHistorySummaries()
                }
            } catch {
                let message = SecretRedactor.redactText(String(describing: error))
                await MainActor.run {
                    self.controlClientState = clientStateHelper.state(endpointStore: endpointStore)
                    self.actionMessage = "Probe refresh failed: \(message)"
                    self.isProbing = false
                }
            }
        }
        return true
    }

    private func dashboardScanRequest(includeProbes: Bool) -> LocalControlRequest {
        LocalControlRequest(
            route: .scan,
            includeProbes: includeProbes,
            targetSources: sourceProvider.sources()
        )
    }

    private func localControlRouter() -> LocalControlRouter {
        LocalControlRouter(
            defaultSourceProvider: sourceProvider,
            scanCoordinator: scanCoordinator,
            doctorBuilder: doctorBuilder,
            controlPlaneStore: scanHistoryStore
        )
    }

    func rerunKeychainValidation(reportsSuccess: Bool = true) {
        guard let keychainSecretStore else {
            lastSecretRecoveryReport = nil
            state = stateBuilder.build(from: lastScanResult)
            if reportsSuccess {
                actionMessage = "Keychain validation unavailable"
            }
            return
        }

        do {
            let validatedAt = Date()
            let persistedReport = try scanHistoryStore?.validateSecretBindings(store: keychainSecretStore, validatedAt: validatedAt)
                ?? SecretRecoveryReport(states: [])
            let persistedIDs = Set(persistedReport.states.compactMap(\.secretID))
            let currentRecords = Self.currentKeychainReferenceRecords(from: lastScanResult.servers, updatedAt: validatedAt)
                .filter { !persistedIDs.contains($0.secretID) }
            let currentReport = SecretRecoveryReporter(store: keychainSecretStore).report(records: currentRecords, validatedAt: validatedAt)
            let report = SecretRecoveryReport(states: persistedReport.states + currentReport.states)
            lastSecretRecoveryReport = report
            state = stateBuilder.build(from: lastScanResult, secretRecoveryReport: report)
            if reportsSuccess {
                if report.checkedCount == 0 {
                    actionMessage = "No Keychain references found to validate"
                } else if report.recoverableStates.isEmpty {
                    actionMessage = "Keychain validation complete: \(report.checkedCount) checked, all present"
                } else {
                    actionMessage = "Keychain validation complete: \(report.missingCount) missing, \(report.inaccessibleCount) inaccessible, \(report.migrationWriteFailureCount) migration write failed"
                }
            }
        } catch {
            lastSecretRecoveryReport = nil
            state = stateBuilder.build(from: lastScanResult)
            if reportsSuccess {
                actionMessage = "Keychain validation failed: \(SecretRedactor.redactText(String(describing: error)))"
            }
        }
    }

    func cleanupMigrationWriteFailedKeychainReferences(for row: DashboardKeychainRecoveryRow) {
        guard let keychainSecretStore else {
            actionMessage = "Migration cleanup unavailable; keychain store unavailable"
            return
        }

        guard let report = lastSecretRecoveryReport else {
            actionMessage = "Validate Keychain before attempting cleanup"
            rerunKeychainValidation()
            return
        }

        let plan = SecretMigrationWriteFailureRecoveryService()
            .plan(for: report.recoverableStates, secretIDs: Set([row.id]))
        guard plan.canRetry else {
            actionMessage = "No migration-write-failed references are pending cleanup for this row."
            return
        }

        actionMessage = plan.previewMessage
        do {
            let result = try SecretMigrationWriteFailureRecoveryService().execute(plan: plan, store: keychainSecretStore)
            actionMessage = result.attemptedReferenceCount == 0 ? plan.previewMessage : result.message
            rerunKeychainValidation(reportsSuccess: false)
        } catch {
            actionMessage = "Migration cleanup failed: \(SecretRedactor.redactText(String(describing: error)))"
            rerunKeychainValidation(reportsSuccess: false)
        }
    }

    private static func currentKeychainReferenceRecords(from servers: [ServerDefinition], updatedAt: Date) -> [SQLiteSecretBindingRecord] {
        servers.flatMap { server -> [SQLiteSecretBindingRecord] in
            let envRecords = server.envBindings.keys.sorted().compactMap { key -> SQLiteSecretBindingRecord? in
                guard let value = server.envBindings[key],
                      let reference = KeychainSecretReference.parse(from: value) else { return nil }
                return SQLiteSecretBindingRecord(
                    secretID: "\(server.id):\(SecretFieldKind.environment.rawValue):\(key)",
                    sourcePath: server.sourcePath,
                    serverName: server.displayName,
                    fieldKind: .environment,
                    fieldName: key,
                    reference: reference,
                    status: "configured",
                    updatedAt: updatedAt,
                    validatedAt: nil
                )
            }
            let headerRecords = server.headers.keys.sorted().compactMap { key -> SQLiteSecretBindingRecord? in
                guard let value = server.headers[key],
                      let reference = KeychainSecretReference.parse(from: value) else { return nil }
                return SQLiteSecretBindingRecord(
                    secretID: "\(server.id):\(SecretFieldKind.header.rawValue):\(key)",
                    sourcePath: server.sourcePath,
                    serverName: server.displayName,
                    fieldKind: .header,
                    fieldName: key,
                    reference: reference,
                    status: "configured",
                    updatedAt: updatedAt,
                    validatedAt: nil
                )
            }
            return envRecords + headerRecords
        }
    }

    func refreshHistorySummaries(limit: Int? = nil, reportsSuccess: Bool = false) {
        guard let scanHistoryStore else {
            recentHistorySummaries = []
            actionMessage = "Scan history store unavailable"
            return
        }

        let resolvedLimit = NativeAppPreferences.sanitizedHistoryLimit(limit ?? Self.historyLimitPreference())
        do {
            recentHistorySummaries = try scanHistoryStore.listRunSummaries(limit: resolvedLimit)
            if reportsSuccess {
                actionMessage = recentHistorySummaries.isEmpty
                    ? "No scan history found"
                    : "Loaded \(recentHistorySummaries.count) history run\(recentHistorySummaries.count == 1 ? "" : "s")"
            }
        } catch {
            recentHistorySummaries = []
            actionMessage = "History load failed: \(SecretRedactor.redactText(String(describing: error)))"
        }
    }

    func historyRunDetail(summary: SQLiteScanHistoryRunSummary) -> ScanHistoryRunDetailState {
        guard let scanHistoryStore else {
            return ScanHistoryRunDetailState(
                runID: summary.runID,
                scannedAt: summary.scannedAt,
                title: "History Unavailable",
                subtitle: summary.runID,
                text: "Scan history store unavailable.",
                jsonText: nil
            )
        }

        do {
            guard let stored = try scanHistoryStore.load(runID: summary.runID) else {
                return ScanHistoryRunDetailState(
                    runID: summary.runID,
                    scannedAt: summary.scannedAt,
                    title: "History Run Missing",
                    subtitle: summary.runID,
                    text: "No scan history row exists for this run ID.",
                    jsonText: nil
                )
            }
            let storedDoctorReport = try scanHistoryStore.loadDoctorReport(runID: summary.runID)
            return try ScanHistoryRunDetailState(
                runID: summary.runID,
                stored: stored,
                storedDoctorReport: storedDoctorReport
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "History detail load failed: \(message)"
            return ScanHistoryRunDetailState(
                runID: summary.runID,
                scannedAt: summary.scannedAt,
                title: "History Load Failed",
                subtitle: summary.runID,
                text: message,
                jsonText: nil
            )
        }
    }

    func copyHistoryRunDetail(_ detail: ScanHistoryRunDetailState, format: ScanHistoryRunDetailFormat) {
        guard let text = detail.text(for: format) else {
            actionMessage = "History \(format.label) detail unavailable"
            return
        }
        copyText(text)
        actionMessage = "Copied history \(format.label)"
    }

    func copyInspectorText(_ text: String, label: String) {
        let redactedText = SecretRedactor.redactText(text)
        guard !redactedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            actionMessage = "Nothing to copy for \(label)"
            return
        }
        copyText(redactedText)
        actionMessage = "Copied \(label)"
    }

    func exportHistoryRunDetail(_ detail: ScanHistoryRunDetailState, format: ScanHistoryRunDetailFormat) {
        do {
            guard let text = detail.text(for: format) else {
                actionMessage = "History \(format.label) detail unavailable"
                return
            }
            guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                actionMessage = "Could not find Application Support"
                return
            }
            let historyDirectory = directory.appendingPathComponent("MCP-HQ", isDirectory: true)
            try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
            let url = historyDirectory.appendingPathComponent(detail.fileName(for: format))
            try text.write(to: url, atomically: true, encoding: .utf8)
            actionMessage = "Exported history \(format.label) \(url.path)"
        } catch {
            actionMessage = "History export failed: \(SecretRedactor.redactText(String(describing: error)))"
        }
    }

    func configPreview(for detail: DashboardServerDetail) -> ConfigPreviewSheetState {
        guard let source = source(for: detail.sourcePath) else {
            return ConfigPreviewSheetState(
                title: "Config Preview Unavailable",
                subtitle: detail.sourcePath,
                text: "MCP-HQ could not find the scanned source for this server.",
                canApply: false
            )
        }
        return configPreview(for: source)
    }

    func configPreview(sourcePath: String) -> ConfigPreviewSheetState {
        guard let source = source(for: sourcePath) else {
            return ConfigPreviewSheetState(
                title: "Config Preview Unavailable",
                subtitle: sourcePath,
                text: "Source config was not found in the latest scan. Refresh, then try again.",
                canApply: false
            )
        }
        return configPreview(for: source)
    }

    func configPreview(for source: ConfigSource) -> ConfigPreviewSheetState {
        do {
            let servers = lastScanResult.servers.filter { $0.sourcePath == source.path }
            guard !servers.isEmpty else {
                return ConfigPreviewSheetState(
                    title: "Config Preview Unavailable",
                    subtitle: "\(source.agent.rawValue):\(source.path)",
                    text: "This source has no parsed MCP servers to render.",
                    canApply: false
                )
            }
            let preview = try AgentConfigSafeApplier().preview(source: source, servers: servers)
            let displayDiff = redactedConfigText(preview.diffText, servers: servers)
            let displayRendered = redactedConfigText(preview.renderedText, servers: servers)
            let displayVisualDiff = redactedVisualDiffLines(preview.visualDiffLines, servers: servers)
            return ConfigPreviewSheetState(
                title: "Config Preview",
                subtitle: "\(source.agent.rawValue):\(source.path)",
                text: [
                    "Target: \(source.agent.rawValue):\(source.path)",
                    "Reparsed servers: \(preview.reparsedServers.count)",
                    "",
                    "Diff:",
                    displayDiff,
                    "",
                    "Generated config:",
                    displayRendered,
                ].joined(separator: "\n"),
                targetSource: source,
                servers: servers,
                renderedText: displayRendered,
                diffText: displayDiff,
                visualDiffLines: displayVisualDiff,
                backupPath: nil,
                canApply: true
            )
        } catch {
            return ConfigPreviewSheetState(
                title: "Config Preview Failed",
                subtitle: source.path,
                text: SecretRedactor.redactText(String(describing: error)),
                canApply: false
            )
        }
    }

    func applyConfigPreview(_ preview: ConfigPreviewSheetState) -> ConfigPreviewSheetState {
        guard let source = preview.targetSource, !preview.servers.isEmpty else {
            actionMessage = "Config apply unavailable"
            return ConfigPreviewSheetState(
                title: "Config Apply Unavailable",
                subtitle: preview.subtitle,
                text: "This preview does not include a writable target and parsed server set.",
                canApply: false
            )
        }

        do {
            let result = try AgentConfigSafeApplier().apply(source: source, servers: preview.servers, dryRun: false)
            let backupLine = result.backupPath ?? "none"
            actionMessage = "Config applied; backup: \(backupLine)"
            let displayDiff = redactedConfigText(result.preview.diffText, servers: preview.servers)
            let displayRendered = redactedConfigText(result.preview.renderedText, servers: preview.servers)
            let displayVisualDiff = redactedVisualDiffLines(result.preview.visualDiffLines, servers: preview.servers)
            refresh()
            return ConfigPreviewSheetState(
                title: "Config Applied",
                subtitle: "\(source.agent.rawValue):\(source.path)",
                text: [
                    "Target: \(source.agent.rawValue):\(source.path)",
                    "Did write: \(result.didWrite ? "yes" : "no")",
                    "Backup: \(backupLine)",
                    "Reparsed servers: \(result.preview.reparsedServers.count)",
                    "",
                    "Diff:",
                    displayDiff,
                    "",
                    "Generated config:",
                    displayRendered,
                ].joined(separator: "\n"),
                targetSource: source,
                servers: preview.servers,
                renderedText: displayRendered,
                diffText: displayDiff,
                visualDiffLines: displayVisualDiff,
                backupPath: result.backupPath,
                canApply: false,
                canRollback: result.backupPath != nil
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Config apply failed: \(message)"
            return ConfigPreviewSheetState(
                title: "Config Apply Failed",
                subtitle: preview.subtitle,
                text: message,
                targetSource: source,
                servers: preview.servers,
                canApply: true
            )
        }
    }

    func rollbackConfig(_ preview: ConfigPreviewSheetState) -> ConfigPreviewSheetState {
        guard let source = preview.targetSource, let backupPath = preview.backupPath else {
            actionMessage = "Config rollback unavailable"
            return preview
        }

        do {
            let backupURL = URL(fileURLWithPath: backupPath)
            let targetURL = URL(fileURLWithPath: source.path)
            let data = try Data(contentsOf: backupURL)
            try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
            _ = try AgentConfigParser().parse(data: data, source: source)
            try data.write(to: targetURL, options: [.atomic])
            actionMessage = "Rolled back \(source.path)"
            refresh()
            return ConfigPreviewSheetState(
                title: "Config Rolled Back",
                subtitle: "\(source.agent.rawValue):\(source.path)",
                text: [
                    "Target: \(source.agent.rawValue):\(source.path)",
                    "Restored from: \(backupPath)",
                    "",
                    "MCP-HQ validated and restored the backup file.",
                ].joined(separator: "\n"),
                targetSource: source,
                servers: [],
                backupPath: backupPath,
                canApply: false,
                canRollback: false
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Config rollback failed: \(message)"
            return ConfigPreviewSheetState(
                title: "Config Rollback Failed",
                subtitle: preview.subtitle,
                text: message,
                targetSource: source,
                servers: preview.servers,
                backupPath: backupPath,
                canApply: false,
                canRollback: true
            )
        }
    }

    func migrateSecrets(for detail: DashboardServerDetail) {
        do {
            guard let source = source(for: detail.sourcePath) else {
                actionMessage = "Secret migration failed: source unavailable"
                return
            }
            var servers = lastScanResult.servers.filter { $0.sourcePath == detail.sourcePath }
            guard let serverIndex = servers.firstIndex(where: { $0.id == detail.id }) else {
                actionMessage = "Secret migration failed: server unavailable"
                return
            }

            let detector = SecretDetector()
            let detected = detector.detect(in: servers[serverIndex])
            guard !detected.isEmpty else {
                actionMessage = "No literal secrets to migrate"
                return
            }

            let store = MacOSKeychainSecretStore()
            let migration = try detector.migrating(servers[serverIndex], store: store)
            guard !migration.storedReferences.isEmpty else {
                actionMessage = "No literal secrets to migrate"
                return
            }
            servers[serverIndex] = migration.migratedServer

            let result = try AgentConfigSafeApplier().apply(source: source, servers: servers, dryRun: false)
            try scanHistoryStore?.upsertSecretBindings(detected, status: "present", validatedAt: Date())
            actionMessage = "Migrated \(migration.storedReferences.count) secret\(migration.storedReferences.count == 1 ? "" : "s"); backup: \(result.backupPath ?? "none")"
            refresh()
        } catch let failure as SecretMigrationWriteFailure {
            let store = MacOSKeychainSecretStore()
            for reference in failure.storedReferences {
                try? store.deleteSecret(for: reference)
            }
            try? scanHistoryStore?.upsertSecretBindings(
                failure.failedAndPendingSecrets,
                status: SecretRecoveryStatus.migrationWriteFailed.rawValue,
                updatedAt: Date(),
                validatedAt: Date()
            )
            actionMessage = "Secret migration failed during Keychain write: \(SecretRedactor.redactText(String(describing: failure)))"
            refresh()
        } catch {
            actionMessage = "Secret migration failed: \(SecretRedactor.redactText(String(describing: error)))"
        }
    }

    func copyDoctorReport(_ report: DoctorReport? = nil) {
        copyText(DoctorReportFormatter().formatText(report ?? doctorReport))
        actionMessage = "Doctor report copied"
    }

    func copyDoctorFinding(_ finding: DoctorFinding) {
        let source = finding.sourcePath.isEmpty ? "unknown" : finding.sourcePath
        let server = finding.serverName ?? "unknown"
        let findingText = [
            "Doctor Finding",
            "Source: \(source)",
            "Server: \(server)",
            "Severity: \(finding.severity.rawValue)",
            "Category: \(finding.category.rawValue)",
            "Title: \(finding.title)",
            "Why: \(finding.whyItMatters)",
            "Fix: \(finding.suggestedFix)",
        ].joined(separator: "\n")
        copyText(SecretRedactor.redactText(findingText))
        actionMessage = "Doctor finding copied"
    }

    private func buildDoctorReport(from result: ScanResult) -> DoctorReport {
        guard let keychainSecretStore else {
            return doctorBuilder.build(from: result)
        }

        do {
            let validatedAt = Date()
            let persistedReport = try scanHistoryStore?.validateSecretBindings(
                store: keychainSecretStore,
                validatedAt: validatedAt
            ) ?? SecretRecoveryReport(states: [])
            let persistedIDs = Set(persistedReport.states.compactMap(\.secretID))
            let currentRecords = Self.currentKeychainReferenceRecords(
                from: result.servers,
                updatedAt: validatedAt
            ).filter { !persistedIDs.contains($0.secretID) }
            let currentReport = SecretRecoveryReporter(store: keychainSecretStore).report(
                records: currentRecords,
                validatedAt: validatedAt
            )
            return doctorBuilder.build(
                from: result,
                keychainRecoveryReport: SecretRecoveryReport(states: persistedReport.states + currentReport.states)
            )
        } catch {
            return doctorBuilder.build(from: result)
        }
    }

    func exportDoctorReport(_ report: DoctorReport? = nil, format: DoctorReportExportFormat = .text) {
        do {
            guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                actionMessage = "Could not find Application Support"
                return
            }
            let reportDirectory = directory.appendingPathComponent("MCP-HQ", isDirectory: true)
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            let reportURL = reportDirectory.appendingPathComponent(format.fileName)
            try DoctorReportExporter().write(report ?? doctorReport, format: format, to: reportURL)
            actionMessage = "Exported \(format.label) \(reportURL.path)"
        } catch {
            actionMessage = "Export failed: \(SecretRedactor.redactText(String(describing: error)))"
        }
    }

    func saveDoctorReportAs(_ report: DoctorReport? = nil, format: DoctorReportExportFormat = .text) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = "Save Doctor Report"
        panel.message = "Choose where to save a redacted MCP-HQ Doctor report."
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = format.fileName
        panel.allowedContentTypes = [format.contentType]

        guard panel.runModal() == .OK, let url = panel.url else {
            actionMessage = "Doctor report save canceled"
            return
        }

        do {
            try DoctorReportExporter().write(report ?? doctorReport, format: format, to: url)
            actionMessage = "Saved \(format.label) \(url.path)"
        } catch {
            actionMessage = "Save failed: \(SecretRedactor.redactText(String(describing: error)))"
        }
        #else
        exportDoctorReport(report, format: format)
        #endif
    }

    func configPreview(for finding: DoctorFinding) -> ConfigPreviewSheetState {
        if let serverID = finding.serverID,
           let detail = state.serverDetails.first(where: { $0.id == serverID }) {
            return configPreview(for: detail)
        }
        guard let source = source(for: finding.sourcePath) else {
            return ConfigPreviewSheetState(
                title: "Config Preview Unavailable",
                subtitle: finding.sourcePath,
                text: "MCP-HQ could not find the scanned source for this Doctor finding.",
                canApply: false
            )
        }
        return configPreview(for: source)
    }

    func openConfigSource(for finding: DoctorFinding) {
        guard let source = source(for: finding.sourcePath) else {
            actionMessage = "Config source unavailable: \(finding.sourcePath)"
            return
        }
        openConfigSource(source)
    }

    func copyConfigPreview(_ preview: ConfigPreviewSheetState) {
        copyText(preview.text)
        actionMessage = "Config preview copied"
    }

    func openConfigSource(_ source: ConfigSource) {
        #if os(macOS)
        let url = URL(fileURLWithPath: source.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            actionMessage = "Config file is missing: \(source.path)"
            return
        }
        NSWorkspace.shared.open(url)
        actionMessage = "Opened \(source.path)"
        #else
        actionMessage = "Opening config files is only available on macOS"
        #endif
    }

    func refreshControlHelperStatus(checkLaunchd: Bool = true, checkEndpoint: Bool = true) {
        let endpointStore = preferredControlEndpointStore
        let launchAgentStatus = controlLaunchAgentManager.status(
            endpointStore: endpointStore,
            checkLaunchd: checkLaunchd
        )
        let endpointAvailability = checkEndpoint
            ? controlEndpointChecker.check(endpointStore: endpointStore)
            : LocalControlEndpointAvailability.metadataOnly(launchAgentStatus.endpoint)
        controlHelperSnapshot = LocalControlHelperStatusSnapshot(
            launchAgentStatus: launchAgentStatus,
            helperPath: controlHelperPathResolver.resolve(),
            endpointAvailability: endpointAvailability
        )
        actionMessage = "Control helper status refreshed"
    }

    func previewControlHelperLaunchAgentInstall() {
        do {
            let configuration = controlHelperLaunchAgentConfiguration()
            let result = try controlLaunchAgentManager.install(configuration, dryRun: true)
            controlHelperInstallPreviewText = controlHelperInstallText(result, title: "LaunchAgent install preview")
            actionMessage = "Control helper install preview generated"
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlHelperInstallPreviewText = message
            actionMessage = "Control helper preview failed: \(message)"
        }
    }

    func installControlHelperLaunchAgentPlist() {
        guard controlHelperSnapshot.canInstallPlist else {
            actionMessage = controlHelperSnapshot.installDisabledReason
            return
        }

        do {
            let configuration = controlHelperLaunchAgentConfiguration()
            let result = try controlLaunchAgentManager.install(configuration, dryRun: false)
            controlHelperInstallPreviewText = controlHelperInstallText(result, title: "LaunchAgent plist installed")
            refreshControlHelperStatus(checkLaunchd: false, checkEndpoint: false)
            actionMessage = "Installed LaunchAgent plist only; launchctl bootstrap was not run"
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlHelperInstallPreviewText = message
            actionMessage = "Control helper install failed: \(message)"
        }
    }

    func installAndBootstrapControlHelperLaunchAgent() {
        guard controlHelperSnapshot.canInstallAndBootstrap else {
            actionMessage = controlHelperSnapshot.installAndBootstrapDisabledReason
            return
        }

        do {
            let configuration = controlHelperLaunchAgentConfiguration()
            let installResult = try controlLaunchAgentManager.install(configuration, dryRun: false)
            let bootstrapResult = try controlLaunchAgentManager.bootstrap()
            controlHelperInstallPreviewText = [
                controlHelperInstallText(installResult, title: "LaunchAgent plist installed"),
                controlHelperCommandText(bootstrapResult, title: "LaunchAgent bootstrap")
            ].joined(separator: "\n")
            refreshControlHelperStatus(checkLaunchd: true, checkEndpoint: true)
            actionMessage = bootstrapResult.exitCode == 0
                ? "Control helper installed and started"
                : "Control helper installed; bootstrap exited \(bootstrapResult.exitCode)"
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlHelperInstallPreviewText = message
            actionMessage = "Control helper install/start failed: \(message)"
        }
    }

    func bootstrapControlHelperLaunchAgent() {
        guard controlHelperSnapshot.canBootstrap else {
            actionMessage = controlHelperSnapshot.bootstrapDisabledReason
            return
        }

        do {
            let result = try controlLaunchAgentManager.bootstrap()
            controlHelperInstallPreviewText = controlHelperCommandText(result, title: "LaunchAgent bootstrap")
            refreshControlHelperStatus(checkLaunchd: true, checkEndpoint: true)
            actionMessage = result.exitCode == 0
                ? "Control helper bootstrap command completed"
                : "Control helper bootstrap exited \(result.exitCode)"
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlHelperInstallPreviewText = message
            actionMessage = "Control helper bootstrap failed: \(message)"
        }
    }

    func bootoutControlHelperLaunchAgent() {
        guard controlHelperSnapshot.canBootout else {
            actionMessage = controlHelperSnapshot.bootoutDisabledReason
            return
        }

        do {
            let result = try controlLaunchAgentManager.bootout()
            controlHelperInstallPreviewText = controlHelperCommandText(result, title: "LaunchAgent bootout")
            refreshControlHelperStatus(checkLaunchd: true, checkEndpoint: true)
            actionMessage = result.exitCode == 0
                ? "Control helper bootout command completed"
                : "Control helper bootout exited \(result.exitCode)"
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            controlHelperInstallPreviewText = message
            actionMessage = "Control helper bootout failed: \(message)"
        }
    }

    func runtimeLifecyclePanelState() -> RuntimeLifecyclePanelState {
        let storedHubInstances = ((try? scanHistoryStore?.listRuntimeInstanceRecords(ownership: .hubOwned)) ?? [])
            .map(\.instance)
        let explanations = RuntimeLifecycleExplainer().explain(
            scanResult: lastScanResult,
            knownHubRuntimes: storedHubInstances
        )
        return RuntimeLifecyclePanelStateBuilder(
            controlPlaneAvailability: RuntimeLifecycleControlPlaneAvailability(
                endpointAvailability: controlHelperSnapshot.endpointAvailability
            )
        ).build(from: explanations)
    }

    func copyRuntimeLifecyclePanel(_ state: RuntimeLifecyclePanelState) {
        copyText(RuntimeLifecyclePanelFormatter().formatText(state))
        actionMessage = "Runtime lifecycle summary copied"
    }

    func copyRuntimeLifecycleAction(_ action: RuntimeLifecycleSafeAction) {
        copyText(action.textToCopy)
        actionMessage = "Copied \(action.title.lowercased())"
    }

    func runtimeLaunchCandidates() -> [RuntimeLaunchCandidate] {
        RuntimeLaunchCandidateBuilder().build(from: lastScanResult)
    }

    func defaultRuntimeLogDirectoryPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MCP-HQ", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .path
    }

    func startHubRuntime(serverID: String, logDirectory: String) {
        guard let server = lastScanResult.servers.first(where: { $0.id == serverID }) else {
            actionMessage = "Runtime start failed: configured server is no longer in the latest scan"
            return
        }
        sendRuntimeControl(
            request: LocalControlRequest(route: .runtimeStart, server: server, logDirectory: logDirectory),
            progressMessage: "Starting \(server.displayName)...",
            successVerb: "Started"
        )
    }

    func stopHubRuntime(_ runtimeInstanceID: String) {
        sendRuntimeControl(
            request: LocalControlRequest(route: .runtimeStop, runtimeInstanceID: runtimeInstanceID),
            progressMessage: "Stopping \(runtimeInstanceID)...",
            successVerb: "Stopped"
        )
    }

    func restartHubRuntime(runtimeInstanceID: String, serverID: String?, logDirectory: String) {
        guard let serverID,
              let server = lastScanResult.servers.first(where: { $0.id == serverID }) else {
            actionMessage = "Runtime restart failed: matching configured server is no longer in the latest scan"
            return
        }
        sendRuntimeControl(
            request: LocalControlRequest(
                route: .runtimeRestart,
                runtimeInstanceID: runtimeInstanceID,
                server: server,
                logDirectory: logDirectory
            ),
            progressMessage: "Restarting \(runtimeInstanceID)...",
            successVerb: "Restarted"
        )
    }

    private func sendRuntimeControl(request: LocalControlRequest, progressMessage: String, successVerb: String) {
        let endpointStore = preferredControlEndpointStore
        actionMessage = progressMessage
        Task.detached(priority: .userInitiated) {
            do {
                let response = try LocalControlHTTPClient(endpointStore: endpointStore).send(request)
                if let error = response.error {
                    await MainActor.run { self.actionMessage = "Runtime control failed: \(error)" }
                    return
                }
                guard let instance = response.runtimeInstance else {
                    await MainActor.run { self.actionMessage = "Runtime control failed: missing runtime response" }
                    return
                }
                await MainActor.run {
                    self.actionMessage = "\(successVerb) \(instance.id)"
                    self.refreshHistorySummaries()
                    self.refresh()
                }
            } catch {
                let message = SecretRedactor.redactText(String(describing: error))
                await MainActor.run { self.actionMessage = "Runtime control failed: \(message)" }
            }
        }
    }

    func configManagerState() -> ConfigManagerState {
        let sourceLookup = Dictionary(uniqueKeysWithValues: lastScanResult.sourceHealth.map { ($0.source.path, $0.source) })
        let fallbackSources = Dictionary(uniqueKeysWithValues: lastScanResult.sources.map { ($0.path, $0) })
        let serversBySource = Dictionary(grouping: lastScanResult.servers, by: \.sourcePath)
        let issuesBySource = Dictionary(grouping: lastScanResult.issues, by: { $0.source.path })
        let detector = SecretDetector()
        let agentRegistry = AgentRegistry.default()
        let desiredStates = (try? scanHistoryStore?.listDesiredServerStates()) ?? []
        let canonicalSnapshot = AgentCanonicalConfigManagerSnapshot(
            model: AgentCanonicalAuthoringModel(scanResult: lastScanResult, desiredStates: desiredStates)
        )

        let sources = state.sourceRows.map { row -> ConfigManagerSourceRow in
            let source = sourceLookup[row.sourcePath] ?? fallbackSources[row.sourcePath] ?? ConfigSource(agent: .unknown, path: row.sourcePath)
            let servers = serversBySource[row.sourcePath] ?? []
            let secretCount = servers.reduce(0) { $0 + detector.detect(in: $1).count }
            let issueCount = issuesBySource[row.sourcePath]?.count ?? 0
            let fileExists = FileManager.default.fileExists(atPath: row.sourcePath)
            let readiness = agentRegistry.readiness(for: source, fileExists: fileExists)
            return ConfigManagerSourceRow(
                id: row.id,
                source: source,
                agentName: row.agentName,
                stateLabel: row.stateLabel,
                serverCount: row.serverCount,
                issueCount: issueCount,
                literalSecretCount: secretCount,
                message: row.message,
                readinessLabel: readiness.label,
                readinessDetail: readiness.detail,
                canCreateWithBindingDraft: readiness.canCreateWithBindingDraft,
                sourcePath: row.sourcePath,
                canPreview: !servers.isEmpty,
                canOpen: fileExists
            )
        }
        let scannedBindings = Dictionary(grouping: lastScanResult.servers) { server in
            AgentBindingDesiredStateIndex.normalizedName(server.displayName)
        }
        let bindings = canonicalSnapshot.bindingRows.compactMap { canonicalRow -> ConfigManagerBindingRow? in
            let servers = scannedBindings[canonicalRow.normalizedName] ?? []
            let first = canonicalRow.templateServer
            let sourcePaths = Set(canonicalRow.sourceRows.map(\.sourcePath)).union(servers.map(\.sourcePath))
            let issueCount = sourcePaths.reduce(0) { total, path in
                total + (issuesBySource[path]?.count ?? 0)
            }
            let serverSecretRows = servers
                .map { server -> ConfigManagerServerSecretRow in
                    let source = sourceLookup[server.sourcePath] ?? fallbackSources[server.sourcePath]
                    return ConfigManagerServerSecretRow(
                        id: server.id,
                        displayName: server.displayName,
                        agentName: source.map { AgentRegistry.displayName(for: $0.agent) } ?? "Unknown",
                        sourcePath: server.sourcePath,
                        literalSecretCount: detector.detect(in: server).count
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.displayName != rhs.displayName {
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath) == .orderedAscending
                }
            let literalSecretCount = serverSecretRows.reduce(0) { $0 + $1.literalSecretCount }
            return ConfigManagerBindingRow(
                id: canonicalRow.id.isEmpty ? first.id : canonicalRow.id,
                displayName: canonicalRow.displayName,
                transportLabel: canonicalRow.transportLabel,
                agentNames: canonicalRow.agentNames,
                enabledSourceIDs: canonicalRow.enabledSourceIDs,
                desiredStateSourceIDs: canonicalRow.desiredStateSourceIDs,
                hasPersistedDesiredState: canonicalRow.hasPersistedDesiredState,
                sourceCount: canonicalRow.sourceCount,
                canonicalSummaryText: canonicalRow.summaryText,
                canonicalDriftText: canonicalRow.driftText,
                canonicalDriftCount: canonicalRow.driftCount,
                canonicalSourceRows: canonicalRow.sourceRows,
                issueCount: issueCount,
                literalSecretCount: literalSecretCount,
                serverIDs: servers.map(\.id).sorted(),
                serverSecretRows: serverSecretRows,
                templateServer: first
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let primaryBulkTemplate = primaryBulkTemplateSelection()
        let bulkTargetSourceCount = primaryBulkTemplate.map {
            defaultBulkTargetSources(from: sources, templateSource: $0.source).count
        } ?? 0
        let bulkTargetProfiles = (try? scanHistoryStore?.listConnectAllTargetProfiles()) ?? []

        return ConfigManagerState(
            sources: sources,
            bindings: bindings,
            summaryText: "\(canonicalSnapshot.summaryText) across \(sources.count) agent sources",
            bulkTemplateSource: primaryBulkTemplate?.source,
            bulkTemplateBindingCount: primaryBulkTemplate?.servers.count ?? 0,
            bulkTargetSourceCount: bulkTargetSourceCount,
            bulkDefaultTargetSourceIDs: Set(primaryBulkTemplate.map {
                defaultBulkTargetSources(from: sources, templateSource: $0.source).map(\.id)
            } ?? []),
            bulkTargetProfiles: bulkTargetProfiles
        )
    }

    func bindingDraftPreview(binding: ConfigManagerBindingRow, enabledSourceIDs: Set<String>) -> ConfigBindingDraftSheetState {
        do {
            let targetSources = configManagerState().sources.map(\.source)
            let draft = try AgentConfigAuthoringPlanner().previewBinding(
                templateServer: binding.templateServer,
                targetSources: targetSources,
                existingServers: lastScanResult.servers,
                enabledSourceIDs: enabledSourceIDs
            )
            return ConfigBindingDraftSheetState(binding: binding, enabledSourceIDs: enabledSourceIDs, draft: draft)
        } catch {
            return ConfigBindingDraftSheetState(
                title: "Binding Draft Failed",
                subtitle: binding.displayName,
                text: SecretRedactor.redactText(String(describing: error)),
                binding: binding,
                enabledSourceIDs: enabledSourceIDs,
                canApply: false
            )
        }
    }

    func canonicalDriftActionPreview(binding: ConfigManagerBindingRow, sourceRow: AgentCanonicalConfigManagerSourceRow) -> ConfigBindingDraftSheetState {
        guard let action = sourceRow.suggestedAction else {
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Unavailable",
                subtitle: binding.displayName,
                text: "No canonical drift action is available for this binding source row.",
                binding: binding,
                enabledSourceIDs: [],
                canApply: false
            )
        }

        let managerState = configManagerState()
        guard let source = managerState.sources.first(where: { $0.source.id == sourceRow.sourceID })?.source else {
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Unavailable",
                subtitle: binding.displayName,
                text: "Source not found for this canonical drift action.",
                binding: binding,
                enabledSourceIDs: [],
                canApply: false
            )
        }

        do {
            let executor = AgentCanonicalDriftActionExecutor()
            let draft = try executor.draft(
                for: action,
                templateServer: binding.templateServer,
                targetSource: source,
                existingServers: lastScanResult.servers
            )
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action",
                subtitle: action.title,
                text: ConfigBindingDraftSheetState.text(for: draft),
                binding: binding,
                enabledSourceIDs: action.operation == .bindingDraftEnable || action.operation == .payloadReplacementPreview
                    ? [source.id] : [],
                draft: draft,
                canApply: executor.canApply(action),
                canonicalAction: action
            )
        } catch {
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Failed",
                subtitle: action.title,
                text: SecretRedactor.redactText(String(describing: error)),
                binding: binding,
                enabledSourceIDs: action.operation == .bindingDraftEnable ? [source.id] : [],
                canApply: false,
                canonicalAction: action
            )
        }
    }

    func applyBindingDraft(_ draftState: ConfigBindingDraftSheetState) -> ConfigBindingDraftSheetState {
        guard draftState.canApply else {
            actionMessage = "Binding draft has no changes to apply"
            return draftState
        }

        do {
            let targetSources = configManagerState().sources.map(\.source)
            let result = try AgentConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore).applyBinding(
                templateServer: draftState.binding.templateServer,
                targetSources: targetSources,
                existingServers: lastScanResult.servers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                expectedFileSnapshots: draftState.draft?.fileSnapshotsByPath
            )
            actionMessage = "Applied \(result.appliedTargets.count) binding source\(result.appliedTargets.count == 1 ? "" : "s")"
            refresh()
            return ConfigBindingDraftSheetState(
                title: "Binding Draft Applied",
                subtitle: result.summaryText,
                text: ConfigBindingDraftSheetState.text(for: result),
                binding: draftState.binding,
                enabledSourceIDs: draftState.enabledSourceIDs,
                canApply: false
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Binding apply failed: \(message)"
            return ConfigBindingDraftSheetState(
                title: "Binding Apply Failed",
                subtitle: draftState.subtitle,
                text: message,
                binding: draftState.binding,
                enabledSourceIDs: draftState.enabledSourceIDs,
                draft: draftState.draft,
                canApply: draftState.canApply
            )
        }
    }

    func applyCanonicalDriftAction(_ draftState: ConfigBindingDraftSheetState) -> ConfigBindingDraftSheetState {
        guard draftState.canApply else {
            actionMessage = "Canonical drift action requires review before apply."
            return draftState
        }
        guard let action = draftState.canonicalAction else {
            return applyBindingDraft(draftState)
        }

        let managerState = configManagerState()
        guard let source = managerState.sources.first(where: { $0.source.id == action.sourceID })?.source else {
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Unavailable",
                subtitle: draftState.subtitle,
                text: "Source not found for this canonical drift action.",
                binding: draftState.binding,
                enabledSourceIDs: draftState.enabledSourceIDs,
                draft: draftState.draft,
                canApply: false,
                canonicalAction: action
            )
        }

        do {
            let executor = AgentCanonicalDriftActionExecutor(controlPlaneStore: scanHistoryStore)
            let result = try executor.apply(
                for: action,
                templateServer: draftState.binding.templateServer,
                targetSource: source,
                existingServers: lastScanResult.servers
            )
            actionMessage = "Applied canonical drift action to \(result.appliedTargets.count) source\(result.appliedTargets.count == 1 ? "" : "s")"
            refresh()
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Applied",
                subtitle: result.summaryText,
                text: ConfigBindingDraftSheetState.text(for: result),
                binding: draftState.binding,
                enabledSourceIDs: draftState.binding.enabledSourceIDs,
                canApply: false,
                canonicalAction: action
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Canonical drift apply failed: \(message)"
            return ConfigBindingDraftSheetState(
                title: "Canonical Drift Action Apply Failed",
                subtitle: draftState.subtitle,
                text: message,
                binding: draftState.binding,
                enabledSourceIDs: draftState.enabledSourceIDs,
                draft: draftState.draft,
                canApply: draftState.canApply,
                canonicalAction: action
            )
        }
    }

    func bulkConnectDraftPreview(enabledSourceIDs: Set<String>? = nil) -> ConfigBulkConnectDraftSheetState {
        guard let templateSelection = primaryBulkTemplateSelection() else {
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Unavailable",
                subtitle: "No template source",
                text: "MCP-HQ could not find a parsed source with MCP servers to use as the connection template.",
                templateServers: [],
                enabledSourceIDs: [],
                canApply: false
            )
        }

        let state = configManagerState()
        let selectedIDs = enabledSourceIDs ?? state.bulkDefaultTargetSourceIDs
        let eligibleSources = selectedBulkTargetSources(from: state.sources, templateSource: templateSelection.source, enabledSourceIDs: selectedIDs)

        do {
            let draft = try AgentBulkConfigAuthoringPlanner().previewConnectAll(
                templateServers: templateSelection.servers,
                templateSource: templateSelection.source,
                targetSources: eligibleSources,
                existingServers: lastScanResult.servers,
                enabledSourceIDs: selectedIDs
            )
            return ConfigBulkConnectDraftSheetState(
                templateServers: templateSelection.servers,
                enabledSourceIDs: selectedIDs,
                draft: draft
            )
        } catch {
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Preview Failed",
                subtitle: AgentRegistry.displayName(for: templateSelection.source.agent),
                text: SecretRedactor.redactText(String(describing: error)),
                templateServers: templateSelection.servers,
                enabledSourceIDs: selectedIDs,
                canApply: false
            )
        }
    }

    func saveBulkConnectTargetProfile(
        name: String,
        enabledSourceIDs: Set<String>
    ) -> ConfigBulkConnectTargetProfileSaveResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure("Profile name is required.")
        }
        guard let scanHistoryStore else {
            return .failure("Target profile registry is unavailable.")
        }
        guard let templateSource = primaryBulkTemplateSelection()?.source else {
            return .failure("No Connect All template source is available.")
        }
        let state = configManagerState()
        let selectedSources = selectedBulkTargetSources(
            from: state.sources,
            templateSource: templateSource,
            enabledSourceIDs: enabledSourceIDs
        )
        guard !selectedSources.isEmpty else {
            return .failure("Select at least one target source before saving a profile.")
        }

        do {
            let updatedAt = Date()
            try scanHistoryStore.upsertConnectAllTargetProfile(
                name: trimmedName,
                targetSources: selectedSources,
                updatedAt: updatedAt
            )
            let targetWord = selectedSources.count == 1 ? "target" : "targets"
            let profile = SQLiteConnectAllTargetProfileRecord(
                name: trimmedName,
                targetSources: selectedSources,
                updatedAt: updatedAt
            )
            return .success(
                "Saved profile \(SecretRedactor.redactText(trimmedName)) with \(selectedSources.count) \(targetWord).",
                profile: profile
            )
        } catch {
            return .failure("Profile save failed: \(SecretRedactor.redactText(String(describing: error)))")
        }
    }

    func applyBulkConnectDraft(_ draftState: ConfigBulkConnectDraftSheetState) -> ConfigBulkConnectDraftSheetState {
        guard draftState.canApply else {
            actionMessage = "Connect-all draft has no changes to apply"
            return draftState
        }

        let state = configManagerState()
        let eligibleSources: [ConfigSource]
        if let templateSource = draftState.draft?.templateSource {
            eligibleSources = selectedBulkTargetSources(
                from: state.sources,
                templateSource: templateSource,
                enabledSourceIDs: draftState.enabledSourceIDs
            )
        } else {
            eligibleSources = state.sources
                .filter { $0.canCreateWithBindingDraft && draftState.enabledSourceIDs.contains($0.source.id) }
                .map(\.source)
        }
        do {
            let result = try AgentBulkConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore).applyConnectAll(
                templateServers: draftState.templateServers,
                templateSource: draftState.draft?.templateSource,
                targetSources: eligibleSources,
                existingServers: lastScanResult.servers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                expectedFileSnapshots: draftState.draft?.fileSnapshotsByPath
            )
            let configuredMessage = "Configured \(result.templateBindingCount) binding\(result.templateBindingCount == 1 ? "" : "s") across \(result.appliedTargets.count) source\(result.appliedTargets.count == 1 ? "" : "s")"
            let verificationStarted = runProbes(completionMessage: "\(configuredMessage); live probe verification finished")
            actionMessage = verificationStarted
                ? "\(configuredMessage); running live probe verification"
                : "\(configuredMessage); live probe verification already running"
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Applied",
                subtitle: result.summaryText,
                text: ConfigBulkConnectDraftSheetState.text(for: result),
                templateServers: draftState.templateServers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                verificationReport: result.verificationReport,
                rollbackPlan: result.rollbackPlan,
                canApply: false
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Connect-all apply failed: \(message)"
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Failed",
                subtitle: draftState.subtitle,
                text: message,
                templateServers: draftState.templateServers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                draft: draftState.draft,
                canApply: draftState.canApply
            )
        }
    }

    func rollbackBulkConnectDraft(_ draftState: ConfigBulkConnectDraftSheetState) -> ConfigBulkConnectDraftSheetState {
        guard let rollbackPlan = draftState.rollbackPlan else {
            actionMessage = "Connect-all rollback unavailable"
            return draftState
        }

        do {
            let result = try AgentBulkConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore).rollbackConnectAll(rollbackPlan)
            actionMessage = "Rolled back \(result.restoredTargets.count) connect-all target source\(result.restoredTargets.count == 1 ? "" : "s")"
            refresh()
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Rolled Back",
                subtitle: result.summaryText,
                text: ConfigBulkConnectDraftSheetState.text(for: result),
                templateServers: draftState.templateServers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                canApply: false
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Connect-all rollback failed: \(message)"
            return ConfigBulkConnectDraftSheetState(
                title: "Connect All Rollback Failed",
                subtitle: draftState.subtitle,
                text: message,
                templateServers: draftState.templateServers,
                enabledSourceIDs: draftState.enabledSourceIDs,
                draft: draftState.draft,
                rollbackPlan: rollbackPlan,
                canApply: false
            )
        }
    }

    func bulkRollbackTransactionsState() -> ConfigRollbackTransactionsSheetState {
        guard let scanHistoryStore else {
            actionMessage = "Rollback transaction history unavailable"
            return ConfigRollbackTransactionsSheetState(
                title: "Connect All Rollbacks",
                subtitle: "No registry store",
                records: [],
                message: "MCP-HQ could not open the local registry store that persists Connect All rollback transactions."
            )
        }

        do {
            let records = try scanHistoryStore.listBulkRollbackTransactions(status: nil)
            return ConfigRollbackTransactionsSheetState(records: records)
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Rollback transaction history failed: \(message)"
            return ConfigRollbackTransactionsSheetState(
                title: "Connect All Rollbacks",
                subtitle: "Could not load transactions",
                records: [],
                message: message
            )
        }
    }

    func rollbackBulkConnectTransaction(_ record: SQLiteBulkRollbackTransactionRecord) -> ConfigRollbackTransactionsSheetState {
        guard let scanHistoryStore else {
            actionMessage = "Rollback transaction history unavailable"
            return ConfigRollbackTransactionsSheetState(
                title: "Connect All Rollbacks",
                subtitle: "No registry store",
                records: [],
                message: "MCP-HQ could not open the local registry store that persists Connect All rollback transactions."
            )
        }

        do {
            let currentRecord = try scanHistoryStore.loadBulkRollbackTransaction(record.transactionID) ?? record
            guard ConfigRollbackTransactionsSheetState.canRollback(currentRecord) else {
                actionMessage = "Rollback transaction is \(currentRecord.status)"
                return ConfigRollbackTransactionsSheetState(
                    records: try scanHistoryStore.listBulkRollbackTransactions(status: nil),
                    message: "Transaction \(currentRecord.transactionID) cannot be rolled back because its status is \(currentRecord.status)."
                )
            }

            let result = try AgentBulkConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore).rollbackConnectAll(currentRecord.plan)
            actionMessage = "Rolled back \(result.restoredTargets.count) persisted connect-all target source\(result.restoredTargets.count == 1 ? "" : "s")"
            refresh()
            return ConfigRollbackTransactionsSheetState(
                records: try scanHistoryStore.listBulkRollbackTransactions(status: nil),
                message: ConfigBulkConnectDraftSheetState.text(for: result)
            )
        } catch {
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Persisted connect-all rollback failed: \(message)"
            let records = (try? scanHistoryStore.listBulkRollbackTransactions(status: nil)) ?? [record]
            return ConfigRollbackTransactionsSheetState(
                title: "Connect All Rollbacks",
                subtitle: "Rollback failed",
                records: records,
                message: message
            )
        }
    }

    func secretReview(binding: ConfigManagerBindingRow) -> ConfigSecretReviewSheetState {
        let serverIDs = Set(binding.serverIDs)
        let servers = lastScanResult.servers.filter { serverIDs.contains($0.id) }
        let plan = SecretDetector().migrationPlan(for: servers)
        return ConfigSecretReviewSheetState(binding: binding, detectedSecrets: plan.detectedSecrets)
    }

    func migrateSecrets(from review: ConfigSecretReviewSheetState) -> ConfigSecretReviewSheetState {
        guard review.canMigrate else {
            actionMessage = "No literal secrets to migrate"
            return review
        }

        let targetServerIDs = Set(review.binding.serverIDs)
        let detector = SecretDetector()
        let store = MacOSKeychainSecretStore()
        let applier = AgentConfigSafeApplier()
        let sourcePaths = Set(review.detectedSecrets.map(\.location.sourcePath)).sorted()
        var snapshots: [String: Data?] = [:]
        var storedReferences: [KeychainSecretReference] = []
        var appliedLines: [String] = []

        do {
            for sourcePath in sourcePaths {
                guard let source = source(for: sourcePath) else { continue }
                snapshots[source.path] = try snapshotConfig(at: source.path)

                let sourceServers = lastScanResult.servers.filter { $0.sourcePath == source.path }
                let targetServers = sourceServers.filter { targetServerIDs.contains($0.id) }
                guard !targetServers.isEmpty else { continue }

                let migration = try detector.migrating(targetServers, store: store)
                guard !migration.storedReferences.isEmpty else { continue }
                storedReferences.append(contentsOf: migration.storedReferences)

                let migratedByID = Dictionary(uniqueKeysWithValues: migration.migratedServers.map { ($0.id, $0) })
                let updatedServers = sourceServers.map { migratedByID[$0.id] ?? $0 }
                let result = try applier.apply(source: source, servers: updatedServers, dryRun: false)

                appliedLines.append("\(AgentRegistry.displayName(for: source.agent)): backup \(result.backupPath ?? "none")")
            }

            guard !storedReferences.isEmpty else {
                actionMessage = "No literal secrets to migrate"
                return ConfigSecretReviewSheetState(
                    title: "Secret Migration Skipped",
                    subtitle: review.subtitle,
                    text: "No literal secrets were migrated.",
                    binding: review.binding,
                    detectedSecrets: review.detectedSecrets,
                    canMigrate: false
                )
            }

            try scanHistoryStore?.upsertSecretBindings(review.detectedSecrets, status: "present", validatedAt: Date())
            actionMessage = "Migrated \(storedReferences.count) secret\(storedReferences.count == 1 ? "" : "s") from Config Manager"
            refresh()
            return ConfigSecretReviewSheetState(
                title: "Secret Migration Applied",
                subtitle: "\(storedReferences.count) Keychain reference\(storedReferences.count == 1 ? "" : "s") written",
                text: ([
                    "Binding: \(review.binding.displayName)",
                    "Migrated secrets: \(storedReferences.count)",
                    "Config files updated: \(appliedLines.count)",
                    "",
                    "Updated sources:",
                ] + (appliedLines.isEmpty ? ["(none)"] : appliedLines)).joined(separator: "\n"),
                binding: review.binding,
                detectedSecrets: [],
                canMigrate: false
            )
        } catch {
            try? restoreConfigSnapshots(snapshots)
            var rollbackReferences = storedReferences
            if let failure = error as? SecretMigrationWriteFailure {
                rollbackReferences.append(contentsOf: failure.storedReferences)
                try? scanHistoryStore?.upsertSecretBindings(
                    failure.failedAndPendingSecrets,
                    status: SecretRecoveryStatus.migrationWriteFailed.rawValue,
                    updatedAt: Date(),
                    validatedAt: Date()
                )
            }
            for reference in rollbackReferences {
                try? store.deleteSecret(for: reference)
            }
            let message = SecretRedactor.redactText(String(describing: error))
            actionMessage = "Secret migration failed: \(message)"
            return ConfigSecretReviewSheetState(
                title: "Secret Migration Failed",
                subtitle: review.subtitle,
                text: "Rolled back config files touched by this migration and removed partial Keychain writes.\n\n\(message)",
                binding: review.binding,
                detectedSecrets: review.detectedSecrets,
                canMigrate: review.canMigrate
            )
        }
    }

    private func source(for sourcePath: String) -> ConfigSource? {
        if let source = lastScanResult.sources.first(where: { $0.path == sourcePath }) {
            return source
        }
        return lastScanResult.sourceHealth.first(where: { $0.source.path == sourcePath })?.source
    }

    private func primaryBulkTemplateSelection() -> (source: ConfigSource, servers: [ServerDefinition])? {
        let serversBySource = Dictionary(grouping: lastScanResult.servers, by: \.sourcePath)
        return serversBySource.compactMap { path, servers -> (source: ConfigSource, servers: [ServerDefinition])? in
            guard let source = source(for: path), !servers.isEmpty else { return nil }
            return (source, servers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        }
        .sorted { lhs, rhs in
            if lhs.servers.count != rhs.servers.count {
                return lhs.servers.count > rhs.servers.count
            }
            if lhs.source.agent != rhs.source.agent {
                if lhs.source.agent == .hermes { return true }
                if rhs.source.agent == .hermes { return false }
                return AgentRegistry.displayName(for: lhs.source.agent).localizedCaseInsensitiveCompare(AgentRegistry.displayName(for: rhs.source.agent)) == .orderedAscending
            }
            return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
        }
        .first
    }

    private func defaultBulkTargetSources(from rows: [ConfigManagerSourceRow], templateSource: ConfigSource) -> [ConfigSource] {
        let registry = AgentRegistry.default()
        let candidates = rows.filter { row in
            row.canCreateWithBindingDraft && row.source.id != templateSource.id && row.source.agent != .unknown
        }
        let groupedByAgent = Dictionary(grouping: candidates, by: { $0.source.agent })
        return groupedByAgent.keys.sorted {
            AgentRegistry.displayName(for: $0).localizedCaseInsensitiveCompare(AgentRegistry.displayName(for: $1)) == .orderedAscending
        }
        .compactMap { agent -> ConfigSource? in
            let preferredPaths = registry.definition(for: agent)?.configPaths ?? []
            return groupedByAgent[agent]?.sorted { lhs, rhs in
                if lhs.canOpen != rhs.canOpen { return lhs.canOpen }
                let leftIndex = preferredPaths.firstIndex(of: lhs.source.path) ?? Int.max
                let rightIndex = preferredPaths.firstIndex(of: rhs.source.path) ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
                return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
            }
            .first?
            .source
        }
    }

    private func selectedBulkTargetSources(
        from rows: [ConfigManagerSourceRow],
        templateSource: ConfigSource,
        enabledSourceIDs: Set<String>
    ) -> [ConfigSource] {
        rows
            .filter { row in
                row.canCreateWithBindingDraft
                    && row.source.id != templateSource.id
                    && row.source.agent != .unknown
                    && enabledSourceIDs.contains(row.source.id)
            }
            .sorted { lhs, rhs in
                if lhs.agentName != rhs.agentName {
                    return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
                }
                return lhs.source.path.localizedCaseInsensitiveCompare(rhs.source.path) == .orderedAscending
            }
            .map(\.source)
    }

    private func snapshotConfig(at path: String) throws -> Data? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func restoreConfigSnapshots(_ snapshots: [String: Data?]) throws {
        for (path, data) in snapshots {
            let url = URL(fileURLWithPath: path)
            if let data {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } else if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func controlHelperLaunchAgentConfiguration() -> LocalControlLaunchAgentConfiguration {
        let helperPath = controlHelperPathResolver.resolve()
        return LocalControlLaunchAgentConfiguration(
            programPath: helperPath.path,
            endpointFilePath: preferredControlEndpointStore.fileURL.path
        )
    }

    private func controlHelperInstallText(_ result: LocalControlLaunchAgentInstallResult, title: String) -> String {
        [
            title,
            "Plist: \(result.plistPath)",
            "Did write: \(result.didWrite ? "yes" : "no")",
            "Helper: \(controlHelperPathResolver.resolve().path)",
            "Endpoint file: \(preferredControlEndpointStore.fileURL.path)",
            "Bootstrap command (not run): \(result.bootstrapCommand)",
            "Bootout command (not run): \(result.bootoutCommand)",
            "",
            "Plist XML:",
            result.plistText.isEmpty ? "(empty)" : result.plistText,
        ].joined(separator: "\n")
    }

    private func controlHelperCommandText(_ result: LocalControlLaunchAgentCommandResult, title: String) -> String {
        var lines = [
            title,
            "Command: \(result.command.joined(separator: " "))",
            "Exit code: \(result.exitCode)",
        ]
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            lines.append("")
            lines.append("stdout:")
            lines.append(stdout)
        }
        if !stderr.isEmpty {
            lines.append("")
            lines.append("stderr:")
            lines.append(stderr)
        }
        return lines.joined(separator: "\n")
    }

    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func redactedConfigText(_ text: String, servers: [ServerDefinition]) -> String {
        var redacted = SecretRedactor.redactConfigText(text)
        for server in servers {
            for (name, value) in server.envBindings {
                redacted = replaceSensitiveConfigValue(name: name, value: value, in: redacted)
            }
            for (name, value) in server.headers {
                redacted = replaceSensitiveConfigValue(name: name, value: value, in: redacted)
            }
        }
        return redacted
    }

    private func redactedVisualDiffLines(_ lines: [ConfigVisualDiffLine], servers: [ServerDefinition]) -> [ConfigVisualDiffLine] {
        lines.map { line in
            line.replacingContent(redactedConfigText(line.content, servers: servers))
        }
    }

    private func replaceSensitiveConfigValue(name: String, value: String, in text: String) -> String {
        guard !value.isEmpty else { return text }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("${") || trimmed.hasPrefix("$") || trimmed.hasPrefix("keychain://") {
            return text
        }

        let normalizedName = name.replacingOccurrences(of: "-", with: "_").lowercased()
        let sensitiveNameParts = ["token", "api_key", "apikey", "key", "secret", "password", "authorization", "auth"]
        let replacement = sensitiveNameParts.contains(where: { normalizedName.contains($0) })
            ? "<redacted>"
            : SecretRedactor.redactIfSensitive(SecretRedactor.redactText(value))
        guard replacement != value else { return text }
        return text.replacingOccurrences(of: value, with: replacement)
    }

    private func persist(_ result: ScanResult, scannedAt: Date) {
        Self.persist(result, scannedAt: scannedAt, cache: scanResultStore, history: scanHistoryStore)
    }

    nonisolated private static func persist(
        _ result: ScanResult,
        scannedAt: Date,
        cache: JSONScanResultStore?,
        history: SQLiteScanHistoryStore?
    ) {
        try? cache?.save(result, scannedAt: scannedAt)
        _ = try? history?.save(result, scannedAt: scannedAt)
    }

    private static func relativeRefreshText(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Last refreshed at \(formatter.string(from: date))"
    }
}

struct ConfigPreviewSheetState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let text: String
    let targetSource: ConfigSource?
    let servers: [ServerDefinition]
    let renderedText: String
    let diffText: String
    let visualDiffLines: [ConfigVisualDiffLine]
    let backupPath: String?
    let canApply: Bool
    let canRollback: Bool

    init(
        title: String,
        subtitle: String,
        text: String,
        targetSource: ConfigSource? = nil,
        servers: [ServerDefinition] = [],
        renderedText: String = "",
        diffText: String = "",
        visualDiffLines: [ConfigVisualDiffLine] = [],
        backupPath: String? = nil,
        canApply: Bool = true,
        canRollback: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.targetSource = targetSource
        self.servers = servers
        self.renderedText = renderedText
        self.diffText = diffText
        self.visualDiffLines = visualDiffLines
        self.backupPath = backupPath
        self.canApply = canApply
        self.canRollback = canRollback
    }
}

#if os(macOS)
private extension DoctorReportExportFormat {
    var contentType: UTType {
        switch self {
        case .text:
            return .plainText
        case .json:
            return .json
        }
    }
}
#endif

enum ScanHistoryRunDetailFormat: CaseIterable {
    case text
    case json

    init(preferredExportFormat rawValue: String) {
        switch NativeAppPreferences.preferredExportFormat(rawValue: rawValue) {
        case .text:
            self = .text
        case .json:
            self = .json
        }
    }

    var label: String {
        switch self {
        case .text:
            return "TXT"
        case .json:
            return "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .text:
            return "txt"
        case .json:
            return "json"
        }
    }
}

struct ScanHistoryRunDetailState: Identifiable, Equatable {
    let id = UUID()
    let runID: String
    let scannedAt: Date
    let title: String
    let subtitle: String
    let text: String
    let jsonText: String?

    init(runID: String, stored: StoredScanResult, storedDoctorReport: SQLiteStoredDoctorReport? = nil) throws {
        let dateFormatter = ISO8601DateFormatter()
        let scanText = ScanOutputFormatter().formatText(stored.result)
        let scanJSON = try ScanOutputFormatter().formatJSON(stored.result)
        let scanObject = try JSONSerialization.jsonObject(with: Data(scanJSON.utf8))
        var wrapper: [String: Any] = [
            "runID": runID,
            "scannedAt": dateFormatter.string(from: stored.scannedAt),
            "scan": scanObject,
        ]
        let doctorText = storedDoctorReport.map { DoctorReportFormatter().formatText($0.report) }
        if let storedDoctorReport {
            let doctorJSON = try DoctorReportFormatter().formatJSON(storedDoctorReport.report)
            wrapper["doctor"] = try JSONSerialization.jsonObject(with: Data(doctorJSON.utf8))
            wrapper["reportedAt"] = dateFormatter.string(from: storedDoctorReport.reportedAt)
        }
        let wrapperData = try JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])
        let wrapperJSON = String(data: wrapperData, encoding: .utf8)

        var textSections = [
            "MCP-HQ history run",
            "",
            "Run: \(runID)",
            "Scanned at: \(dateFormatter.string(from: stored.scannedAt))",
            "",
            scanText,
        ]
        if let storedDoctorReport, let doctorText {
            textSections.append(contentsOf: [
                "",
                "Stored Doctor report",
                "Reported at: \(dateFormatter.string(from: storedDoctorReport.reportedAt))",
                "",
                doctorText,
            ])
        }

        self.runID = runID
        self.scannedAt = stored.scannedAt
        self.title = "History Run"
        self.subtitle = storedDoctorReport == nil
            ? dateFormatter.string(from: stored.scannedAt)
            : "\(dateFormatter.string(from: stored.scannedAt)) • Doctor report saved"
        self.text = textSections.joined(separator: "\n")
        self.jsonText = wrapperJSON
    }

    init(runID: String, scannedAt: Date, title: String, subtitle: String, text: String, jsonText: String?) {
        self.runID = runID
        self.scannedAt = scannedAt
        self.title = title
        self.subtitle = subtitle
        self.text = SecretRedactor.redactText(text)
        self.jsonText = jsonText.map(SecretRedactor.redactText)
    }

    func text(for format: ScanHistoryRunDetailFormat) -> String? {
        switch format {
        case .text:
            return text
        case .json:
            return jsonText
        }
    }

    func fileName(for format: ScanHistoryRunDetailFormat) -> String {
        "history-\(Self.safeRunID(runID)).\(format.fileExtension)"
    }

    private static func safeRunID(_ runID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = String(runID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return filtered.isEmpty ? "run" : filtered
    }
}

struct ConfigManagerState: Equatable {
    let sources: [ConfigManagerSourceRow]
    let bindings: [ConfigManagerBindingRow]
    let summaryText: String
    let bulkTemplateSource: ConfigSource?
    let bulkTemplateBindingCount: Int
    let bulkTargetSourceCount: Int
    let bulkDefaultTargetSourceIDs: Set<String>
    let bulkTargetProfiles: [SQLiteConnectAllTargetProfileRecord]

    var canBulkConnect: Bool {
        bulkTemplateBindingCount > 0 && bulkTargetSourceCount > 0
    }
}

struct ConfigBulkConnectTargetProfileSaveResult: Equatable {
    let message: String
    let profile: SQLiteConnectAllTargetProfileRecord?

    static func success(
        _ message: String,
        profile: SQLiteConnectAllTargetProfileRecord
    ) -> ConfigBulkConnectTargetProfileSaveResult {
        ConfigBulkConnectTargetProfileSaveResult(message: message, profile: profile)
    }

    static func failure(_ message: String) -> ConfigBulkConnectTargetProfileSaveResult {
        ConfigBulkConnectTargetProfileSaveResult(message: message, profile: nil)
    }
}

struct ConfigManagerSourceRow: Identifiable, Equatable {
    let id: String
    let source: ConfigSource
    let agentName: String
    let stateLabel: String
    let serverCount: Int
    let issueCount: Int
    let literalSecretCount: Int
    let message: String
    let readinessLabel: String
    let readinessDetail: String
    let canCreateWithBindingDraft: Bool
    let sourcePath: String
    let canPreview: Bool
    let canOpen: Bool
}

struct ConfigManagerBindingRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let transportLabel: String
    let agentNames: [String]
    let enabledSourceIDs: Set<String>
    let desiredStateSourceIDs: Set<String>
    let hasPersistedDesiredState: Bool
    let sourceCount: Int
    let canonicalSummaryText: String
    let canonicalDriftText: String
    let canonicalDriftCount: Int
    let canonicalSourceRows: [AgentCanonicalConfigManagerSourceRow]
    let issueCount: Int
    let literalSecretCount: Int
    let serverIDs: [String]
    let serverSecretRows: [ConfigManagerServerSecretRow]
    let templateServer: ServerDefinition
}

struct ConfigManagerServerSecretRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let agentName: String
    let sourcePath: String
    let literalSecretCount: Int
}

struct ConfigSecretReviewSheetState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let text: String
    let binding: ConfigManagerBindingRow
    let detectedSecrets: [DetectedSecret]
    let canMigrate: Bool

    init(binding: ConfigManagerBindingRow, detectedSecrets: [DetectedSecret]) {
        self.title = "Secret Review"
        self.subtitle = "\(detectedSecrets.count) literal secret\(detectedSecrets.count == 1 ? "" : "s") in \(binding.displayName)"
        self.text = Self.text(binding: binding, detectedSecrets: detectedSecrets)
        self.binding = binding
        self.detectedSecrets = detectedSecrets
        self.canMigrate = !detectedSecrets.isEmpty
    }

    init(title: String, subtitle: String, text: String, binding: ConfigManagerBindingRow, detectedSecrets: [DetectedSecret], canMigrate: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.text = SecretRedactor.redactText(text)
        self.binding = binding
        self.detectedSecrets = detectedSecrets
        self.canMigrate = canMigrate
    }

    private static func text(binding: ConfigManagerBindingRow, detectedSecrets: [DetectedSecret]) -> String {
        var lines = [
            "Binding: \(binding.displayName)",
            "Literal secrets: \(detectedSecrets.count)",
            "Plaintext values are never shown.",
            "",
        ]

        if detectedSecrets.isEmpty {
            lines.append("No literal secrets detected for this binding.")
            return lines.joined(separator: "\n")
        }

        let grouped = Dictionary(grouping: detectedSecrets) { secret in
            "\(secret.location.sourcePath)\u{0}\(secret.location.serverID)"
        }

        for key in grouped.keys.sorted() {
            let secrets = grouped[key] ?? []
            guard let first = secrets.first else { continue }
            lines.append("## \(first.location.serverDisplayName)")
            lines.append("Source: \(first.location.sourcePath)")
            lines.append("Server ID: \(first.location.serverID)")
            for secret in secrets.sorted(by: { lhs, rhs in
                if lhs.location.field != rhs.location.field { return lhs.location.field.rawValue < rhs.location.field.rawValue }
                return lhs.location.name.localizedCaseInsensitiveCompare(rhs.location.name) == .orderedAscending
            }) {
                let field = secret.location.field == .environment ? "Environment" : "Header"
                lines.append("- \(field) \(secret.location.name): \(secret.redactedValue) -> \(secret.replacementValue)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

struct ConfigBindingDraftSheetState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let text: String
    let binding: ConfigManagerBindingRow
    let enabledSourceIDs: Set<String>
    let draft: AgentBindingDraftPreview?
    let canApply: Bool
    let canonicalAction: AgentCanonicalDriftSuggestedAction?

    init(binding: ConfigManagerBindingRow, enabledSourceIDs: Set<String>, draft: AgentBindingDraftPreview) {
        self.title = "Binding Draft"
        self.subtitle = draft.summaryText
        self.text = SecretRedactor.redactConfigText(Self.text(for: draft))
        self.binding = binding
        self.enabledSourceIDs = enabledSourceIDs
        self.draft = draft
        self.canApply = !draft.changedPreviews.isEmpty
        self.canonicalAction = nil
    }

    init(
        title: String,
        subtitle: String,
        text: String,
        binding: ConfigManagerBindingRow,
        enabledSourceIDs: Set<String>,
        draft: AgentBindingDraftPreview? = nil,
        canApply: Bool = false,
        canonicalAction: AgentCanonicalDriftSuggestedAction? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.binding = binding
        self.enabledSourceIDs = enabledSourceIDs
        self.draft = draft
        self.canApply = canApply
        self.canonicalAction = canonicalAction
    }

    static func text(for result: AgentBindingDraftApplyResult) -> String {
        var lines = [
            "Binding: \(result.bindingName)",
            result.summaryText,
            "",
        ]

        if result.appliedTargets.isEmpty {
            lines.append("No config files changed.")
            return lines.joined(separator: "\n")
        }

        for target in result.appliedTargets {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.path)")
            lines.append("Applied: \(target.isEnabled ? "enabled" : "disabled")")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("Backup: \(target.backupPath ?? "none")")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func text(for draft: AgentBindingDraftPreview) -> String {
        var lines = [
            "Binding: \(draft.bindingName)",
            draft.summaryText,
            "",
        ]

        if draft.targetPreviews.isEmpty {
            lines.append("No config files would change for the current binding selection.")
            return lines.joined(separator: "\n")
        }

        for target in draft.targetPreviews {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.path)")
            lines.append("Desired: \(target.isEnabled ? "enabled" : "disabled")")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("")
            lines.append("Diff:")
            lines.append(SecretRedactor.redactConfigText(target.preview.diffText))
            lines.append("")
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n"))
    }
}

struct ConfigBulkConnectDraftSheetState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let text: String
    let templateServers: [ServerDefinition]
    let enabledSourceIDs: Set<String>
    let draft: AgentBulkBindingDraftPreview?
    let verificationReport: AgentBulkConnectVerificationReport?
    let rollbackPlan: AgentBulkConnectRollbackPlan?
    let canApply: Bool

    var canRollback: Bool {
        rollbackPlan?.targets.isEmpty == false
    }

    init(templateServers: [ServerDefinition], enabledSourceIDs: Set<String>, draft: AgentBulkBindingDraftPreview) {
        self.title = "Connect All Draft"
        self.subtitle = draft.summaryText
        self.text = SecretRedactor.redactConfigText(Self.text(for: draft))
        self.templateServers = templateServers
        self.enabledSourceIDs = enabledSourceIDs
        self.draft = draft
        self.verificationReport = nil
        self.rollbackPlan = nil
        self.canApply = !draft.changedPreviews.isEmpty
    }

    init(
        title: String,
        subtitle: String,
        text: String,
        templateServers: [ServerDefinition],
        enabledSourceIDs: Set<String>,
        draft: AgentBulkBindingDraftPreview? = nil,
        verificationReport: AgentBulkConnectVerificationReport? = nil,
        rollbackPlan: AgentBulkConnectRollbackPlan? = nil,
        canApply: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.text = SecretRedactor.redactConfigText(text)
        self.templateServers = templateServers
        self.enabledSourceIDs = enabledSourceIDs
        self.draft = draft
        self.verificationReport = verificationReport
        self.rollbackPlan = rollbackPlan
        self.canApply = canApply
    }

    static func text(for result: AgentBulkBindingDraftApplyResult) -> String {
        var lines = [
            "Connect all",
            result.summaryText,
            "",
        ]

        if result.appliedTargets.isEmpty {
            lines.append("No config files changed.")
            return lines.joined(separator: "\n")
        }

        for target in result.appliedTargets {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.path)")
            lines.append("Bindings applied: \(target.bindingCount)")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("Rollback: \(target.backupPath.map { "restore \($0)" } ?? "delete newly created file")")
            lines.append("")
        }

        if let report = result.verificationReport {
            lines.append("Verification")
            lines.append(report.summaryText)
            if report.targets.contains(where: { $0.probeStatus != .notRun }) {
                lines.append(report.probeSummaryText)
            }
            lines.append("This proves the config files are parseable and contain the expected bindings; it does not prove each external agent is using the changed config.")
            lines.append("")
            lines.append("Verification matrix")
            lines.append(contentsOf: AgentBulkConnectVerificationMatrixFormatter.markdownTableLines(for: report))
            lines.append("")
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
            lines.append("")
            lines.append("MCP-HQ also starts a live probe scan after this app apply completes, independent of the Refresh probe setting. Probe findings appear in the dashboard and Doctor view.")
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n"))
    }

    static func text(for result: AgentBulkConnectRollbackResult) -> String {
        var lines = [
            "Connect all rollback",
            result.summaryText,
            "Rollback transaction: \(result.planID)",
            "",
        ]

        for target in result.restoredTargets {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.path)")
            if target.shouldDeleteCreatedFile {
                lines.append("Action: deleted newly created config file")
            } else {
                lines.append("Action: restored backup \(target.backupPath ?? "unknown")")
            }
            lines.append("")
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n"))
    }

    private static func text(for draft: AgentBulkBindingDraftPreview) -> String {
        var lines = [
            "Connect all",
            draft.summaryText,
            "",
            "Template source: \(draft.templateSource.map { "\(AgentRegistry.displayName(for: $0.agent)) \($0.path)" } ?? "selected bindings")",
            "Target sources: \(draft.targetPreviews.count)",
            "",
        ]

        if draft.targetPreviews.isEmpty {
            lines.append("No eligible agent sources are selected.")
            return lines.joined(separator: "\n")
        }

        for target in draft.targetPreviews {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.path)")
            lines.append("Will create missing config: \(FileManager.default.fileExists(atPath: target.source.path) ? "no" : "yes")")
            lines.append("Bindings to ensure: \(target.bindingCount)")
            lines.append("Servers after change: \(target.serverCount)")
            lines.append("")
            lines.append("Diff:")
            lines.append(SecretRedactor.redactConfigText(target.preview.diffText))
            lines.append("")
        }

        return SecretRedactor.redactConfigText(lines.joined(separator: "\n"))
    }
}

struct ConfigRollbackTransactionsSheetState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let records: [SQLiteBulkRollbackTransactionRecord]
    let message: String?

    init(
        title: String = "Connect All Rollbacks",
        subtitle: String? = nil,
        records: [SQLiteBulkRollbackTransactionRecord],
        message: String? = nil
    ) {
        self.title = title
        self.records = records
        self.subtitle = subtitle ?? "\(records.count) rollback transaction\(records.count == 1 ? "" : "s")"
        self.message = message.map(SecretRedactor.redactConfigText)
    }

    static func canRollback(_ record: SQLiteBulkRollbackTransactionRecord) -> Bool {
        record.status == "available" || record.status == "rollbackFailed"
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @AppStorage("selectedServerID") private var selectedServerID = ""
    @State private var configPreview: ConfigPreviewSheetState?
    @State private var isShowingHistory = false
    @State private var isShowingConfigManager = false
    @State private var isShowingControlHelper = false
    @State private var isShowingRuntimeLifecycle = false
    @State private var isShowingSettings = false

    private var selectedServerDetail: DashboardServerDetail? {
        if !selectedServerID.isEmpty,
           let detail = model.state.serverDetails.first(where: { $0.id == selectedServerID }) {
            return detail
        }
        return model.state.serverDetails.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 288)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("MCP-HQ")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Control Helper") {
                    isShowingControlHelper = true
                }

                Button("Lifecycle & Logs") {
                    model.refreshControlHelperStatus(checkLaunchd: false, checkEndpoint: true)
                    isShowingRuntimeLifecycle = true
                }

                Button("History") {
                    model.refreshHistorySummaries()
                    isShowingHistory = true
                }

                Button("Config Manager") {
                    isShowingConfigManager = true
                }

                Button("Settings") {
                    isShowingSettings = true
                }

                Button("Copy Doctor") {
                    model.copyDoctorReport()
                }

                Button("Validate Keychain") {
                    model.rerunKeychainValidation()
                }

                Button(model.isProbing ? "Probing…" : "Run Probes") {
                    model.runProbes()
                }
                .disabled(model.isProbing)

                Button("Refresh") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .task {
            model.refresh()
        }
        .sheet(isPresented: $isShowingControlHelper) {
            ControlHelperSheet(model: model)
        }
        .sheet(isPresented: $isShowingHistory) {
            ScanHistorySheet(model: model)
        }
        .sheet(isPresented: $isShowingRuntimeLifecycle) {
            RuntimeLifecycleSheet(
                state: model.runtimeLifecyclePanelState(),
                candidates: model.runtimeLaunchCandidates(),
                defaultLogDirectory: model.defaultRuntimeLogDirectoryPath(),
                copyState: { state in model.copyRuntimeLifecyclePanel(state) },
                copyAction: { action in model.copyRuntimeLifecycleAction(action) },
                startRuntime: { serverID, logDirectory in model.startHubRuntime(serverID: serverID, logDirectory: logDirectory) },
                stopRuntime: { runtimeInstanceID in model.stopHubRuntime(runtimeInstanceID) },
                restartRuntime: { runtimeInstanceID, serverID, logDirectory in
                    model.restartHubRuntime(runtimeInstanceID: runtimeInstanceID, serverID: serverID, logDirectory: logDirectory)
                }
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(model: model)
        }
        .sheet(isPresented: $isShowingConfigManager) {
            ConfigManagerSheet(
                state: model.configManagerState(),
                makePreview: { source in
                    model.configPreview(for: source)
                },
                makeBindingDraft: { binding, enabledSourceIDs in
                    model.bindingDraftPreview(binding: binding, enabledSourceIDs: enabledSourceIDs)
                },
                applyBindingDraft: { draft in
                    model.applyBindingDraft(draft)
                },
                makeCanonicalDriftActionDraft: { binding, sourceRow in
                    model.canonicalDriftActionPreview(binding: binding, sourceRow: sourceRow)
                },
                applyCanonicalDriftAction: { draft in
                    model.applyCanonicalDriftAction(draft)
                },
                makeBulkConnectDraft: { enabledSourceIDs in
                    model.bulkConnectDraftPreview(enabledSourceIDs: enabledSourceIDs)
                },
                saveBulkTargetProfile: { name, enabledSourceIDs in
                    model.saveBulkConnectTargetProfile(name: name, enabledSourceIDs: enabledSourceIDs)
                },
                applyBulkConnectDraft: { draft in
                    model.applyBulkConnectDraft(draft)
                },
                rollbackBulkConnectDraft: { draft in
                    model.rollbackBulkConnectDraft(draft)
                },
                makeRollbackTransactions: {
                    model.bulkRollbackTransactionsState()
                },
                rollbackTransaction: { record in
                    model.rollbackBulkConnectTransaction(record)
                },
                makeSecretReview: { binding in
                    model.secretReview(binding: binding)
                },
                migrateSecrets: { review in
                    model.migrateSecrets(from: review)
                },
                copyPreview: { preview in
                    model.copyConfigPreview(preview)
                },
                applyPreview: { preview in
                    model.applyConfigPreview(preview)
                },
                rollbackPreview: { preview in
                    model.rollbackConfig(preview)
                },
                openSource: { source in
                    model.openConfigSource(source)
                }
            )
        }
        .sheet(item: $configPreview) { preview in
            ConfigPreviewSheet(preview: preview) {
                model.copyConfigPreview(preview)
            } applyPreview: {
                configPreview = model.applyConfigPreview(preview)
            } rollbackPreview: {
                configPreview = model.rollbackConfig(preview)
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MCP-HQ")
                        .font(.largeTitle.bold())
                    Text("Native control center for local MCP servers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                SummaryGrid(summary: model.state.summary)

                if !model.state.sourceRows.isEmpty {
                    SourceHealthList(sourceRows: model.state.sourceRows)
                }

                if !model.doctorReport.findings.isEmpty {
                    DoctorFindingsView(report: model.doctorReport)
                }

                if !model.state.issueRows.isEmpty {
                    IssueList(issueRows: model.state.issueRows)
                }

                if !model.state.keychainRecoveryRows.isEmpty {
                    KeychainRecoveryList(rows: model.state.keychainRecoveryRows, compact: true)
                }

                Text(model.lastRefreshedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding()
        }
        .frame(minWidth: 280)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inventory")
                        .font(.title2.bold())
                    Text(model.state.summary.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("History") {
                    model.refreshHistorySummaries()
                    isShowingHistory = true
                }
                Button("Settings") {
                    isShowingSettings = true
                }
                Button("Validate Keychain") {
                    model.rerunKeychainValidation()
                }
                Button(model.isProbing ? "Probing…" : "Run Probes") {
                    model.runProbes()
                }
                .disabled(model.isProbing)
                Button("Refresh") {
                    model.refresh()
                }
            }
            .padding([.horizontal, .top])

            if let selectedServerDetail {
                ServerInspectorView(
                    detail: selectedServerDetail,
                    previewConfig: {
                        configPreview = model.configPreview(for: selectedServerDetail)
                    },
                    migrateSecrets: {
                        model.migrateSecrets(for: selectedServerDetail)
                    },
                    copyText: { text, label in
                        model.copyInspectorText(text, label: label)
                    }
                )
                    .padding(.horizontal)
            }

            if let actionMessage = model.actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)
            }

            if !model.state.keychainRecoveryRows.isEmpty {
                KeychainRecoveryPanel(
                    rows: model.state.keychainRecoveryRows,
                    reviewConfig: { row in
                        configPreview = model.configPreview(sourcePath: row.sourcePath)
                    },
                    rerunMigrationCleanup: { row in
                        model.cleanupMigrationWriteFailedKeychainReferences(for: row)
                    },
                    openMigrationReview: {
                        isShowingConfigManager = true
                    },
                    rerunValidation: {
                        model.rerunKeychainValidation()
                    }
                )
                    .padding(.horizontal)
            }

            if !model.doctorReport.findings.isEmpty {
                DoctorFindingsView(
                    report: model.doctorReport,
                    copyReport: { report in model.copyDoctorReport(report) },
                    exportReport: { report, format in model.exportDoctorReport(report, format: format) },
                    saveReport: { report, format in model.saveDoctorReportAs(report, format: format) },
                    copyFinding: { finding in model.copyDoctorFinding(finding) },
                    openConfig: { finding in model.openConfigSource(for: finding) },
                    previewConfig: { finding in configPreview = model.configPreview(for: finding) },
                    showsFilters: true
                )
                    .padding(.horizontal)
            }

            if model.state.serverRows.isEmpty, model.state.processRows.isEmpty {
                EmptyInventoryView(
                    isProbing: model.isProbing,
                    refresh: { model.refresh() },
                    runProbes: { model.runProbes() },
                    openConfigManager: { isShowingConfigManager = true }
                )
            } else {
                List {
                    if !model.state.serverSections.isEmpty {
                        ForEach(model.state.serverSections) { section in
                            Section {
                                ForEach(section.serverRows) { row in
                                    Button {
                                        selectedServerID = row.id
                                    } label: {
                                        ServerRowView(row: row)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(selectedServerID == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.agentName)
                                    Text(section.sourcePath)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    } else if !model.state.serverRows.isEmpty {
                        Section("Configured servers") {
                            ForEach(model.state.serverRows) { row in
                                Button {
                                    selectedServerID = row.id
                                } label: {
                                    ServerRowView(row: row)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(selectedServerID == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
                            }
                        }
                    }

                    if !model.state.processRows.isEmpty {
                        Section("Running MCP-like processes") {
                            ForEach(model.state.processRows) { row in
                                ProcessRowView(row: row)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NativeAppPreferences.Key.defaultHistoryLimit) private var defaultHistoryLimit = NativeAppPreferences.defaultHistoryLimit
    @AppStorage(NativeAppPreferences.Key.preferredExportFormat) private var preferredExportFormat = NativeAppPreferences.defaultPreferredExportFormat.rawValue
    @AppStorage(NativeAppPreferences.Key.probeOnRefresh) private var probeOnRefresh = NativeAppPreferences.defaultProbeOnRefresh
    @AppStorage(NativeAppPreferences.Key.controlEndpointFilePath) private var endpointFilePath = NativeAppPreferences.defaultControlEndpointFilePath

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.bold())
                    Text("Safe native app preferences stored in UserDefaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "Refresh and history", subtitle: "Controls lightweight scans, live probes, and how much history the sheet loads.")

                Stepper(value: $defaultHistoryLimit, in: NativeAppPreferences.minimumHistoryLimit...NativeAppPreferences.maximumHistoryLimit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default history limit")
                        Text("Show up to \(NativeAppPreferences.sanitizedHistoryLimit(defaultHistoryLimit)) recent run\(NativeAppPreferences.sanitizedHistoryLimit(defaultHistoryLimit) == 1 ? "" : "s") in History.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Run live probes when Refresh is clicked", isOn: $probeOnRefresh)
                    .help("When enabled, Refresh uses the same live MCP probe path as Run Probes. Leave off for a faster, config-only refresh.")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "Exports", subtitle: "The history detail sheet opens with this format selected.")

                Picker("Preferred export format", selection: $preferredExportFormat) {
                    ForEach(NativeAppPreferredExportFormat.allCases, id: \.self) { format in
                        Text(label(for: format)).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Control helper endpoint", subtitle: "Used by Control Helper status checks and LaunchAgent previews/installs.")

                TextField("Endpoint file path", text: $endpointFilePath)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyEndpointPath)

                HStack {
                    Button("Use Default") {
                        endpointFilePath = NativeAppPreferences.defaultControlEndpointFilePath
                        applyEndpointPath()
                    }
                    Button("Apply Path") {
                        applyEndpointPath()
                    }
                    Spacer()
                    Text(NativeAppPreferences.sanitizedEndpointFilePath(endpointFilePath))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Text("Changing this path does not move an existing endpoint file; restart or reinstall the helper if you want it to write to a new location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            defaultHistoryLimit = NativeAppPreferences.sanitizedHistoryLimit(defaultHistoryLimit)
            preferredExportFormat = NativeAppPreferences.preferredExportFormat(rawValue: preferredExportFormat).rawValue
            endpointFilePath = NativeAppPreferences.sanitizedEndpointFilePath(endpointFilePath)
        }
        .onChange(of: defaultHistoryLimit) { _, newValue in
            let sanitized = NativeAppPreferences.sanitizedHistoryLimit(newValue)
            if sanitized != newValue {
                defaultHistoryLimit = sanitized
            }
            model.refreshHistorySummaries()
        }
        .onChange(of: preferredExportFormat) { _, newValue in
            preferredExportFormat = NativeAppPreferences.preferredExportFormat(rawValue: newValue).rawValue
        }
    }

    private func applyEndpointPath() {
        endpointFilePath = NativeAppPreferences.sanitizedEndpointFilePath(endpointFilePath)
        model.refreshControlHelperStatus(checkLaunchd: false, checkEndpoint: false)
    }

    private func label(for format: NativeAppPreferredExportFormat) -> String {
        switch format {
        case .text:
            return "TXT"
        case .json:
            return "JSON"
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScanHistorySheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRunDetail: ScanHistoryRunDetailState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Scan History")
                        .font(.title2.bold())
                    Text("\(model.recentHistorySummaries.count) recent run\(model.recentHistorySummaries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    model.refreshHistorySummaries(reportsSuccess: true)
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            if model.recentHistorySummaries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No scan history found")
                        .font(.headline)
                    Text("Click Refresh for a fast config-only run, or Run Probes to save live health results. The Settings sheet controls how many recent runs are shown here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.recentHistorySummaries, id: \.runID) { summary in
                            ScanHistoryRunSummaryRow(summary: summary) {
                                selectedRunDetail = model.historyRunDetail(summary: summary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            model.refreshHistorySummaries()
        }
        .sheet(item: $selectedRunDetail) { detail in
            ScanHistoryRunDetailSheet(
                detail: detail,
                copyDetail: { format in
                    model.copyHistoryRunDetail(detail, format: format)
                },
                exportDetail: { format in
                    model.exportHistoryRunDetail(detail, format: format)
                }
            )
        }
    }
}

struct ScanHistoryRunSummaryRow: View {
    let summary: SQLiteScanHistoryRunSummary
    let showDetail: () -> Void

    private static let scannedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.scannedAtFormatter.string(from: summary.scannedAt))
                    .font(.headline)
                Spacer()
                Text(summary.runID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("Details") {
                    showDetail()
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                ScanHistoryCountPill(label: "Sources", value: summary.sourceCount)
                ScanHistoryCountPill(label: "Servers", value: summary.serverCount)
                ScanHistoryCountPill(label: "Findings", value: summary.findingCount)
                ScanHistoryCountPill(label: "Processes", value: summary.processCount)
                ScanHistoryCountPill(label: "Probes", value: summary.probeCount)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16))
        )
    }
}

struct ScanHistoryRunDetailSheet: View {
    let detail: ScanHistoryRunDetailState
    let copyDetail: (ScanHistoryRunDetailFormat) -> Void
    let exportDetail: (ScanHistoryRunDetailFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NativeAppPreferences.Key.preferredExportFormat) private var selectedFormatRaw = NativeAppPreferences.defaultPreferredExportFormat.rawValue

    private var selectedFormat: ScanHistoryRunDetailFormat {
        ScanHistoryRunDetailFormat(preferredExportFormat: selectedFormatRaw)
    }

    private var detailText: String {
        detail.text(for: selectedFormat) ?? "History \(selectedFormat.label) detail unavailable."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.title)
                        .font(.title2.bold())
                    Text(detail.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Format", selection: $selectedFormatRaw) {
                    ForEach(NativeAppPreferredExportFormat.allCases, id: \.self) { format in
                        Text(format == .text ? "TXT" : "JSON").tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Button("Copy") {
                    copyDetail(selectedFormat)
                }
                Button("Export") {
                    exportDetail(selectedFormat)
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Run ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail.runID)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ScrollView {
                Text(detailText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16))
            )
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 520)
    }
}

struct ScanHistoryCountPill: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 86, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
    }
}

struct StatusMenuView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    private var snapshot: StatusMenuSnapshot { model.statusMenuSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.summaryText)
                .font(.headline)
            Text(snapshot.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Dashboard") {
                openWindow(id: "dashboard")
                #if os(macOS)
                NSApp.activate(ignoringOtherApps: true)
                #endif
            }

            Button("Refresh") {
                model.refresh()
            }

            Button(snapshot.probeActionTitle) {
                model.runProbes()
            }
            .disabled(!snapshot.canRunProbes)

            Divider()

            Button("Quit MCP-HQ") {
                #if os(macOS)
                NSApp.terminate(nil)
                #endif
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}

struct ControlHelperSheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingInstall = false
    @State private var isConfirmingInstallAndBootstrap = false
    @State private var isConfirmingBootstrap = false
    @State private var isConfirmingBootout = false

    private var snapshot: LocalControlHelperStatusSnapshot {
        model.controlHelperSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Control Helper")
                        .font(.title2.bold())
                    Text("Install, start, and inspect the LaunchAgent-managed loopback helper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                ControlHelperStatusRow(
                    title: "LaunchAgent plist",
                    value: snapshot.installedLabel,
                    detail: snapshot.launchAgentStatus.plistPath,
                    color: snapshot.launchAgentStatus.isInstalled ? .green : .secondary
                )
                ControlHelperStatusRow(
                    title: "launchd",
                    value: snapshot.launchdLabel,
                    detail: snapshot.launchAgentStatus.launchdMessage ?? "Use Refresh Status to ask launchd.",
                    color: color(for: snapshot.launchAgentStatus.launchdState)
                )
                ControlHelperStatusRow(
                    title: "Endpoint",
                    value: snapshot.endpointLabel,
                    detail: snapshot.endpointAvailability.message,
                    color: color(for: snapshot.endpointAvailability.state)
                )
                ControlHelperStatusRow(
                    title: "Dashboard client",
                    value: model.controlClientState.backend.displayName,
                    detail: model.controlClientState.availability.message,
                    color: color(for: model.controlClientState.availability.state)
                )
                ControlHelperStatusRow(
                    title: "Bundled helper",
                    value: snapshot.helperPath.source.displayName,
                    detail: snapshot.helperPathLabel,
                    color: snapshot.helperPath.exists ? .green : .red
                )
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button("Refresh Status") {
                    model.refreshControlHelperStatus(checkLaunchd: true, checkEndpoint: true)
                }
                Button("Preview Install") {
                    model.previewControlHelperLaunchAgentInstall()
                }
                Button("Install & Start") {
                    isConfirmingInstallAndBootstrap = true
                }
                .disabled(!snapshot.canInstallAndBootstrap)
                Button("Install Plist Only") {
                    isConfirmingInstall = true
                }
                .disabled(!snapshot.canInstallPlist)
                Button("Start Helper") {
                    isConfirmingBootstrap = true
                }
                .disabled(!snapshot.canBootstrap)
                Button("Stop Helper", role: .destructive) {
                    isConfirmingBootout = true
                }
                .disabled(!snapshot.canBootout)
                Spacer()
            }

            if let actionHint {
                Text(actionHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The plist points at Contents/MacOS/mcphq when the packaged app helper exists. Start and stop actions run launchctl for this user LaunchAgent only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let previewText = model.controlHelperInstallPreviewText {
                ScrollView {
                    Text(previewText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Spacer()
                Text("Choose Preview Install to see the exact plist XML and launchctl commands that would be used later. No files are written during preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 560)
        .confirmationDialog(
            "Install LaunchAgent plist only?",
            isPresented: $isConfirmingInstall,
            titleVisibility: .visible
        ) {
            Button("Install Plist Only") {
                model.installControlHelperLaunchAgentPlist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will write the LaunchAgent plist and log directory under your user account, but will not run launchctl bootstrap or start the helper.")
        }
        .confirmationDialog(
            "Install and start local control helper?",
            isPresented: $isConfirmingInstallAndBootstrap,
            titleVisibility: .visible
        ) {
            Button("Install & Start") {
                model.installAndBootstrapControlHelperLaunchAgent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will write the LaunchAgent plist, then run launchctl bootstrap for the com.mcphq.control user LaunchAgent. The helper exposes a local loopback control API for this Mac.")
        }
        .confirmationDialog(
            "Start local control helper?",
            isPresented: $isConfirmingBootstrap,
            titleVisibility: .visible
        ) {
            Button("Start Helper") {
                model.bootstrapControlHelperLaunchAgent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will run launchctl bootstrap for the com.mcphq.control user LaunchAgent. The helper exposes a local loopback control API for this Mac.")
        }
        .confirmationDialog(
            "Stop local control helper?",
            isPresented: $isConfirmingBootout,
            titleVisibility: .visible
        ) {
            Button("Stop Helper", role: .destructive) {
                model.bootoutControlHelperLaunchAgent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will run launchctl bootout for the com.mcphq.control user LaunchAgent. This stops the local helper, not your agent-owned MCP server processes.")
        }
    }

    private var actionHint: String? {
        if let reason = snapshot.installDisabledReason {
            return reason
        }
        if !snapshot.canInstallAndBootstrap && !snapshot.canBootstrap && !snapshot.canBootout {
            return snapshot.installAndBootstrapDisabledReason ?? snapshot.bootstrapDisabledReason ?? snapshot.bootoutDisabledReason
        }
        return nil
    }

    private func color(for state: LocalControlLaunchAgentLoadState) -> Color {
        switch state {
        case .loaded:
            return .green
        case .notLoaded:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private func color(for state: LocalControlEndpointAvailabilityState) -> Color {
        switch state {
        case .available:
            return .green
        case .unavailable:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

struct ControlHelperStatusRow: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.bold())
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 92, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

struct RuntimeLifecycleSheet: View {
    let state: RuntimeLifecyclePanelState
    let candidates: [RuntimeLaunchCandidate]
    let defaultLogDirectory: String
    let copyState: (RuntimeLifecyclePanelState) -> Void
    let copyAction: (RuntimeLifecycleSafeAction) -> Void
    let startRuntime: (String, String) -> Void
    let stopRuntime: (String) -> Void
    let restartRuntime: (String, String?, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var logLineLimit = 100
    @State private var logResults: [String: RuntimeLifecyclePanelLogResult] = [:]
    @State private var logErrors: [String: String] = [:]
    @State private var selectedCandidateID: String?
    @State private var logDirectory: String = ""
    @State private var pendingStartCandidate: RuntimeLaunchCandidate?
    @State private var pendingStopRow: RuntimeLifecyclePanelRow?
    @State private var pendingRestartRow: RuntimeLifecyclePanelRow?
    private let logLoader = RuntimeLifecyclePanelLogLoader()

    private var startableCandidates: [RuntimeLaunchCandidate] {
        candidates.filter(\.isStartable)
    }

    private var selectedCandidate: RuntimeLaunchCandidate? {
        guard let selectedCandidateID else { return startableCandidates.first }
        return startableCandidates.first { $0.id == selectedCandidateID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lifecycle & Logs")
                        .font(.title2.bold())
                    Text(state.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Picker("Log lines", selection: $logLineLimit) {
                    Text("50 lines").tag(50)
                    Text("100 lines").tag(100)
                    Text("200 lines").tag(200)
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                Button("Copy Summary") {
                    copyState(state)
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.footerText)
                Text(state.controlPlaneText)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)

            runtimeStartControls

            if state.rows.isEmpty {
                ContentUnavailableView(
                    "No runtime processes",
                    systemImage: "terminal",
                    description: Text("Refresh after starting an MCP server.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.rows) { row in
                    RuntimeLifecycleRowView(
                        row: row,
                        logLineLimit: logLineLimit,
                        logResult: logResults[row.runtimeInstanceID],
                        logError: logErrors[row.runtimeInstanceID],
                        copyAction: copyAction,
                        requestStop: { pendingStopRow = row },
                        requestRestart: { pendingRestartRow = row },
                        loadLogs: loadLogs
                    )
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if logDirectory.isEmpty {
                logDirectory = defaultLogDirectory
            }
            if selectedCandidateID == nil {
                selectedCandidateID = startableCandidates.first?.id
            }
        }
        .confirmationDialog(
            "Start hub-owned runtime?",
            isPresented: Binding(
                get: { pendingStartCandidate != nil },
                set: { if !$0 { pendingStartCandidate = nil } }
            ),
            presenting: pendingStartCandidate
        ) { candidate in
            Button("Start \(candidate.displayName)") {
                startRuntime(candidate.serverID, logDirectory)
                pendingStartCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                pendingStartCandidate = nil
            }
        } message: { candidate in
            Text("MCP-HQ will ask the local control helper to launch a hub-owned copy of \(candidate.displayName) and capture logs under the selected directory.")
        }
        .confirmationDialog(
            "Stop hub-owned runtime?",
            isPresented: Binding(
                get: { pendingStopRow != nil },
                set: { if !$0 { pendingStopRow = nil } }
            ),
            presenting: pendingStopRow
        ) { row in
            Button("Stop \(row.title)", role: .destructive) {
                stopRuntime(row.runtimeInstanceID)
                pendingStopRow = nil
            }
            Button("Cancel", role: .cancel) {
                pendingStopRow = nil
            }
        } message: { row in
            Text("MCP-HQ will ask the local control helper to stop only this hub-owned runtime. Agent-owned and unknown processes are never stopped from this panel.")
        }
        .confirmationDialog(
            "Restart hub-owned runtime?",
            isPresented: Binding(
                get: { pendingRestartRow != nil },
                set: { if !$0 { pendingRestartRow = nil } }
            ),
            presenting: pendingRestartRow
        ) { row in
            Button("Restart \(row.title)") {
                restartRuntime(row.runtimeInstanceID, row.serverID, logDirectory)
                pendingRestartRow = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestartRow = nil
            }
        } message: { row in
            Text("MCP-HQ will ask the local control helper to stop and launch this hub-owned runtime again using the matching configured server.")
        }
    }

    @ViewBuilder
    private var runtimeStartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hub-Owned Launch")
                    .font(.caption.bold())
                Spacer()
                Picker("Server", selection: Binding(
                    get: { selectedCandidateID ?? startableCandidates.first?.id ?? "" },
                    set: { selectedCandidateID = $0 }
                )) {
                    ForEach(startableCandidates) { candidate in
                        Text("\(candidate.displayName) - \(candidate.agentName)")
                            .tag(candidate.id)
                    }
                }
                .frame(width: 260)
                .disabled(startableCandidates.isEmpty)
                Button("Start Runtime") {
                    if let selectedCandidate {
                        pendingStartCandidate = selectedCandidate
                    }
                }
                .disabled(!state.controlPlaneAllowsActions || selectedCandidate == nil || logDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("Log directory", text: $logDirectory)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            if let selectedCandidate {
                Text(selectedCandidate.commandSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("No startable stdio servers are available in the latest scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !state.controlPlaneAllowsActions {
                Text("Start is disabled until the helper endpoint is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadLogs(for row: RuntimeLifecyclePanelRow) {
        do {
            let result = try logLoader.load(row: row, lineLimit: logLineLimit)
            logResults[row.runtimeInstanceID] = result
            logErrors[row.runtimeInstanceID] = nil
        } catch {
            logResults[row.runtimeInstanceID] = nil
            logErrors[row.runtimeInstanceID] = SecretRedactor.redactText(String(describing: error))
        }
    }
}

struct RuntimeLifecycleRowView: View {
    let row: RuntimeLifecyclePanelRow
    let logLineLimit: Int
    let logResult: RuntimeLifecyclePanelLogResult?
    let logError: String?
    let copyAction: (RuntimeLifecycleSafeAction) -> Void
    let requestStop: () -> Void
    let requestRestart: () -> Void
    let loadLogs: (RuntimeLifecyclePanelRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.headline)
                Text(row.pidText)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(row.ownershipLabel)
                    .font(.caption.bold())
                    .foregroundStyle(color(forOwnership: row.ownershipLabel))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(row.statusLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }

            Text(row.serverText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                Label("Control", systemImage: "switch.2")
                    .font(.caption.bold())
                Text(row.controlExplanation)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(row.controlAvailabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.bold())
                Text(row.logHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(row.logView.message)
                    .font(.caption)
                    .foregroundStyle(row.logView.isLoadable ? .primary : .secondary)
                    .textSelection(.enabled)
                if let displayPath = row.logView.displayPath {
                    Text(displayPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if row.logView.isLoadable {
                    Button("Load last \(logLineLimit) lines") {
                        loadLogs(row)
                    }
                    .help("Read and redact a bounded tail of the known log path. This does not start, stop, or restart any process.")
                }
                if let logError {
                    Text(logError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let logResult {
                    Text(logResult.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(logResult.entries) { entry in
                                Text("[\(entry.stream.rawValue)] \(entry.message)")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            if logResult.entries.isEmpty {
                                Text("Log file is empty.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 180)
                    .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !row.capabilitySummaries.isEmpty {
                DisclosureGroup("Capability explanations") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(row.capabilitySummaries, id: \.self) { summary in
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(summary.contains("available") ? .primary : .secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if row.availableControlActions.contains(.stop) {
                HStack {
                    Button("Stop Runtime", role: .destructive) {
                        requestStop()
                    }
                    .help("Ask the local MCP-HQ helper to stop this hub-owned runtime. External agent-owned processes are not eligible.")
                    if row.availableControlActions.contains(.restart) {
                        Button("Restart Runtime") {
                            requestRestart()
                        }
                        .help("Ask the local MCP-HQ helper to restart this hub-owned runtime using the matching configured server.")
                    }
                    Spacer()
                }
            }

            if !row.safeActions.isEmpty {
                HStack {
                    ForEach(row.safeActions) { action in
                        Button(action.title) {
                            copyAction(action)
                        }
                        .help(action.detail)
                    }
                    Spacer()
                }
            }
        }
    }

    private func color(forOwnership label: String) -> Color {
        switch label {
        case RuntimeOwnership.hubOwned.displayLabel:
            return .green
        case RuntimeOwnership.agentOwned.displayLabel:
            return .blue
        default:
            return .secondary
        }
    }
}

struct SummaryGrid: View {
    let summary: DashboardSummary

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                SummaryCard(title: "Servers", value: "\(summary.serverCount)")
                SummaryCard(title: "Processes", value: "\(summary.processCount)")
            }
            GridRow {
                SummaryCard(title: "Sources", value: "\(summary.sourceCount)")
                SummaryCard(title: "Warnings", value: "\(summary.warningCount)")
            }
            GridRow {
                SummaryCard(title: "Errors", value: "\(summary.errorCount)")
            }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SourceHealthList: View {
    let sourceRows: [DashboardSourceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Sources")
                .font(.headline)
            ForEach(sourceRows) { source in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(source.agentName)
                            .font(.caption.bold())
                        Spacer()
                        Text(source.stateLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(color(for: source.stateLabel))
                    }
                    Text(source.message)
                        .font(.caption)
                    Text(source.sourcePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func color(for stateLabel: String) -> Color {
        switch stateLabel {
        case "Parsed":
            return .green
        case "Malformed", "Unsupported":
            return .red
        case "No servers":
            return .orange
        default:
            return .secondary
        }
    }
}

struct DoctorFindingsView: View {
    let report: DoctorReport
    var copyReport: ((DoctorReport) -> Void)? = nil
    var exportReport: ((DoctorReport, DoctorReportExportFormat) -> Void)? = nil
    var saveReport: ((DoctorReport, DoctorReportExportFormat) -> Void)? = nil
    var copyFinding: ((DoctorFinding) -> Void)? = nil
    var openConfig: ((DoctorFinding) -> Void)? = nil
    var previewConfig: ((DoctorFinding) -> Void)? = nil
    var showsFilters: Bool = false

    @AppStorage("doctorFilterSeverity") private var selectedSeverity = Self.allFilterValue
    @AppStorage("doctorFilterCategory") private var selectedCategory = Self.allFilterValue
    @AppStorage("doctorFilterSourcePath") private var selectedSourcePath = Self.allFilterValue
    @AppStorage("doctorFilterServerID") private var selectedServerID = Self.allFilterValue

    private static let allFilterValue = "__all__"

    var body: some View {
        let visibleReport = filteredReport

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Doctor")
                    .font(.headline)
                Spacer()
                if let copyReport {
                    Button("Copy") {
                        copyReport(visibleReport)
                    }
                    .font(.caption)
                }
                if exportReport != nil || saveReport != nil {
                    Menu("Export") {
                        if let exportReport {
                            Section("Application Support") {
                                ForEach(DoctorReportExportFormat.allCases, id: \.self) { format in
                                    Button(format.label) {
                                        exportReport(visibleReport, format)
                                    }
                                }
                            }
                        }
                        if let saveReport {
                            Section("Choose Destination") {
                                ForEach(DoctorReportExportFormat.allCases, id: \.self) { format in
                                    Button("Save \(format.label) As...") {
                                        saveReport(visibleReport, format)
                                    }
                                }
                            }
                        }
                    }
                    .font(.caption)
                }
                Text(summaryText(for: visibleReport))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if showsFilters, report.findings.count > 1 {
                filterControls(visibleReport: visibleReport)
            }

            if visibleReport.findings.isEmpty {
                Text("No Doctor findings match these filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(visibleReport.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.agentName)
                            .font(.caption.bold())
                        Text(group.sourcePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 10) {
                        if let serverName = group.serverName {
                            Text("Server: \(serverName)")
                        }
                        if let category = group.category {
                            Text("Category: \(category.rawValue)")
                        }
                        if let severity = group.severity {
                            Text("Severity: \(severity.rawValue)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                    ForEach(group.findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(finding.severity.rawValue.capitalized)
                                    .font(.caption2.bold())
                                    .foregroundStyle(color(for: finding.severity))
                                Text(finding.category.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let serverName = finding.serverName {
                                    Text(serverName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            Text(finding.title)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(finding.whyItMatters)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(finding.suggestedFix)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            findingActions(for: finding)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func filterControls(visibleReport: DoctorReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], alignment: .leading, spacing: 6) {
                Picker("Severity", selection: $selectedSeverity) {
                    Text("All severities").tag(Self.allFilterValue)
                    Text("Errors").tag(DoctorFindingSeverity.error.rawValue)
                    Text("Warnings").tag(DoctorFindingSeverity.warning.rawValue)
                    Text("Info").tag(DoctorFindingSeverity.info.rawValue)
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Category", selection: $selectedCategory) {
                    Text("All categories").tag(Self.allFilterValue)
                    ForEach(categoryOptions, id: \.rawValue) { category in
                        Text(category.rawValue.capitalized)
                            .tag(category.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Source", selection: $selectedSourcePath) {
                    Text("All sources").tag(Self.allFilterValue)
                    ForEach(sourceOptions, id: \.self) { sourcePath in
                        Text(shortPath(sourcePath))
                            .tag(sourcePath)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Server", selection: $selectedServerID) {
                    Text("All servers").tag(Self.allFilterValue)
                    ForEach(serverOptions, id: \.id) { option in
                        Text(option.name)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack {
                Text("Showing \(visibleReport.findings.count) of \(report.findings.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if isFilterActive {
                    Button("Clear filters") {
                        selectedSeverity = Self.allFilterValue
                        selectedCategory = Self.allFilterValue
                        selectedSourcePath = Self.allFilterValue
                        selectedServerID = Self.allFilterValue
                    }
                    .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func findingActions(for finding: DoctorFinding) -> some View {
        let canOpenSource = !finding.sourcePath.isEmpty && FileManager.default.fileExists(atPath: finding.sourcePath)
        let canPreviewSource = finding.serverID != nil
        if canOpenSource || canPreviewSource || copyFinding != nil {
            HStack(spacing: 8) {
                if let copyFinding {
                    Button("Copy Finding") {
                        copyFinding(finding)
                    }
                    .font(.caption2)
                }
                if canOpenSource, let openConfig {
                    Button("Open Config") {
                        openConfig(finding)
                    }
                    .font(.caption2)
                }
                if canPreviewSource, let previewConfig {
                    Button("Preview Config") {
                        previewConfig(finding)
                    }
                    .font(.caption2)
                }
            }
            .padding(.top, 2)
        }
    }

    private var filteredReport: DoctorReport {
        guard showsFilters else { return report }
        return report.filtered(by: DoctorFindingFilter(
            severity: DoctorFindingSeverity(rawValue: selectedSeverity),
            category: DoctorFindingCategory(rawValue: selectedCategory),
            sourcePath: sourceOptions.contains(selectedSourcePath) ? selectedSourcePath : nil,
            serverID: serverOptions.contains(where: { $0.id == selectedServerID }) ? selectedServerID : nil
        ))
    }

    private var isFilterActive: Bool {
        showsFilters && (
            selectedSeverity != Self.allFilterValue
            || selectedCategory != Self.allFilterValue
            || selectedSourcePath != Self.allFilterValue
            || selectedServerID != Self.allFilterValue
        )
    }

    private var categoryOptions: [DoctorFindingCategory] {
        Array(Set(report.findings.compactMap(\.category)).sorted { lhs, rhs in
            lhs.rawValue.localizedCaseInsensitiveCompare(rhs.rawValue) == .orderedAscending
        })
    }

    private var sourceOptions: [String] {
        Array(Set(report.findings.map(\.sourcePath).filter { !$0.isEmpty })).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var serverOptions: [(id: String, name: String)] {
        let pairs = report.findings.compactMap { finding -> (String, String)? in
            guard let serverID = finding.serverID, !serverID.isEmpty else { return nil }
            return (serverID, finding.serverName ?? serverID)
        }
        let namesByID = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        return namesByID.map { id, name in (id: id, name: name) }
            .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
    }

    private func summaryText(for report: DoctorReport) -> String {
        let summary = [
            report.errorCount > 0 ? "\(report.errorCount) error\(report.errorCount == 1 ? "" : "s")" : nil,
            report.warningCount > 0 ? "\(report.warningCount) warning\(report.warningCount == 1 ? "" : "s")" : nil,
            report.infoCount > 0 ? "\(report.infoCount) info" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
        return summary.isEmpty ? "No findings" : summary
    }

    private func shortPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent
    }

    private func color(for severity: DoctorFindingSeverity) -> Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        }
    }
}

struct ConfigPreviewSheet: View {
    let preview: ConfigPreviewSheetState
    let copyPreview: () -> Void
    let applyPreview: () -> Void
    let rollbackPreview: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingApply = false
    @State private var isConfirmingRollback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.title3.bold())
                    Text(preview.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Copy") {
                    copyPreview()
                }
                Button("Apply") {
                    isConfirmingApply = true
                }
                .disabled(!preview.canApply)
                Button("Rollback") {
                    isConfirmingRollback = true
                }
                .disabled(!preview.canRollback)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    StructuredConfigDiffView(lines: preview.visualDiffLines)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compact preview")
                            .font(.headline)
                        Text(preview.text)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 520)
        .confirmationDialog(
            "Apply generated config?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Apply Config") {
                applyPreview()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will write \(preview.subtitle), create a timestamped backup when a file already exists, and re-parse the generated config before keeping it.")
        }
        .confirmationDialog(
            "Restore backup config?",
            isPresented: $isConfirmingRollback,
            titleVisibility: .visible
        ) {
            Button("Rollback Config", role: .destructive) {
                rollbackPreview()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will validate the backup, re-parse it, and restore it over \(preview.subtitle).")
        }
    }
}

private struct StructuredConfigDiffView: View {
    let lines: [ConfigVisualDiffLine]

    private var addedCount: Int { lines.filter { $0.kind == .added }.count }
    private var removedCount: Int { lines.filter { $0.kind == .removed }.count }
    private var contextCount: Int { lines.filter { $0.kind == .context }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Structured diff")
                    .font(.headline)
                Spacer()
                DiffCountBadge(label: "Added", count: addedCount, color: .green)
                DiffCountBadge(label: "Removed", count: removedCount, color: .red)
                DiffCountBadge(label: "Context", count: contextCount, color: .secondary)
            }

            if lines.isEmpty {
                Text("No changes")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        StructuredConfigDiffRow(line: line)
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct DiffCountBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        Text("\(label) \(count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct StructuredConfigDiffRow: View {
    let line: ConfigVisualDiffLine

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var label: String {
        switch line.kind {
        case .added: return "add"
        case .removed: return "remove"
        case .context: return "context"
        }
    }

    private var tint: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var lineNumberText: String {
        let old = line.oldLineNumber.map(String.init) ?? "-"
        let new = line.newLineNumber.map(String.init) ?? "-"
        return "\(old)->\(new)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, alignment: .leading)
            Text(lineNumberText)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(prefix)
                .foregroundStyle(tint)
                .frame(width: 12, alignment: .center)
            Text(line.content.isEmpty ? " " : line.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(line.kind == .context ? 0.04 : 0.10), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ConfigManagerSheet: View {
    let state: ConfigManagerState
    let makePreview: (ConfigSource) -> ConfigPreviewSheetState
    let makeBindingDraft: (ConfigManagerBindingRow, Set<String>) -> ConfigBindingDraftSheetState
    let applyBindingDraft: (ConfigBindingDraftSheetState) -> ConfigBindingDraftSheetState
    let makeCanonicalDriftActionDraft: (ConfigManagerBindingRow, AgentCanonicalConfigManagerSourceRow) -> ConfigBindingDraftSheetState
    let applyCanonicalDriftAction: (ConfigBindingDraftSheetState) -> ConfigBindingDraftSheetState
    let makeBulkConnectDraft: (Set<String>) -> ConfigBulkConnectDraftSheetState
    let saveBulkTargetProfile: (String, Set<String>) -> ConfigBulkConnectTargetProfileSaveResult
    let applyBulkConnectDraft: (ConfigBulkConnectDraftSheetState) -> ConfigBulkConnectDraftSheetState
    let rollbackBulkConnectDraft: (ConfigBulkConnectDraftSheetState) -> ConfigBulkConnectDraftSheetState
    let makeRollbackTransactions: () -> ConfigRollbackTransactionsSheetState
    let rollbackTransaction: (SQLiteBulkRollbackTransactionRecord) -> ConfigRollbackTransactionsSheetState
    let makeSecretReview: (ConfigManagerBindingRow) -> ConfigSecretReviewSheetState
    let migrateSecrets: (ConfigSecretReviewSheetState) -> ConfigSecretReviewSheetState
    let copyPreview: (ConfigPreviewSheetState) -> Void
    let applyPreview: (ConfigPreviewSheetState) -> ConfigPreviewSheetState
    let rollbackPreview: (ConfigPreviewSheetState) -> ConfigPreviewSheetState
    let openSource: (ConfigSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview: ConfigPreviewSheetState?
    @State private var bindingDraft: ConfigBindingDraftSheetState?
    @State private var canonicalDriftActionDraft: ConfigBindingDraftSheetState?
    @State private var bulkConnectDraft: ConfigBulkConnectDraftSheetState?
    @State private var rollbackTransactions: ConfigRollbackTransactionsSheetState?
    @State private var isShowingBulkTargetSelector = false
    @State private var secretReview: ConfigSecretReviewSheetState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config Manager")
                        .font(.title2.bold())
                    Text(state.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview Connect All") {
                    isShowingBulkTargetSelector = true
                }
                .disabled(!state.canBulkConnect)
                .help("Choose target agents before previewing the primary MCP server set.")
                Button("Rollbacks") {
                    rollbackTransactions = makeRollbackTransactions()
                }
                .help("Review persisted Connect All rollback transactions.")
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Agent Sources")
                            .font(.headline)
                        ForEach(state.sources) { source in
                            ConfigManagerSourceCard(source: source) {
                                preview = makePreview(source.source)
                            } openSource: {
                                openSource(source.source)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 360, maxWidth: 430)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Server Bindings")
                            .font(.headline)
                        if let templateSource = state.bulkTemplateSource {
                            Text("Connect All uses \(state.bulkTemplateBindingCount) binding\(state.bulkTemplateBindingCount == 1 ? "" : "s") from \(AgentRegistry.displayName(for: templateSource.agent)) as the template and targets \(state.bulkTargetSourceCount) safe-authorable source\(state.bulkTargetSourceCount == 1 ? "" : "s").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if state.bindings.isEmpty {
                            ConfigManagerEmptyBindingsView()
                        } else {
                            ForEach(state.bindings) { binding in
                                ConfigManagerBindingCard(binding: binding, sources: state.sources) { enabledSourceIDs in
                                    bindingDraft = makeBindingDraft(binding, enabledSourceIDs)
                                } previewCanonicalDriftAction: { sourceRow in
                                    canonicalDriftActionDraft = makeCanonicalDriftActionDraft(binding, sourceRow)
                                } reviewSecrets: {
                                    secretReview = makeSecretReview(binding)
                                }
                                .id("\(binding.id):\(binding.enabledSourceIDs.sorted().joined(separator: ","))")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(minWidth: 920, minHeight: 620)
        .sheet(item: $preview) { preview in
            ConfigPreviewSheet(preview: preview) {
                copyPreview(preview)
            } applyPreview: {
                self.preview = applyPreview(preview)
            } rollbackPreview: {
                self.preview = rollbackPreview(preview)
            }
        }
        .sheet(item: $bindingDraft) { draft in
            ConfigBindingDraftSheet(draft: draft) {
                bindingDraft = applyBindingDraft(draft)
            }
        }
        .sheet(item: $canonicalDriftActionDraft) { draft in
            ConfigBindingDraftSheet(draft: draft) {
                canonicalDriftActionDraft = applyCanonicalDriftAction(draft)
            }
        }
        .sheet(isPresented: $isShowingBulkTargetSelector) {
            ConfigBulkConnectTargetSheet(state: state) { enabledSourceIDs in
                isShowingBulkTargetSelector = false
                bulkConnectDraft = makeBulkConnectDraft(enabledSourceIDs)
            } saveProfile: { name, enabledSourceIDs in
                saveBulkTargetProfile(name, enabledSourceIDs)
            }
        }
        .sheet(item: $bulkConnectDraft) { draft in
            ConfigBulkConnectDraftSheet(draft: draft) {
                bulkConnectDraft = applyBulkConnectDraft(draft)
            } rollbackDraft: {
                bulkConnectDraft = rollbackBulkConnectDraft(draft)
            }
        }
        .sheet(item: $rollbackTransactions) { state in
            ConfigRollbackTransactionsSheet(
                state: state,
                refresh: {
                    makeRollbackTransactions()
                },
                rollbackTransaction: { record in
                    rollbackTransaction(record)
                }
            )
        }
        .sheet(item: $secretReview) { review in
            ConfigSecretReviewSheet(review: review) {
                secretReview = migrateSecrets(review)
            }
        }
    }
}

struct ConfigManagerEmptyBindingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No server bindings yet")
                .font(.subheadline.bold())
            Text("Use Agent Sources on the left to preview a config file. After one supported agent has an MCP server, it appears here and can be copied to the other agents.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("If you already configured a server outside MCP-HQ, close this sheet and refresh the inventory.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConfigManagerSourceCard: View {
    let source: ConfigManagerSourceRow
    let previewSource: () -> Void
    let openSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(source.agentName)
                    .font(.headline)
                Text(source.stateLabel)
                    .font(.caption.bold())
                    .foregroundStyle(color(for: source.stateLabel))
                Spacer()
                Text("\(source.serverCount) server\(source.serverCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(source.sourcePath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Text(source.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(source.readinessDetail)
                .font(.caption)
                .foregroundStyle(source.canCreateWithBindingDraft ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(source.readinessLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(source.canCreateWithBindingDraft ? Color.green : Color.orange)
                if source.issueCount > 0 {
                    Text("\(source.issueCount) issue\(source.issueCount == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                if source.literalSecretCount > 0 {
                    Text("\(source.literalSecretCount) literal secret\(source.literalSecretCount == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Open") {
                    openSource()
                }
                .font(.caption)
                .disabled(!source.canOpen)
                Button("Preview") {
                    previewSource()
                }
                .font(.caption)
                .disabled(!source.canPreview)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(for stateLabel: String) -> Color {
        switch stateLabel {
        case "Parsed":
            return .green
        case "Malformed", "Unsupported":
            return .red
        case "No servers":
            return .orange
        default:
            return .secondary
        }
    }
}

struct ConfigManagerBindingCard: View {
    let binding: ConfigManagerBindingRow
    let sources: [ConfigManagerSourceRow]
    let previewDraft: (Set<String>) -> Void
    let previewCanonicalDriftAction: (AgentCanonicalConfigManagerSourceRow) -> Void
    let reviewSecrets: () -> Void
    @State private var enabledSourceIDs: Set<String>

    init(
        binding: ConfigManagerBindingRow,
        sources: [ConfigManagerSourceRow],
        previewDraft: @escaping (Set<String>) -> Void,
        previewCanonicalDriftAction: @escaping (AgentCanonicalConfigManagerSourceRow) -> Void,
        reviewSecrets: @escaping () -> Void
    ) {
        self.binding = binding
        self.sources = sources
        self.previewDraft = previewDraft
        self.previewCanonicalDriftAction = previewCanonicalDriftAction
        self.reviewSecrets = reviewSecrets
        self._enabledSourceIDs = State(initialValue: binding.enabledSourceIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(binding.displayName)
                    .font(.headline)
                Text(binding.transportLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                Spacer()
                Text("\(binding.sourceCount) source\(binding.sourceCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowPills(values: binding.agentNames)

            VStack(alignment: .leading, spacing: 4) {
                Text(binding.canonicalSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(binding.canonicalDriftText)
                    .font(.caption2.bold())
                    .foregroundStyle(binding.canonicalDriftCount > 0 ? Color.orange : Color.secondary)
            }

            if !binding.canonicalSourceRows.isEmpty {
                DisclosureGroup("Canonical state") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(binding.canonicalSourceRows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(row.agentName)
                                        .font(.caption2.bold())
                                    Text(row.intentLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(row.driftLabel)
                                        .font(.caption2.bold())
                                        .foregroundStyle(row.isDrift ? Color.orange : Color.secondary)
                                    Spacer()
                                    Text(row.sourcePath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                if row.driftStatus == .payloadMismatch {
                                    Text(row.detailText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if let suggestedActionText = row.suggestedActionText {
                                    Text(suggestedActionText)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                    Button(row.suggestedActionButtonLabel ?? "Preview action") {
                                        previewCanonicalDriftAction(row)
                                    }
                                    .font(.caption)
                                } else if row.suggestedAction != nil {
                                    Button(row.suggestedActionButtonLabel ?? "Review action") {
                                        previewCanonicalDriftAction(row)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.top, 3)
                }
                .font(.caption)
            }

            DisclosureGroup("Edit agent bindings") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources) { source in
                        Toggle(isOn: binding(for: source.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.agentName)
                                    .font(.caption.bold())
                                Text(source.sourcePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(source.source.agent == .unknown)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            if binding.literalSecretCount > 0 {
                DisclosureGroup("Server secret counts") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(binding.serverSecretRows.filter { $0.literalSecretCount > 0 }) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.agentName)
                                    .font(.caption2.bold())
                                Text(row.sourcePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(row.literalSecretCount) literal")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.top, 3)
                }
                .font(.caption)
            }

            HStack(spacing: 8) {
                if binding.hasPersistedDesiredState {
                    Text("saved intent")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                }
                if binding.canonicalDriftCount > 0 {
                    Text("\(binding.canonicalDriftCount) canonical drift\(binding.canonicalDriftCount == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                if binding.issueCount > 0 {
                    Text("\(binding.issueCount) issue\(binding.issueCount == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                if binding.literalSecretCount > 0 {
                    Text("\(binding.literalSecretCount) literal secret\(binding.literalSecretCount == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Review Secrets") {
                    reviewSecrets()
                }
                .font(.caption)
                .disabled(binding.literalSecretCount == 0)
                Button("Preview Draft") {
                    previewDraft(enabledSourceIDs)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func binding(for sourceID: String) -> Binding<Bool> {
        Binding(
            get: { enabledSourceIDs.contains(sourceID) },
            set: { isEnabled in
                if isEnabled {
                    enabledSourceIDs.insert(sourceID)
                } else {
                    enabledSourceIDs.remove(sourceID)
                }
            }
        )
    }
}

struct ConfigSecretReviewSheet: View {
    let review: ConfigSecretReviewSheetState
    let migrateSecrets: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingMigration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.title)
                        .font(.title3.bold())
                    Text(review.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Migrate") {
                    isConfirmingMigration = true
                }
                .disabled(!review.canMigrate)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(review.text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .frame(minWidth: 760, minHeight: 560)
        .confirmationDialog(
            "Migrate literal secrets?",
            isPresented: $isConfirmingMigration,
            titleVisibility: .visible
        ) {
            Button("Write Keychain References") {
                migrateSecrets()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will store these values in macOS Keychain, rewrite affected configs to keychain:// references, create backups, and re-parse generated configs.")
        }
    }
}

struct ConfigBindingDraftSheet: View {
    let draft: ConfigBindingDraftSheetState
    let applyDraft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingApply = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title)
                        .font(.title3.bold())
                    Text(draft.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Apply") {
                    isConfirmingApply = true
                }
                .disabled(!draft.canApply)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(draft.text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .frame(minWidth: 760, minHeight: 560)
        .confirmationDialog(
            "Apply binding draft?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Apply Binding") {
                applyDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will write every changed config in this draft, create timestamped backups, re-parse the generated configs, and restore earlier files if a later write fails.")
        }
    }
}

struct ConfigBulkConnectTargetSheet: View {
    let state: ConfigManagerState
    let previewDraft: (Set<String>) -> Void
    let saveProfile: (String, Set<String>) -> ConfigBulkConnectTargetProfileSaveResult
    @Environment(\.dismiss) private var dismiss
    @State private var enabledSourceIDs: Set<String>
    @State private var profiles: [SQLiteConnectAllTargetProfileRecord]
    @State private var profileName = ""
    @State private var profileMessage: String?

    init(
        state: ConfigManagerState,
        previewDraft: @escaping (Set<String>) -> Void,
        saveProfile: @escaping (String, Set<String>) -> ConfigBulkConnectTargetProfileSaveResult
    ) {
        self.state = state
        self.previewDraft = previewDraft
        self.saveProfile = saveProfile
        self._enabledSourceIDs = State(initialValue: state.bulkDefaultTargetSourceIDs)
        self._profiles = State(initialValue: state.bulkTargetProfiles)
    }

    private var targetSources: [ConfigManagerSourceRow] {
        state.sources
            .filter { row in
                row.canCreateWithBindingDraft
                    && row.source.id != state.bulkTemplateSource?.id
                    && row.source.agent != .unknown
            }
            .sorted { lhs, rhs in
                if lhs.agentName != rhs.agentName {
                    return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
                }
                return lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect All Targets")
                        .font(.title3.bold())
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Defaults") {
                    enabledSourceIDs = state.bulkDefaultTargetSourceIDs
                }
                Button("All") {
                    enabledSourceIDs = Set(targetSources.map(\.source.id))
                }
                Button("Clear") {
                    enabledSourceIDs = []
                }
                Button("Preview Draft") {
                    previewDraft(enabledSourceIDs)
                }
                .disabled(enabledSourceIDs.isEmpty)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let templateSource = state.bulkTemplateSource {
                Text("Template: \(AgentRegistry.displayName(for: templateSource.agent)) \(templateSource.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if !profiles.isEmpty {
                    Menu("Profiles") {
                        ForEach(profiles, id: \.name) { profile in
                            Button("\(profile.name) (\(profile.targetSources.count))") {
                                load(profile)
                            }
                        }
                    }
                    .help("Load a saved Connect All target selection.")
                }

                TextField("Profile name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Save Profile") {
                    let result = saveProfile(profileName, enabledSourceIDs)
                    profileMessage = result.message
                    if let profile = result.profile {
                        upsertProfile(profile)
                        profileName = ""
                    }
                }
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || enabledSourceIDs.isEmpty)
                Spacer()
            }

            if let profileMessage {
                Text(profileMessage)
                    .font(.caption)
                    .foregroundStyle(profileMessage.hasPrefix("Saved profile") || profileMessage.hasPrefix("Loaded profile") ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(targetSources) { source in
                        Toggle(isOn: binding(for: source.source.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(source.agentName)
                                            .font(.caption.bold())
                                        Text(source.canOpen ? "update" : "create")
                                            .font(.caption2.bold())
                                            .foregroundStyle(source.canOpen ? Color.blue : Color.green)
                                        if state.bulkDefaultTargetSourceIDs.contains(source.source.id) {
                                            Text("default")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(source.sourcePath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(source.readinessDetail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if targetSources.isEmpty {
                        ContentUnavailableView(
                            "No safe targets",
                            systemImage: "checklist",
                            description: Text("MCP-HQ could not find any non-template known-agent config sources that can be authored safely.")
                        )
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 820, minHeight: 600)
    }

    private var summaryText: String {
        let selectedCount = enabledSourceIDs.count
        let templateCount = state.bulkTemplateBindingCount
        return "\(selectedCount) of \(targetSources.count) target source\(targetSources.count == 1 ? "" : "s") selected for \(templateCount) template binding\(templateCount == 1 ? "" : "s")"
    }

    private func binding(for sourceID: String) -> Binding<Bool> {
        Binding(
            get: { enabledSourceIDs.contains(sourceID) },
            set: { isEnabled in
                if isEnabled {
                    enabledSourceIDs.insert(sourceID)
                } else {
                    enabledSourceIDs.remove(sourceID)
                }
            }
        )
    }

    private func load(_ profile: SQLiteConnectAllTargetProfileRecord) {
        let visibleTargetIDs = Set(targetSources.map(\.source.id))
        let profileTargetIDs = Set(profile.targetSources.map(\.id))
        enabledSourceIDs = profileTargetIDs.intersection(visibleTargetIDs)
        let selectedCount = enabledSourceIDs.count
        let targetWord = selectedCount == 1 ? "target" : "targets"
        profileMessage = "Loaded profile \(profile.name): \(selectedCount) visible \(targetWord) selected."
    }

    private func upsertProfile(_ profile: SQLiteConnectAllTargetProfileRecord) {
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
        profiles.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct ConfigRollbackTransactionsSheet: View {
    let refresh: () -> ConfigRollbackTransactionsSheetState
    let rollbackTransaction: (SQLiteBulkRollbackTransactionRecord) -> ConfigRollbackTransactionsSheetState

    @Environment(\.dismiss) private var dismiss
    @State private var displayedState: ConfigRollbackTransactionsSheetState
    @State private var pendingRollback: SQLiteBulkRollbackTransactionRecord?
    @State private var isConfirmingRollback = false

    init(
        state: ConfigRollbackTransactionsSheetState,
        refresh: @escaping () -> ConfigRollbackTransactionsSheetState,
        rollbackTransaction: @escaping (SQLiteBulkRollbackTransactionRecord) -> ConfigRollbackTransactionsSheetState
    ) {
        self.refresh = refresh
        self.rollbackTransaction = rollbackTransaction
        _displayedState = State(initialValue: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayedState.title)
                        .font(.title3.bold())
                    Text(displayedState.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    displayedState = refresh()
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let message = displayedState.message, !message.isEmpty {
                ScrollView {
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            if displayedState.records.isEmpty {
                ContentUnavailableView(
                    "No Rollback Transactions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Connect All apply transactions will appear here after a successful guarded apply.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedState.records, id: \.transactionID) { record in
                            ConfigRollbackTransactionCard(record: record) {
                                pendingRollback = record
                                isConfirmingRollback = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 560)
        .confirmationDialog(
            "Rollback Connect All transaction?",
            isPresented: $isConfirmingRollback,
            titleVisibility: .visible
        ) {
            Button("Rollback Transaction", role: .destructive) {
                if let pendingRollback {
                    displayedState = rollbackTransaction(pendingRollback)
                }
                pendingRollback = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRollback = nil
            }
        } message: {
            Text("MCP-HQ will restore backup files for existing configs and delete config files that were newly created by this Connect All transaction.")
        }
    }
}

struct ConfigRollbackTransactionCard: View {
    let record: SQLiteBulkRollbackTransactionRecord
    let rollback: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.dateFormatter.string(from: record.createdAt))
                    .font(.headline)
                Text(record.status)
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.16), in: Capsule())
                Spacer()
                Button("Rollback") {
                    rollback()
                }
                .disabled(!ConfigRollbackTransactionsSheetState.canRollback(record))
            }

            Text(record.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(record.transactionID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Text("\(record.plan.targets.count) target source\(record.plan.targets.count == 1 ? "" : "s")")
                .font(.caption.bold())

            VStack(alignment: .leading, spacing: 4) {
                ForEach(record.plan.targets, id: \.source.id) { target in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(target.agentName)
                            .font(.caption.bold())
                            .frame(width: 92, alignment: .leading)
                        Text(target.source.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Text(target.shouldDeleteCreatedFile ? "delete created file" : "restore backup")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch record.status {
        case "available":
            return .blue
        case "rolledBack":
            return .green
        case "rollbackFailed":
            return .orange
        default:
            return .secondary
        }
    }
}

struct ConfigBulkConnectDraftSheet: View {
    let draft: ConfigBulkConnectDraftSheetState
    let applyDraft: () -> Void
    let rollbackDraft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingApply = false
    @State private var isConfirmingRollback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title)
                        .font(.title3.bold())
                    Text(draft.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Apply") {
                    isConfirmingApply = true
                }
                .disabled(!draft.canApply)
                Button("Rollback") {
                    isConfirmingRollback = true
                }
                .disabled(!draft.canRollback)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let verificationReport = draft.verificationReport {
                        ConfigBulkConnectVerificationMatrix(report: verificationReport)
                    }

                    Text(draft.text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 820, minHeight: 600)
        .confirmationDialog(
            "Apply connect-all draft?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Configure Agents") {
                applyDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will write every changed config in this draft, create timestamped backups for existing files, re-parse generated configs, and restore earlier files if a later write fails.")
        }
        .confirmationDialog(
            "Rollback connect-all apply?",
            isPresented: $isConfirmingRollback,
            titleVisibility: .visible
        ) {
            Button("Rollback Connect All", role: .destructive) {
                rollbackDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will restore backup files for existing configs and delete config files that were newly created by this connect-all apply.")
        }
    }
}

struct ConfigBulkConnectVerificationMatrix: View {
    let report: AgentBulkConnectVerificationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verification Matrix")
                    .font(.headline)
                Text("\(report.summaryText). \(report.probeSummaryText). External agent runtime load is not directly verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.targets, id: \.source.id) { target in
                    ConfigBulkConnectVerificationRow(target: target)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConfigBulkConnectVerificationRow: View {
    let target: AgentBulkConnectTargetVerification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.agentName)
                    .font(.caption.bold())
                Text(target.source.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            VerificationBadge(text: target.status.rawValue, color: configColor)

            Text("\(target.presentBindingCount)/\(target.expectedBindingCount) bindings")
                .font(.caption)
                .frame(width: 92, alignment: .leading)

            VerificationBadge(text: probeText, color: probeColor)

            Text(target.probeStatus == .notRun ? target.message : target.probeMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }

    private var probeText: String {
        target.probeStatus == .notRun ? "probe not run" : target.probeStatus.rawValue
    }

    private var configColor: Color {
        switch target.status {
        case .configured:
            return .green
        case .missingConfig, .unsupported, .parseFailed, .missingBindings:
            return .orange
        }
    }

    private var probeColor: Color {
        switch target.probeStatus {
        case .healthy:
            return .green
        case .partial:
            return .orange
        case .failed:
            return .red
        case .notRun:
            return .secondary
        }
    }
}

struct VerificationBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .frame(width: 92, alignment: .leading)
    }
}

struct FlowPills: View {
    let values: [String]

    var body: some View {
        if values.isEmpty {
            Text("No agent bindings")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

struct IssueList: View {
    let issueRows: [DashboardIssueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues")
                .font(.headline)
            ForEach(issueRows) { issue in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(issue.severityLabel.uppercased()) • \(issue.agentName)")
                        .font(.caption.bold())
                    Text(issue.message)
                        .font(.caption)
                    Text(issue.sourcePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(issue.severityLabel == "error" ? Color.red.opacity(0.12) : Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct KeychainRecoveryList: View {
    let rows: [DashboardKeychainRecoveryRow]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keychain Recovery")
                .font(.headline)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.statusLabel.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(row.statusLabel == "Missing" ? Color.orange : Color.red)
                        Spacer()
                        Text(row.fieldLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(row.serverName)
                        .font(.caption.bold())
                    Text(row.summary)
                        .font(.caption)
                        .lineLimit(compact ? 2 : nil)
                    if !compact {
                        Text(row.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.sourcePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct KeychainRecoveryPanel: View {
    let rows: [DashboardKeychainRecoveryRow]
    let reviewConfig: (DashboardKeychainRecoveryRow) -> Void
    let rerunMigrationCleanup: (DashboardKeychainRecoveryRow) -> Void
    let openMigrationReview: () -> Void
    let rerunValidation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keychain Recovery")
                        .font(.headline)
                    Text("\(rows.count) reference\(rows.count == 1 ? "" : "s") need attention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rerun Validation") {
                    rerunValidation()
                }
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.statusLabel)
                            .font(.caption.bold())
                            .foregroundStyle(row.statusLabel == "Missing" ? Color.orange : Color.red)
                        Text(row.serverName)
                            .font(.caption.bold())
                        Spacer()
                        Text(row.fieldName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.summary)
                        .font(.caption)
                    Text(row.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(row.primaryActionTitle) {
                            reviewConfig(row)
                        }
                        Button(row.secondaryActionTitle) {
                            if row.supportsMigrationCleanup {
                                rerunMigrationCleanup(row)
                            } else {
                                rerunValidation()
                            }
                        }
                        Button(row.reviewActionTitle) {
                            openMigrationReview()
                        }
                        Text(row.sourcePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ServerInspectorView: View {
    let detail: DashboardServerDetail
    let previewConfig: () -> Void
    let migrateSecrets: () -> Void
    let copyText: (String, String) -> Void
    @State private var isConfirmingSecretMigration = false
    @State private var capabilitySearchText = ""

    private var hasLiteralSecrets: Bool {
        detail.secretRows.contains { $0.statusLabel == "Literal secret" }
    }

    private var capabilityFilter: DashboardCapabilityFilter {
        DashboardCapabilityFilter(query: capabilitySearchText)
    }

    private var hasCapabilities: Bool {
        !detail.toolNames.isEmpty || !detail.toolDetails.isEmpty ||
            !detail.resourceNames.isEmpty || !detail.resourceDetails.isEmpty ||
            !detail.promptNames.isEmpty || !detail.promptDetails.isEmpty
    }

    private var filteredToolNames: [String] {
        capabilityFilter.filteredToolNames(detail.toolNames)
    }

    private var filteredToolDetails: [MCPToolDetail] {
        capabilityFilter.filteredTools(detail.toolDetails)
    }

    private var filteredResourceNames: [String] {
        capabilityFilter.filteredResourceNames(detail.resourceNames)
    }

    private var filteredResourceDetails: [MCPResourceDetail] {
        capabilityFilter.filteredResources(detail.resourceDetails)
    }

    private var filteredPromptNames: [String] {
        capabilityFilter.filteredPromptNames(detail.promptNames)
    }

    private var filteredPromptDetails: [MCPPromptDetail] {
        capabilityFilter.filteredPrompts(detail.promptDetails)
    }

    private var hasFilteredCapabilities: Bool {
        !filteredToolNames.isEmpty || !filteredToolDetails.isEmpty ||
            !filteredResourceNames.isEmpty || !filteredResourceDetails.isEmpty ||
            !filteredPromptNames.isEmpty || !filteredPromptDetails.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inspector")
                    .font(.headline)
                Text(detail.displayName)
                    .font(.subheadline.bold())
                Text(detail.agentName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(detail.transport.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(detail.toolSummary)
                    .font(.caption.bold())
                    .foregroundStyle(detail.toolSummary.hasPrefix("Healthy") ? .green : .secondary)
            }

            HStack(spacing: 8) {
                Button("Preview Config") {
                    previewConfig()
                }
                .font(.caption)
                Button("Migrate Secrets") {
                    isConfirmingSecretMigration = true
                }
                .font(.caption)
                .disabled(!hasLiteralSecrets)
            }

            if hasCapabilities {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter tools, resources, prompts", text: $capabilitySearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    if capabilityFilter.isActive {
                        Button("Clear") {
                            capabilitySearchText = ""
                        }
                        .font(.caption)
                    }
                }
                if capabilityFilter.isActive && !hasFilteredCapabilities {
                    Text("No tools, resources, or prompts match this filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail.connectionSummary)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Label(detail.processSummary, systemImage: "cpu")
                Label(detail.healthSummary, systemImage: "heart.text.square")
                Label(detail.envSummary, systemImage: "key")
                Label(detail.sourcePath, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !detail.issueRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detail.issueRows) { issue in
                        Text("\(issue.severityLabel.uppercased()): \(issue.message)")
                            .font(.caption)
                            .foregroundStyle(issue.severityLabel == "error" ? .red : .yellow)
                    }
                }
            }

            if !detail.toolNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CapabilitySectionHeader(
                        title: "Tools",
                        visibleCount: filteredToolNames.count,
                        totalCount: detail.toolNames.count,
                        isFiltered: capabilityFilter.isActive
                    )
                    if filteredToolNames.isEmpty {
                        CapabilityNoMatchesText(kind: "tools")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(filteredToolNames, id: \.self) { name in
                                    CapabilityChip(name: name) {
                                        copyText(name, "tool name")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !detail.toolDetails.isEmpty {
                DisclosureGroup(capabilityFilter.isActive ? "Tool details • \(filteredToolDetails.count) of \(detail.toolDetails.count)" : "Tool details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if filteredToolDetails.isEmpty {
                            CapabilityNoMatchesText(kind: "tool details")
                        } else {
                            ForEach(filteredToolDetails) { tool in
                                ToolCapabilityRow(tool: tool) { text, label in
                                    copyText(text, label)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.resourceNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CapabilitySectionHeader(
                        title: "Resources • \(detail.resourceSummary)",
                        visibleCount: filteredResourceNames.count,
                        totalCount: detail.resourceNames.count,
                        isFiltered: capabilityFilter.isActive
                    )
                    if filteredResourceNames.isEmpty {
                        CapabilityNoMatchesText(kind: "resources")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(filteredResourceNames, id: \.self) { name in
                                    CapabilityChip(name: name) {
                                        copyText(name, "resource name")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !detail.resourceDetails.isEmpty {
                DisclosureGroup(capabilityFilter.isActive ? "Resource details • \(filteredResourceDetails.count) of \(detail.resourceDetails.count)" : "Resource details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if filteredResourceDetails.isEmpty {
                            CapabilityNoMatchesText(kind: "resource details")
                        } else {
                            ForEach(filteredResourceDetails) { resource in
                                ResourceCapabilityRow(resource: resource) { text, label in
                                    copyText(text, label)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.promptNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CapabilitySectionHeader(
                        title: "Prompts • \(detail.promptSummary)",
                        visibleCount: filteredPromptNames.count,
                        totalCount: detail.promptNames.count,
                        isFiltered: capabilityFilter.isActive
                    )
                    if filteredPromptNames.isEmpty {
                        CapabilityNoMatchesText(kind: "prompts")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(filteredPromptNames, id: \.self) { name in
                                    CapabilityChip(name: name) {
                                        copyText(name, "prompt name")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !detail.promptDetails.isEmpty {
                DisclosureGroup(capabilityFilter.isActive ? "Prompt details • \(filteredPromptDetails.count) of \(detail.promptDetails.count)" : "Prompt details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if filteredPromptDetails.isEmpty {
                            CapabilityNoMatchesText(kind: "prompt details")
                        } else {
                            ForEach(filteredPromptDetails) { prompt in
                                PromptCapabilityRow(prompt: prompt) { text, label in
                                    copyText(text, label)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.redactedEnvBindings.isEmpty {
                DisclosureGroup("Environment") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.redactedEnvBindings.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(detail.redactedEnvBindings[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.secretRows.isEmpty {
                DisclosureGroup("Secrets") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(detail.secretRows) { secret in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(secret.name)
                                        .font(.system(.caption, design: .monospaced).bold())
                                    Text(secret.fieldLabel)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.thinMaterial, in: Capsule())
                                    Text(secret.statusLabel)
                                        .font(.caption2.bold())
                                        .foregroundStyle(secret.statusLabel == "Literal secret" ? .orange : .secondary)
                                }
                                Text(secret.redactedValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(secret.replacementValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if !detail.processRows.isEmpty {
                DisclosureGroup("Matched processes") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.processRows) { process in
                            Text("pid \(process.pid) • \(process.commandLine)")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(
            "Migrate literal secrets?",
            isPresented: $isConfirmingSecretMigration,
            titleVisibility: .visible
        ) {
            Button("Migrate Secrets") {
                migrateSecrets()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MCP-HQ will store this server's literal env/header secrets in Keychain, rewrite the config to Keychain references, create a timestamped backup, and re-parse the generated config before keeping it.")
        }
    }
}

struct CapabilitySectionHeader: View {
    let title: String
    let visibleCount: Int
    let totalCount: Int
    let isFiltered: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.bold())
            if isFiltered {
                Text("\(visibleCount) of \(totalCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

struct CapabilityChip: View {
    let name: String
    let copyName: () -> Void

    var body: some View {
        Text(name)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .textSelection(.enabled)
            .contextMenu {
                Button("Copy Name") {
                    copyName()
                }
            }
            .help("Control-click to copy")
    }
}

struct CapabilityNoMatchesText: View {
    let kind: String

    var body: some View {
        Text("No \(kind) match the filter.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct ToolCapabilityRow: View {
    let tool: MCPToolDetail
    let copyText: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.name)
                    .font(.system(.caption, design: .monospaced).bold())
                    .textSelection(.enabled)
                Spacer()
                CapabilityCopyMenu(
                    nameActionTitle: "Copy Tool Name",
                    summaryActionTitle: "Copy Tool Summary",
                    copyName: { copyText(tool.name, "tool name") },
                    copySummary: { copyText(toolSummary(tool), "tool summary") }
                )
            }
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !tool.inputSchemaSummary.isEmpty {
                Text("Input: \(tool.inputSchemaSummary)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolSummary(_ tool: MCPToolDetail) -> String {
        var lines = ["Tool: \(tool.name)"]
        if !tool.description.isEmpty { lines.append("Description: \(tool.description)") }
        if !tool.inputSchemaSummary.isEmpty { lines.append("Input: \(tool.inputSchemaSummary)") }
        return lines.joined(separator: "\n")
    }
}

struct ResourceCapabilityRow: View {
    let resource: MCPResourceDetail
    let copyText: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(resource.name.isEmpty ? resource.uri : resource.name)
                    .font(.system(.caption, design: .monospaced).bold())
                    .textSelection(.enabled)
                Spacer()
                CapabilityCopyMenu(
                    nameActionTitle: "Copy Resource Name",
                    summaryActionTitle: "Copy Resource Summary",
                    copyName: { copyText(resource.name.isEmpty ? resource.uri : resource.name, "resource name") },
                    copySummary: { copyText(resourceSummary(resource), "resource summary") }
                )
            }
            Text(resource.uri)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !resource.description.isEmpty {
                Text(resource.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !resource.mimeType.isEmpty {
                Text(resource.mimeType)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resourceSummary(_ resource: MCPResourceDetail) -> String {
        var lines = ["Resource: \(resource.name.isEmpty ? resource.uri : resource.name)", "URI: \(resource.uri)"]
        if !resource.description.isEmpty { lines.append("Description: \(resource.description)") }
        if !resource.mimeType.isEmpty { lines.append("MIME: \(resource.mimeType)") }
        return lines.joined(separator: "\n")
    }
}

struct PromptCapabilityRow: View {
    let prompt: MCPPromptDetail
    let copyText: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(prompt.name)
                    .font(.system(.caption, design: .monospaced).bold())
                    .textSelection(.enabled)
                Spacer()
                CapabilityCopyMenu(
                    nameActionTitle: "Copy Prompt Name",
                    summaryActionTitle: "Copy Prompt Summary",
                    copyName: { copyText(prompt.name, "prompt name") },
                    copySummary: { copyText(promptSummary(prompt), "prompt summary") }
                )
            }
            if !prompt.description.isEmpty {
                Text(prompt.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !prompt.argumentSummary.isEmpty {
                Text("Arguments: \(prompt.argumentSummary)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promptSummary(_ prompt: MCPPromptDetail) -> String {
        var lines = ["Prompt: \(prompt.name)"]
        if !prompt.description.isEmpty { lines.append("Description: \(prompt.description)") }
        if !prompt.argumentSummary.isEmpty { lines.append("Arguments: \(prompt.argumentSummary)") }
        return lines.joined(separator: "\n")
    }
}

struct CapabilityCopyMenu: View {
    let nameActionTitle: String
    let summaryActionTitle: String
    let copyName: () -> Void
    let copySummary: () -> Void

    var body: some View {
        Menu {
            Button(nameActionTitle) {
                copyName()
            }
            Button(summaryActionTitle) {
                copySummary()
            }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Copy safe redacted text")
    }
}

struct ServerRowView: View {
    let row: DashboardServerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(.headline)
                Text(row.agentName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(row.transport.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(row.envSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.connectionSummary)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)

            Text(row.processSummary)
                .font(.caption)
                .foregroundStyle(row.processSummary.hasPrefix("Matched") ? .green : .secondary)

            Text(row.toolSummary)
                .font(.caption)
                .foregroundStyle(row.toolSummary.hasPrefix("Healthy") ? .green : .secondary)

            Text(row.sourcePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if !row.redactedEnvBindings.isEmpty {
                DisclosureGroup("Environment") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(row.redactedEnvBindings.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(row.redactedEnvBindings[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }
}

struct ProcessRowView: View {
    let row: DashboardProcessRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.executableName)
                    .font(.headline)
                Text("pid \(row.pid)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(row.ownershipLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(row.matchReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.commandLine)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)

            Text(row.resourceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyInventoryView: View {
    let isProbing: Bool
    let refresh: () -> Void
    let runProbes: () -> Void
    let openConfigManager: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No MCP servers found yet")
                        .font(.title3.bold())
                    Text("MCP-HQ reads supported coding-agent config files. Add or import one server, then refresh to see it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Open Config Manager to inspect agent config paths and create a safe draft.", systemImage: "1.circle")
                Label("Add an MCP server in Pi, Hermes, Codex, Claude, Cursor, Gemini, or another supported agent.", systemImage: "2.circle")
                Label("Refresh for a config scan, or run probes when you want live health checks.", systemImage: "3.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Config Manager", action: openConfigManager)
                    .buttonStyle(.borderedProminent)
                Button("Refresh", action: refresh)
                Button(isProbing ? "Probing..." : "Run Probes", action: runProbes)
                    .disabled(isProbing)
            }
        }
        .padding(18)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
