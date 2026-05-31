import Foundation

public struct MCPHQCommand: Sendable {
    private let defaultSourceProvider: DefaultConfigSourceProvider
    private let formatter: ScanOutputFormatter
    private let processScanner: MCPProcessScanner
    private let probeProvider: @Sendable ([ServerDefinition]) -> [MCPProbeResult]
    private let liveProbeProvider: @Sendable ([ServerDefinition]) -> [MCPProbeResult]
    private let logTailer: RuntimeLogTailer
    private let scanHistoryStore: SQLiteScanHistoryStore?
    private let secretStore: SecretStore?
    private let launchAgentCommandRunner: @Sendable ([String]) throws -> LocalControlLaunchAgentCommandResult
    private let controlClientHelper: LocalControlClientStateHelper
    private let now: @Sendable () -> Date

    public init(
        defaultSourceProvider: DefaultConfigSourceProvider = DefaultConfigSourceProvider(),
        formatter: ScanOutputFormatter = ScanOutputFormatter(),
        processScanner: MCPProcessScanner = MCPProcessScanner(),
        logTailer: RuntimeLogTailer = RuntimeLogTailer(),
        scanHistoryStore: SQLiteScanHistoryStore? = try? SQLiteScanHistoryStore.applicationSupport(),
        secretStore: SecretStore? = MacOSKeychainSecretStore(),
        probeProvider: @escaping @Sendable ([ServerDefinition]) -> [MCPProbeResult] = { _ in [] },
        liveProbeProvider: @escaping @Sendable ([ServerDefinition]) -> [MCPProbeResult] = { MCPLiveProbe().probe(servers: $0) },
        launchAgentCommandRunner: @escaping @Sendable ([String]) throws -> LocalControlLaunchAgentCommandResult = { command in
            try LocalControlLaunchAgentManager.defaultCommandRunner(command)
        },
        controlClientHelper: LocalControlClientStateHelper = LocalControlClientStateHelper(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaultSourceProvider = defaultSourceProvider
        self.formatter = formatter
        self.processScanner = processScanner
        self.logTailer = logTailer
        self.scanHistoryStore = scanHistoryStore
        self.secretStore = secretStore
        self.probeProvider = probeProvider
        self.liveProbeProvider = liveProbeProvider
        self.launchAgentCommandRunner = launchAgentCommandRunner
        self.controlClientHelper = controlClientHelper
        self.now = now
    }

    public func run(args: [String]) throws -> MCPHQCommandResult {
        guard let command = args.first else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: usage())
        }

        switch command {
        case "scan":
            return try runScan(args: Array(args.dropFirst()))
        case "doctor":
            return try runDoctor(args: Array(args.dropFirst()))
        case "config":
            return runConfig(args: Array(args.dropFirst()))
        case "control":
            return try runControl(args: Array(args.dropFirst()))
        case "history":
            return try runHistory(args: Array(args.dropFirst()))
        case "registry":
            return try runRegistry(args: Array(args.dropFirst()))
        case "runtime":
            return try runRuntime(args: Array(args.dropFirst()))
        case "logs":
            return runLogs(args: Array(args.dropFirst()))
        default:
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: usage())
        }
    }

    private func runScan(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var shouldProbe = false
        var explicitSources: [ConfigSource] = []
        var endpointFile: String?
        var index = 0

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--probe":
                shouldProbe = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                explicitSources.append(source)
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown scan option: \(argument)\n\(usage())")
            }
        }

        let result: ScanResult
        if let endpointFile {
            if explicitSources.count > 1 {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "scan accepts at most one --source with --endpoint-file\n\(usage())")
            }
            let response = try sendLocalControlRequest(
                LocalControlRequest(route: .scan, includeProbes: shouldProbe, source: explicitSources.first),
                endpointFile: endpointFile,
                probeProvider: shouldProbe ? liveProbeProvider : probeProvider
            ).response
            guard let remoteResult = response.scanResult else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Scan failed: \(response.error ?? "missing scan response")")
            }
            result = remoteResult
        } else {
            let sources = explicitSources.isEmpty ? defaultSourceProvider.sources() : explicitSources
            let selectedProbeProvider = shouldProbe ? liveProbeProvider : probeProvider
            result = ScanCoordinator(
                processScanner: processScanner,
                probeProvider: selectedProbeProvider,
                secretStore: secretStore
            ).scan(sources: sources, includeProbes: true)
        }
        let stdout = outputJSON ? try formatter.formatJSON(result) : formatter.formatText(result)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func runDoctor(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var shouldProbe = false
        var explicitSources: [ConfigSource] = []
        var endpointFile: String?
        var filterSeverity: DoctorFindingSeverity?
        var filterCategory: DoctorFindingCategory?
        var filterSourcePath: String?
        var filterServer: String?
        var index = 0

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--probe":
                shouldProbe = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                explicitSources.append(source)
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            case "--severity":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --severity\n\(usage())")
                }
                let severityValue = args[index + 1].lowercased()
                guard let severity = DoctorFindingSeverity(rawValue: severityValue) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --severity value: \(args[index + 1])\n\(usage())")
                }
                filterSeverity = severity
                index += 2
            case "--category":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --category\n\(usage())")
                }
                let categoryValue = args[index + 1].lowercased()
                guard let category = DoctorFindingCategory(rawValue: categoryValue) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --category value: \(args[index + 1])\n\(usage())")
                }
                filterCategory = category
                index += 2
            case "--source-path":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source-path\n\(usage())")
                }
                filterSourcePath = args[index + 1]
                index += 2
            case "--server":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --server\n\(usage())")
                }
                filterServer = args[index + 1]
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown doctor option: \(argument)\n\(usage())")
            }
        }

        let report: DoctorReport
        if let endpointFile {
            if explicitSources.count > 1 {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "doctor accepts at most one --source with --endpoint-file\n\(usage())")
            }
            let response = try sendLocalControlRequest(
                LocalControlRequest(route: .doctor, includeProbes: shouldProbe, source: explicitSources.first),
                endpointFile: endpointFile,
                probeProvider: shouldProbe ? liveProbeProvider : probeProvider
            ).response
            guard let remoteReport = response.doctorReport else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Doctor failed: \(response.error ?? "missing doctor response")")
            }
            report = remoteReport
        } else {
            let sources = explicitSources.isEmpty ? defaultSourceProvider.sources() : explicitSources
            let selectedProbeProvider = shouldProbe ? liveProbeProvider : probeProvider
            let result = ScanCoordinator(
                processScanner: processScanner,
                probeProvider: selectedProbeProvider,
                secretStore: secretStore
            ).scan(sources: sources, includeProbes: true)
            let keychainReport = doctorKeychainRecoveryReport(
                for: result,
                sourcePath: explicitSources.count == 1 ? explicitSources.first?.path : nil
            )
            report = DoctorReportBuilder().build(from: result, keychainRecoveryReport: keychainReport)
        }
        let filter = DoctorFindingFilter(
            severity: filterSeverity,
            category: filterCategory,
            sourcePath: filterSourcePath,
            serverID: resolvedDoctorServerID(filterServer, in: report)
        )
        let formatter = DoctorReportFormatter()
        let stdout = outputJSON ? try formatter.formatJSON(report, filter: filter) : formatter.formatText(report, filter: filter)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private enum ConfigAction: String {
        case preview
        case apply
    }

    private enum ConfigConnectAllAction: String {
        case preview
        case apply
        case rollback
    }

    private enum ConfigCommandError: Error, CustomStringConvertible {
        case sourceFileMissing(ConfigSource)
        case unsupportedAgent(AgentID)
        case serverNotFound(String, ConfigSource)
        case registryStoreUnavailable

        var description: String {
            switch self {
            case .sourceFileMissing(let source):
                return "Config source does not exist: \(source.agent.rawValue):\(source.path)"
            case .unsupportedAgent(let agent):
                return "Config parsing is not supported for \(agent.rawValue)"
            case .serverNotFound(let server, let source):
                return "Server \(SecretRedactor.redactText(server)) was not found in \(source.agent.rawValue):\(source.path)"
            case .registryStoreUnavailable:
                return "Registry store unavailable"
            }
        }
    }

    private func runConfig(args: [String]) -> MCPHQCommandResult {
        if args.first == "connect-all" {
            return runConfigConnectAll(args: Array(args.dropFirst()))
        }

        guard let action = args.first.flatMap(ConfigAction.init(rawValue:)) else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid config action\n\(usage())")
        }

        var targetSource: ConfigSource?
        var serverSource: ConfigSource?
        var endpointFile: String?
        var dryRun = false
        var index = 1

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                targetSource = source
                index += 2
            case "--server-source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --server-source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --server-source value: \(args[index + 1])\n\(usage())")
                }
                serverSource = source
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            case "--dry-run":
                guard action == .apply else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--dry-run is only valid with config apply\n\(usage())")
                }
                dryRun = true
                index += 1
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown config option: \(argument)\n\(usage())")
            }
        }

        guard let targetSource else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing required --source\n\(usage())")
        }

        let inputSource = serverSource ?? targetSource
        if let endpointFile {
            do {
                let exchange = try controlClientHelper.send(
                    LocalControlRequest(
                        route: action == .preview ? .configPreview : .configApply,
                        source: targetSource,
                        serverSource: inputSource,
                        dryRun: action == .apply ? dryRun : true
                    ),
                    endpointFile: endpointFile
                ) {
                    LocalControlInProcessClient(router: LocalControlRouter())
                }

                switch action {
                case .preview:
                    guard let preview = exchange.response.configPreview else {
                        return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config preview failed: \(exchange.response.error ?? "missing preview response")")
                    }
                    return MCPHQCommandResult(exitCode: 0, stdout: formatConfigPreview(preview), stderr: "")
                case .apply:
                    guard let result = exchange.response.configApply else {
                        return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config apply failed: \(exchange.response.error ?? "missing apply response")")
                    }
                    return MCPHQCommandResult(exitCode: 0, stdout: formatConfigApply(result), stderr: "")
                }
            } catch {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config \(action.rawValue) failed: \(error)")
            }
        }

        do {
            let servers = try loadServers(from: inputSource)
            let applier = AgentConfigSafeApplier()
            switch action {
            case .preview:
                let preview = try applier.preview(source: targetSource, servers: servers)
                return MCPHQCommandResult(
                    exitCode: 0,
                    stdout: formatConfigPreview(preview, serverSource: inputSource),
                    stderr: ""
                )
            case .apply:
                let result = try applier.apply(source: targetSource, servers: servers, dryRun: dryRun)
                return MCPHQCommandResult(
                    exitCode: 0,
                    stdout: formatConfigApply(result, serverSource: inputSource, dryRun: dryRun),
                    stderr: ""
                )
            }
        } catch {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config \(action.rawValue) failed: \(error)")
        }
    }

    private func runConfigConnectAll(args: [String]) -> MCPHQCommandResult {
        guard let action = args.first.flatMap(ConfigConnectAllAction.init(rawValue:)) else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid config connect-all action\n\(usage())")
        }

        var templateSource: ConfigSource?
        var targetSources: [ConfigSource] = []
        var endpointFile: String?
        var dryRun = false
        var verifyProbes = false
        var rollbackTransactionID: String?
        var profileName: String?
        var saveProfileName: String?
        var index = 1

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--template-source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --template-source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --template-source value: \(args[index + 1])\n\(usage())")
                }
                templateSource = source
                index += 2
            case "--target-source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --target-source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --target-source value: \(args[index + 1])\n\(usage())")
                }
                targetSources.append(source)
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            case "--profile":
                guard action != .rollback else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--profile is only valid with config connect-all preview/apply\n\(usage())")
                }
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --profile\n\(usage())")
                }
                profileName = args[index + 1]
                index += 2
            case "--save-profile":
                guard action != .rollback else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--save-profile is only valid with config connect-all preview/apply\n\(usage())")
                }
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --save-profile\n\(usage())")
                }
                saveProfileName = args[index + 1]
                index += 2
            case "--dry-run":
                guard action == .apply else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--dry-run is only valid with config connect-all apply\n\(usage())")
                }
                dryRun = true
                index += 1
            case "--probe":
                guard action == .apply else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--probe is only valid with config connect-all apply\n\(usage())")
                }
                verifyProbes = true
                index += 1
            case "--transaction-id":
                guard action == .rollback else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "--transaction-id is only valid with config connect-all rollback\n\(usage())")
                }
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --transaction-id\n\(usage())")
                }
                rollbackTransactionID = args[index + 1]
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown config connect-all option: \(argument)\n\(usage())")
            }
        }

        if let profileName {
            guard let scanHistoryStore else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all profile failed: registry store unavailable")
            }
            do {
                guard let profile = try scanHistoryStore.loadConnectAllTargetProfile(name: profileName) else {
                    return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all profile failed: target profile not found")
                }
                targetSources = uniqueConnectAllSources(profile.targetSources + targetSources)
            } catch {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all profile failed: \(error)")
            }
        }
        if saveProfileName != nil, scanHistoryStore == nil {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all profile failed: registry store unavailable")
        }

        if action == .rollback {
            guard let rollbackTransactionID, !rollbackTransactionID.isEmpty else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing required --transaction-id\n\(usage())")
            }
            guard let scanHistoryStore else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all rollback failed: registry store unavailable")
            }
            do {
                guard let record = try scanHistoryStore.loadBulkRollbackTransaction(rollbackTransactionID) else {
                    return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all rollback failed: transaction not found")
                }
                guard record.status == "available" || record.status == "rollbackFailed" else {
                    return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all rollback failed: transaction status is \(record.status)")
                }
                let result = try AgentBulkConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore).rollbackConnectAll(record.plan)
                return MCPHQCommandResult(exitCode: 0, stdout: formatConnectAllRollback(result), stderr: "")
            } catch {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all rollback failed: \(error)")
            }
        }

        guard let templateSource else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing required --template-source\n\(usage())")
        }
        guard !targetSources.isEmpty else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "At least one --target-source or --profile is required\n\(usage())")
        }

        if let endpointFile {
            do {
                let exchange = try controlClientHelper.send(
                    LocalControlRequest(
                        route: action == .preview ? .configConnectAllPreview : .configConnectAllApply,
                        includeProbes: verifyProbes && action == .apply && !dryRun,
                        templateSource: templateSource,
                        targetSources: targetSources,
                        dryRun: action == .apply ? dryRun : true
                    ),
                    endpointFile: endpointFile
                ) {
                    LocalControlInProcessClient(router: LocalControlRouter())
                }

                switch action {
                case .preview:
                    guard let preview = exchange.response.configBulkPreview else {
                        return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all preview failed: \(exchange.response.error ?? "missing connect-all preview response")")
                    }
                    return MCPHQCommandResult(
                        exitCode: 0,
                        stdout: try appendSavedConnectAllProfileLine(to: preview.text, profileName: saveProfileName, targetSources: targetSources),
                        stderr: ""
                    )
                case .apply:
                    guard let result = exchange.response.configBulkApply else {
                        return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all apply failed: \(exchange.response.error ?? "missing connect-all apply response")")
                    }
                    return MCPHQCommandResult(
                        exitCode: 0,
                        stdout: try appendSavedConnectAllProfileLine(to: result.text, profileName: saveProfileName, targetSources: targetSources),
                        stderr: ""
                    )
                case .rollback:
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Endpoint-backed connect-all rollback is not implemented; use the local registry store\n\(usage())")
                }
            } catch {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all \(action.rawValue) failed: \(error)")
            }
        }

        do {
            let templateServers = try loadServers(from: templateSource)
            let existingServers = try loadExistingServers(from: targetSources)
            let enabledSourceIDs = Set(targetSources.map(\.id))
            let planner = AgentBulkConfigAuthoringPlanner(controlPlaneStore: scanHistoryStore)

            switch action {
            case .preview:
                let draft = try planner.previewConnectAll(
                    templateServers: templateServers,
                    templateSource: templateSource,
                    targetSources: targetSources,
                    existingServers: existingServers,
                    enabledSourceIDs: enabledSourceIDs
                )
                return MCPHQCommandResult(
                    exitCode: 0,
                    stdout: try appendSavedConnectAllProfileLine(to: formatConnectAllPreview(draft), profileName: saveProfileName, targetSources: targetSources),
                    stderr: ""
                )
            case .apply:
                if dryRun {
                    let draft = try planner.previewConnectAll(
                        templateServers: templateServers,
                        templateSource: templateSource,
                        targetSources: targetSources,
                        existingServers: existingServers,
                        enabledSourceIDs: enabledSourceIDs
                    )
                    return MCPHQCommandResult(
                        exitCode: 0,
                        stdout: try appendSavedConnectAllProfileLine(to: formatConnectAllPreview(draft, title: "Config connect-all apply dry run"), profileName: saveProfileName, targetSources: targetSources),
                        stderr: ""
                    )
                }
                let result = try planner.applyConnectAll(
                    templateServers: templateServers,
                    templateSource: templateSource,
                    targetSources: targetSources,
                    existingServers: existingServers,
                    enabledSourceIDs: enabledSourceIDs
                )
                if verifyProbes {
                    let scanResult = ScanCoordinator(probeProvider: liveProbeProvider, secretStore: secretStore).scan(sources: targetSources, includeProbes: true)
                    let verificationReport = AgentBulkConnectVerifier().verify(
                        templateServers: templateServers,
                        targetSources: targetSources,
                        probeResults: scanResult.probeResults
                    )
                    let verifiedResult = AgentBulkBindingDraftApplyResult(
                        templateSource: result.templateSource,
                        templateBindingCount: result.templateBindingCount,
                        appliedTargets: result.appliedTargets,
                        verificationReport: verificationReport,
                        rollbackPlan: result.rollbackPlan
                    )
                    return MCPHQCommandResult(
                        exitCode: 0,
                        stdout: try appendSavedConnectAllProfileLine(to: formatConnectAllApply(verifiedResult), profileName: saveProfileName, targetSources: targetSources),
                        stderr: ""
                    )
                }
                return MCPHQCommandResult(
                    exitCode: 0,
                    stdout: try appendSavedConnectAllProfileLine(to: formatConnectAllApply(result), profileName: saveProfileName, targetSources: targetSources),
                    stderr: ""
                )
            case .rollback:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unexpected connect-all rollback path\n\(usage())")
            }
        } catch {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Config connect-all \(action.rawValue) failed: \(error)")
        }
    }

    private func appendSavedConnectAllProfileLine(
        to text: String,
        profileName: String?,
        targetSources: [ConfigSource]
    ) throws -> String {
        guard let profileName else { return text }
        guard let scanHistoryStore else { throw ConfigCommandError.registryStoreUnavailable }
        let uniqueSources = uniqueConnectAllSources(targetSources)
        try scanHistoryStore.upsertConnectAllTargetProfile(name: profileName, targetSources: uniqueSources)
        let targetWord = uniqueSources.count == 1 ? "target source" : "target sources"
        return text + "Saved target profile: \(SecretRedactor.redactText(profileName)) (\(uniqueSources.count) \(targetWord))\n"
    }

    private func uniqueConnectAllSources(_ sources: [ConfigSource]) -> [ConfigSource] {
        var seen = Set<String>()
        var unique: [ConfigSource] = []
        for source in sources where seen.insert(source.id).inserted {
            unique.append(source)
        }
        return unique
    }

    private func loadServers(from source: ConfigSource) throws -> [ServerDefinition] {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ConfigCommandError.sourceFileMissing(source)
        }
        let parser = AgentConfigParser()
        guard parser.supports(source.agent) else {
            throw ConfigCommandError.unsupportedAgent(source.agent)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
        try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
        return try parser.parse(data: data, source: source)
    }

    private func loadExistingServers(from sources: [ConfigSource]) throws -> [ServerDefinition] {
        let parser = AgentConfigParser()
        var servers: [ServerDefinition] = []
        for source in sources {
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            guard parser.supports(source.agent) else {
                throw ConfigCommandError.unsupportedAgent(source.agent)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: source.path))
            try ConfigSyntaxValidator.validate(data: data, agent: source.agent)
            servers.append(contentsOf: try parser.parse(data: data, source: source))
        }
        return servers
    }

    private func formatConfigPreview(_ preview: GeneratedConfigPreview, serverSource: ConfigSource) -> String {
        """
        Config preview
        Target: \(preview.source.agent.rawValue):\(preview.source.path)
        Server source: \(serverSource.agent.rawValue):\(serverSource.path)
        Reparsed servers: \(preview.reparsedServers.count)

        Generated config:
        \(preview.renderedText)
        """
    }

    private func formatConfigPreview(_ preview: LocalControlConfigPreview) -> String {
        """
        Config preview
        Target: \(preview.target.agent.rawValue):\(preview.target.path)
        Server source: \(preview.serverSource.agent.rawValue):\(preview.serverSource.path)
        Reparsed servers: \(preview.reparsedServerCount)

        Generated config:
        \(preview.renderedText)
        """
    }

    private func formatConfigApply(_ result: ConfigApplyResult, serverSource: ConfigSource, dryRun: Bool) -> String {
        var lines = [
            dryRun ? "Config apply dry run" : "Config apply",
            "Target: \(result.preview.source.agent.rawValue):\(result.preview.source.path)",
            "Server source: \(serverSource.agent.rawValue):\(serverSource.path)",
            "Reparsed servers: \(result.preview.reparsedServers.count)",
            "Did write: \(result.didWrite ? "yes" : "no")",
            "Backup: \(result.backupPath ?? "none")"
        ]
        if dryRun {
            lines.append("")
            lines.append("Generated config:")
            lines.append(result.preview.renderedText)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatConfigApply(_ result: LocalControlConfigApply) -> String {
        var lines = [
            result.dryRun ? "Config apply dry run" : "Config apply",
            "Target: \(result.target.agent.rawValue):\(result.target.path)",
            "Server source: \(result.serverSource.agent.rawValue):\(result.serverSource.path)",
            "Reparsed servers: \(result.reparsedServerCount)",
            "Did write: \(result.didWrite ? "yes" : "no")",
            "Backup: \(result.backupPath ?? "none")"
        ]
        if result.dryRun {
            lines.append("")
            lines.append("Generated config:")
            lines.append(result.renderedText)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatConnectAllPreview(_ draft: AgentBulkBindingDraftPreview, title: String = "Config connect-all preview") -> String {
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

    private func formatConnectAllApply(_ result: AgentBulkBindingDraftApplyResult) -> String {
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

    private func formatConnectAllRollback(_ result: AgentBulkConnectRollbackResult) -> String {
        var lines = [
            "Config connect-all rollback",
            result.summaryText,
            "Transaction: \(result.planID)",
            "",
        ]
        for target in result.restoredTargets {
            lines.append("## \(target.agentName)")
            lines.append("Source: \(target.source.agent.rawValue):\(target.source.path)")
            if target.shouldDeleteCreatedFile {
                lines.append("Action: deleted newly created config file")
            } else {
                lines.append("Action: restored backup \(target.backupPath ?? "unknown")")
            }
            lines.append("")
        }
        return SecretRedactor.redactConfigText(lines.joined(separator: "\n")) + "\n"
    }

    private func parseSource(_ value: String) -> ConfigSource? {
        guard let separatorIndex = value.firstIndex(of: ":") else { return nil }
        let agentValue = String(value[..<separatorIndex])
        let pathStart = value.index(after: separatorIndex)
        let path = String(value[pathStart...])
        guard !path.isEmpty, let agent = AgentID(rawValue: agentValue) else { return nil }
        return ConfigSource(agent: agent, path: path)
    }

    private func resolvedDoctorServerID(_ value: String?, in report: DoctorReport) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if report.findings.contains(where: { $0.serverID == value }) {
            return value
        }
        if let match = report.findings.first(where: { finding in
            finding.serverName?.localizedCaseInsensitiveCompare(value) == .orderedSame
        })?.serverID {
            return match
        }
        return value
    }

    private func doctorKeychainRecoveryReport(
        for result: ScanResult,
        sourcePath: String? = nil
    ) -> SecretRecoveryReport {
        guard let secretStore else {
            return SecretRecoveryReport(states: [])
        }

        let validatedAt = now()
        let persistedReport: SecretRecoveryReport
        if let scanHistoryStore {
            do {
                persistedReport = try scanHistoryStore.validateSecretBindings(
                    sourcePath: sourcePath,
                    store: secretStore,
                    validatedAt: validatedAt
                )
            } catch {
                persistedReport = SecretRecoveryReport(states: [])
            }
        } else {
            persistedReport = SecretRecoveryReport(states: [])
        }

        let persistedIDs = Set(persistedReport.states.compactMap(\.secretID))
        let records = Self.currentKeychainReferenceRecords(
            from: result.servers,
            sourcePath: sourcePath,
            validatedAt: validatedAt
        ).filter { !persistedIDs.contains($0.secretID) }
        let currentReport = SecretRecoveryReporter(store: secretStore).report(
            records: records,
            validatedAt: validatedAt
        )
        return SecretRecoveryReport(states: persistedReport.states + currentReport.states)
    }

    private static func currentKeychainReferenceRecords(
        from servers: [ServerDefinition],
        sourcePath: String?,
        validatedAt: Date
    ) -> [SQLiteSecretBindingRecord] {
        servers
            .filter { sourcePath == nil || $0.sourcePath == sourcePath }
            .flatMap { server in
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
                        updatedAt: validatedAt,
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
                        updatedAt: validatedAt,
                        validatedAt: nil
                    )
                }
                return envRecords + headerRecords
            }
    }

    private func runControl(args: [String]) throws -> MCPHQCommandResult {
        guard let action = args.first else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid control action\n\(usage())")
        }
        if action == "launch-agent" {
            return try runControlLaunchAgent(args: Array(args.dropFirst()))
        }
        guard action == "status" else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid control action\n\(usage())")
        }

        var outputJSON = false
        var shouldProbe = false
        var source: ConfigSource?
        var endpointFile: String?
        var index = 1
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--probe":
                shouldProbe = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard source == nil else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "control status accepts at most one --source\n\(usage())")
                }
                guard let parsedSource = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                source = parsedSource
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown control option: \(argument)\n\(usage())")
            }
        }

        let controlRequest = LocalControlRequest(
            route: .status,
            includeProbes: shouldProbe,
            source: source
        )
        let response = try sendLocalControlRequest(
            controlRequest,
            endpointFile: endpointFile,
            probeProvider: shouldProbe ? liveProbeProvider : probeProvider
        ).response
        guard let status = response.status else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Control status failed: \(response.error ?? "missing status response")")
        }

        let stdout = outputJSON ? try formatControlStatusJSON(status) : formatControlStatusText(status)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func sendLocalControlRequest(
        _ request: LocalControlRequest,
        endpointFile: String?,
        probeProvider: @escaping @Sendable ([ServerDefinition]) -> [MCPProbeResult]
    ) throws -> LocalControlClientExchange {
        try controlClientHelper.send(request, endpointFile: endpointFile) {
            let router = LocalControlRouter(
                defaultSourceProvider: defaultSourceProvider,
                scanCoordinator: ScanCoordinator(
                    processScanner: processScanner,
                    probeProvider: probeProvider,
                    secretStore: secretStore
                )
            )
            return LocalControlInProcessClient(router: router)
        }
    }

    private func runControlLaunchAgent(args: [String]) throws -> MCPHQCommandResult {
        guard let action = args.first else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing launch-agent action\n\(usage())")
        }

        var programPath = executablePath()
        var endpointFilePath = LocalControlEndpointStore.defaultStore().fileURL.path
        var launchAgentsDirectory: URL?
        var port: UInt16?
        var token: String?
        var requiresToken = true
        var dryRun = false
        var index = 1

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--program":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --program\n\(usage())")
                }
                programPath = args[index + 1]
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFilePath = args[index + 1]
                index += 2
            case "--launch-agents-dir":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --launch-agents-dir\n\(usage())")
                }
                launchAgentsDirectory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
                index += 2
            case "--port":
                guard index + 1 < args.count, let parsedPort = UInt16(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid value for --port\n\(usage())")
                }
                port = parsedPort
                index += 2
            case "--token":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --token\n\(usage())")
                }
                token = args[index + 1]
                requiresToken = true
                index += 2
            case "--no-token":
                token = nil
                requiresToken = false
                index += 1
            case "--dry-run":
                dryRun = true
                index += 1
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown launch-agent option: \(argument)\n\(usage())")
            }
        }

        let manager = LocalControlLaunchAgentManager(
            launchAgentsDirectory: launchAgentsDirectory ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            commandRunner: launchAgentCommandRunner
        )

        switch action {
        case "install":
            let configuration = LocalControlLaunchAgentConfiguration(
                programPath: programPath,
                endpointFilePath: endpointFilePath,
                port: port,
                token: token,
                requiresToken: requiresToken
            )
            let result = try manager.install(configuration, dryRun: dryRun)
            return MCPHQCommandResult(exitCode: 0, stdout: formatLaunchAgentInstall(result, action: dryRun ? "LaunchAgent install dry run" : "LaunchAgent install"), stderr: "")
        case "uninstall":
            let result = try manager.remove(dryRun: dryRun)
            return MCPHQCommandResult(exitCode: 0, stdout: formatLaunchAgentInstall(result, action: dryRun ? "LaunchAgent uninstall dry run" : "LaunchAgent uninstall"), stderr: "")
        case "bootstrap", "start":
            let result = try manager.bootstrap()
            return MCPHQCommandResult(
                exitCode: result.exitCode,
                stdout: formatLaunchAgentCommand(result, action: "LaunchAgent bootstrap"),
                stderr: ""
            )
        case "bootout", "stop":
            let result = try manager.bootout()
            return MCPHQCommandResult(
                exitCode: result.exitCode,
                stdout: formatLaunchAgentCommand(result, action: "LaunchAgent bootout"),
                stderr: ""
            )
        case "status":
            let endpointStore = LocalControlEndpointStore(fileURL: URL(fileURLWithPath: endpointFilePath))
            let status = manager.status(endpointStore: endpointStore, checkLaunchd: true)
            return MCPHQCommandResult(exitCode: 0, stdout: formatLaunchAgentStatus(status), stderr: "")
        default:
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid launch-agent action\n\(usage())")
        }
    }

    private func executablePath() -> String {
        if let executablePath = ProcessInfo.processInfo.arguments.first, !executablePath.isEmpty {
            return URL(fileURLWithPath: executablePath).standardizedFileURL.path
        }
        return "/usr/bin/env"
    }

    private func formatControlStatusText(_ status: LocalControlStatus) -> String {
        var lines = [
            "MCP-HQ control status",
            "",
            "Servers: \(status.serverCount)",
            "Sources: \(status.sourceCount)",
            "Processes: \(status.processCount)",
            "Issues: \(status.issueCount)",
            "Warnings: \(status.warningCount)",
            "Errors: \(status.errorCount)",
        ]
        if let scannedAt = status.scannedAt {
            lines.append("Scanned at: \(Self.formatISO8601(scannedAt))")
            let ageSeconds = status.cacheAgeSeconds ?? max(0, Int(now().timeIntervalSince(scannedAt)))
            lines.append("Cache age: \(HealthCacheAgeFormatter.duration(seconds: ageSeconds))")
        }
        if let servedFromHealthCache = status.servedFromHealthCache {
            lines.append("Health cache: \(servedFromHealthCache ? "served from cache" : "refreshed")")
        }
        if let freshness = status.cacheFreshness {
            lines.append("Cache freshness: \(freshness.rawValue)")
        }
        if status.cacheRefreshRecommended == true {
            lines.append("Cache refresh: recommended")
        }
        if let scanStatus = status.scanStatus {
            lines.append("Scan status: \(scanStatus.rawValue)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatControlStatusJSON(_ status: LocalControlStatus) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(status), encoding: .utf8) ?? "{}"
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func formatLaunchAgentInstall(_ result: LocalControlLaunchAgentInstallResult, action: String) -> String {
        [
            action,
            "Plist: \(result.plistPath)",
            "Did write: \(result.didWrite ? "yes" : "no")",
            "Bootstrap: \(result.bootstrapCommand)",
            "Stop: \(result.bootoutCommand)",
        ].joined(separator: "\n") + "\n"
    }

    private func formatLaunchAgentCommand(_ result: LocalControlLaunchAgentCommandResult, action: String) -> String {
        var lines = [
            action,
            "Command: \(result.command.joined(separator: " "))",
            "Exit code: \(result.exitCode)",
        ]
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            lines.append("stdout:")
            lines.append(stdout)
        }
        if !stderr.isEmpty {
            lines.append("stderr:")
            lines.append(stderr)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatLaunchAgentStatus(_ status: LocalControlLaunchAgentStatus) -> String {
        var lines = [
            "MCP-HQ control LaunchAgent",
            "Plist: \(status.plistPath)",
            "Installed: \(status.isInstalled ? "yes" : "no")",
            "Launchd: \(status.launchdState.rawValue)",
        ]
        if let endpoint = status.endpoint {
            lines.append("Endpoint: \(endpoint.controlURL.absoluteString)")
            lines.append("PID: \(endpoint.pid)")
        } else {
            lines.append("Endpoint: unavailable")
        }
        if let launchdMessage = status.launchdMessage {
            lines.append("Launchd details:")
            lines.append(launchdMessage)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func runHistory(args: [String]) throws -> MCPHQCommandResult {
        guard let action = args.first, ["list", "show", "doctor"].contains(action) else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid history action\n\(usage())")
        }

        if action == "show" {
            return try runHistoryShow(args: Array(args.dropFirst()))
        }
        if action == "doctor" {
            return try runHistoryDoctor(args: Array(args.dropFirst()))
        }
        return try runHistoryList(args: Array(args.dropFirst()))
    }

    private func runHistoryList(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var limit = 10
        var index = 0
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--limit", "-n":
                guard index + 1 < args.count,
                      let parsedLimit = Int(args[index + 1]),
                      parsedLimit >= 0 else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid value for \(argument)\n\(usage())")
                }
                limit = parsedLimit
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown history option: \(argument)\n\(usage())")
            }
        }

        guard let scanHistoryStore else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "History store unavailable")
        }
        let summaries = try scanHistoryStore.listRunSummaries(limit: limit)
        let stdout = outputJSON ? try formatHistorySummariesJSON(summaries) : formatHistorySummariesText(summaries)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func runHistoryDoctor(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var limit = 10
        var runID: String?
        var index = 0
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--limit", "-n":
                guard runID == nil,
                      index + 1 < args.count,
                      let parsedLimit = Int(args[index + 1]),
                      parsedLimit >= 0 else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid value for \(argument)\n\(usage())")
                }
                limit = parsedLimit
                index += 2
            default:
                guard !argument.hasPrefix("-"), runID == nil else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown history doctor option: \(argument)\n\(usage())")
                }
                runID = argument
                index += 1
            }
        }

        guard let scanHistoryStore else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "History store unavailable")
        }

        if let runID {
            guard let stored = try scanHistoryStore.loadDoctorReport(runID: runID) else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Doctor report not found: \(runID)")
            }
            let stdout = outputJSON
                ? try formatDoctorHistoryRunJSON(stored)
                : formatDoctorHistoryRunText(stored)
            return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
        }

        let summaries = try scanHistoryStore.listDoctorReportSummaries(limit: limit)
        let stdout = outputJSON ? try encodeJSON(summaries) : formatDoctorHistorySummariesText(summaries)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func runHistoryShow(args: [String]) throws -> MCPHQCommandResult {
        var outputJSON = false
        var runID: String?
        var index = 0
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            default:
                guard !argument.hasPrefix("-"), runID == nil else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown history option: \(argument)\n\(usage())")
                }
                runID = argument
                index += 1
            }
        }

        guard let runID else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing history run id\n\(usage())")
        }
        guard let scanHistoryStore else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "History store unavailable")
        }
        guard let stored = try scanHistoryStore.load(runID: runID) else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "History run not found: \(runID)")
        }

        let stdout = outputJSON
            ? try formatHistoryRunJSON(runID: runID, stored: stored)
            : formatHistoryRunText(runID: runID, stored: stored)
        return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func formatHistorySummariesText(_ summaries: [SQLiteScanHistoryRunSummary]) -> String {
        var lines = ["MCP-HQ history", ""]
        guard !summaries.isEmpty else {
            lines.append("No scan history found.")
            return lines.joined(separator: "\n") + "\n"
        }

        let dateFormatter = ISO8601DateFormatter()
        for summary in summaries {
            lines.append("\(dateFormatter.string(from: summary.scannedAt))  \(summary.runID)")
            lines.append("  Sources: \(summary.sourceCount)")
            lines.append("  Servers: \(summary.serverCount)")
            lines.append("  Findings: \(summary.findingCount)")
            lines.append("  Processes: \(summary.processCount)")
            lines.append("  Probes: \(summary.probeCount)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatHistorySummariesJSON(_ summaries: [SQLiteScanHistoryRunSummary]) throws -> String {
        try encodeJSON(summaries)
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw ScanOutputFormatterError.invalidUTF8
        }
        return text + "\n"
    }

    private func formatHistoryRunText(runID: String, stored: StoredScanResult) -> String {
        let dateFormatter = ISO8601DateFormatter()
        return [
            "MCP-HQ history run",
            "",
            "Run: \(runID)",
            "Scanned at: \(dateFormatter.string(from: stored.scannedAt))",
            "",
            formatter.formatText(stored.result)
        ].joined(separator: "\n") + "\n"
    }

    private func formatHistoryRunJSON(runID: String, stored: StoredScanResult) throws -> String {
        let scanJSON = try formatter.formatJSON(stored.result)
        guard let scanData = scanJSON.data(using: .utf8),
              let scanObject = try JSONSerialization.jsonObject(with: scanData) as? [String: Any] else {
            throw ScanOutputFormatterError.invalidUTF8
        }

        let dateFormatter = ISO8601DateFormatter()
        let object: [String: Any] = [
            "runID": runID,
            "scannedAt": dateFormatter.string(from: stored.scannedAt),
            "scan": scanObject
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ScanOutputFormatterError.invalidUTF8
        }
        return text + "\n"
    }

    private func formatDoctorHistorySummariesText(_ summaries: [SQLiteDoctorReportSummary]) -> String {
        var lines = ["MCP-HQ Doctor history", ""]
        guard !summaries.isEmpty else {
            lines.append("No Doctor report history found.")
            return lines.joined(separator: "\n") + "\n"
        }

        let dateFormatter = ISO8601DateFormatter()
        for summary in summaries {
            lines.append("\(dateFormatter.string(from: summary.reportedAt))  \(summary.runID)")
            lines.append("  Scanned: \(dateFormatter.string(from: summary.scannedAt))")
            lines.append("  Findings: \(summary.findingCount)")
            lines.append("  Errors: \(summary.errorCount)")
            lines.append("  Warnings: \(summary.warningCount)")
            lines.append("  Info: \(summary.infoCount)")
            lines.append("  Sources: \(summary.sourceCount)")
            lines.append("  Servers: \(summary.serverCount)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatDoctorHistoryRunText(_ stored: SQLiteStoredDoctorReport) -> String {
        let dateFormatter = ISO8601DateFormatter()
        return [
            "MCP-HQ Doctor history report",
            "",
            "Run: \(stored.runID)",
            "Scanned at: \(dateFormatter.string(from: stored.scannedAt))",
            "Reported at: \(dateFormatter.string(from: stored.reportedAt))",
            "",
            DoctorReportFormatter().formatText(stored.report)
        ].joined(separator: "\n") + "\n"
    }

    private func formatDoctorHistoryRunJSON(_ stored: SQLiteStoredDoctorReport) throws -> String {
        let reportJSON = try DoctorReportFormatter().formatJSON(stored.report)
        guard let reportData = reportJSON.data(using: .utf8),
              let reportObject = try JSONSerialization.jsonObject(with: reportData) as? [String: Any] else {
            throw ScanOutputFormatterError.invalidUTF8
        }

        let dateFormatter = ISO8601DateFormatter()
        let object: [String: Any] = [
            "runID": stored.runID,
            "scannedAt": dateFormatter.string(from: stored.scannedAt),
            "reportedAt": dateFormatter.string(from: stored.reportedAt),
            "doctor": reportObject
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ScanOutputFormatterError.invalidUTF8
        }
        return text + "\n"
    }

    private enum RegistryAction: String {
        case agents
        case sources
        case desired
        case backups
        case rollbacks
        case targetProfiles = "target-profiles"
        case runtimes
        case secrets
    }

    private func runRegistry(args: [String]) throws -> MCPHQCommandResult {
        guard let action = args.first.flatMap(RegistryAction.init(rawValue:)) else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid registry action\n\(usage())")
        }

        var outputJSON = false
        var source: ConfigSource?
        var validateKeychain = false
        var index = 1
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--validate", "--validate-keychain":
                validateKeychain = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let parsedSource = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                source = parsedSource
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown registry option: \(argument)\n\(usage())")
            }
        }

        guard let scanHistoryStore else {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Registry store unavailable")
        }

        switch action {
        case .agents:
            let records = try scanHistoryStore.listAgentRecords()
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatAgentRegistryText(records),
                stderr: ""
            )
        case .sources:
            let records = try scanHistoryStore.listSourceBindings()
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatSourceBindingsText(records),
                stderr: ""
            )
        case .desired:
            let records = try scanHistoryStore.listDesiredServerStates(source: source)
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatDesiredServerStatesText(records),
                stderr: ""
            )
        case .backups:
            let records = try scanHistoryStore.listConfigBackups(source: source)
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatConfigBackupsText(records),
                stderr: ""
            )
        case .rollbacks:
            let records = try scanHistoryStore.listBulkRollbackTransactions()
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatBulkRollbackTransactionsText(records),
                stderr: ""
            )
        case .targetProfiles:
            let records = try scanHistoryStore.listConnectAllTargetProfiles()
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatConnectAllTargetProfilesText(records),
                stderr: ""
            )
        case .runtimes:
            let records = try scanHistoryStore.listRuntimeInstanceRecords()
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatRuntimeRegistryText(records),
                stderr: ""
            )
        case .secrets:
            if validateKeychain {
                guard let secretStore else {
                    return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Keychain validation unavailable")
                }
                let report = try scanHistoryStore.validateSecretBindings(sourcePath: source?.path, store: secretStore)
                return MCPHQCommandResult(
                    exitCode: 0,
                    stdout: outputJSON ? try encodeJSON(report) : formatSecretRecoveryReportText(report),
                    stderr: ""
                )
            }
            let records = try scanHistoryStore.listSecretBindingRecords(sourcePath: source?.path)
            return MCPHQCommandResult(
                exitCode: 0,
                stdout: outputJSON ? try encodeJSON(records) : formatSecretBindingsText(records),
                stderr: ""
            )
        }
    }

    private func formatAgentRegistryText(_ records: [SQLiteAgentRecord]) -> String {
        var lines = ["MCP-HQ registry agents", ""]
        guard !records.isEmpty else {
            lines.append("No agent registry rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        for record in records {
            lines.append("\(record.displayName) (\(record.agent.rawValue))")
            lines.append("  Format: \(record.configFormat.rawValue)")
            lines.append("  Parser: \(record.parserStatus.rawValue)")
            lines.append("  Renderer: \(record.rendererStatus.rawValue)")
            lines.append("  Config paths: \(record.configPaths.count)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatSourceBindingsText(_ records: [SQLiteSourceBindingRecord]) -> String {
        var lines = ["MCP-HQ registry sources", ""]
        guard !records.isEmpty else {
            lines.append("No source binding rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            lines.append("\(AgentRegistry.displayName(for: record.source.agent)) \(record.state?.rawValue ?? "unknown")")
            lines.append("  Path: \(record.source.path)")
            lines.append("  Servers: \(record.serverCount)")
            lines.append("  Last seen: \(dateFormatter.string(from: record.lastSeenAt))")
            if let lastRunID = record.lastRunID {
                lines.append("  Run: \(lastRunID)")
            }
            if !record.message.isEmpty {
                lines.append("  Message: \(record.message)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatDesiredServerStatesText(_ records: [SQLiteDesiredServerState]) -> String {
        var lines = ["MCP-HQ registry desired servers", ""]
        guard !records.isEmpty else {
            lines.append("No desired server rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            lines.append("\(record.serverName) \(record.enabled ? "enabled" : "disabled")")
            lines.append("  Agent: \(AgentRegistry.displayName(for: record.source.agent))")
            lines.append("  Path: \(record.source.path)")
            lines.append("  Transport: \(record.server.transport.rawValue)")
            lines.append("  Updated: \(dateFormatter.string(from: record.updatedAt))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatConfigBackupsText(_ records: [SQLiteConfigBackupRecord]) -> String {
        var lines = ["MCP-HQ registry config backups", ""]
        guard !records.isEmpty else {
            lines.append("No config backup rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            lines.append("\(dateFormatter.string(from: record.createdAt))  \(record.backupID)")
            lines.append("  Agent: \(AgentRegistry.displayName(for: record.source.agent))")
            lines.append("  Source: \(record.source.path)")
            lines.append("  Backup: \(record.backupPath)")
            lines.append("  Reason: \(record.reason)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatBulkRollbackTransactionsText(_ records: [SQLiteBulkRollbackTransactionRecord]) -> String {
        var lines = ["MCP-HQ registry bulk rollback transactions", ""]
        guard !records.isEmpty else {
            lines.append("No bulk rollback transactions found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            lines.append("\(dateFormatter.string(from: record.createdAt))  \(record.transactionID)")
            lines.append("  Status: \(record.status)")
            lines.append("  Reason: \(record.reason)")
            lines.append("  Targets: \(record.plan.targets.count)")
            for target in record.plan.targets {
                lines.append("    \(target.agentName): \(target.source.path)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatConnectAllTargetProfilesText(_ records: [SQLiteConnectAllTargetProfileRecord]) -> String {
        var lines = ["MCP-HQ registry Connect All target profiles", ""]
        guard !records.isEmpty else {
            lines.append("No Connect All target profiles found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            let targetWord = record.targetSources.count == 1 ? "target" : "targets"
            lines.append("\(record.name) (\(record.targetSources.count) \(targetWord))")
            lines.append("  Updated: \(dateFormatter.string(from: record.updatedAt))")
            for source in record.targetSources {
                lines.append("  - \(source.agent.rawValue):\(source.path)")
            }
        }
        return SecretRedactor.redactConfigText(lines.joined(separator: "\n")) + "\n"
    }

    private func formatRuntimeRegistryText(_ records: [SQLiteRuntimeInstanceRecord]) -> String {
        var lines = ["MCP-HQ registry runtimes", ""]
        guard !records.isEmpty else {
            lines.append("No runtime rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            let instance = record.instance
            lines.append("\(instance.id) \(instance.status.rawValue)")
            lines.append("  Ownership: \(instance.ownership.rawValue)")
            if let pid = instance.pid {
                lines.append("  PID: \(pid)")
            }
            if let serverID = instance.serverID {
                lines.append("  Server: \(serverID)")
            }
            if let logPath = instance.logPath {
                lines.append("  Log: \(logPath)")
            }
            lines.append("  Updated: \(dateFormatter.string(from: record.updatedAt))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatSecretBindingsText(_ records: [SQLiteSecretBindingRecord]) -> String {
        var lines = ["MCP-HQ registry secrets", ""]
        guard !records.isEmpty else {
            lines.append("No secret binding rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        for record in records {
            lines.append("\(record.fieldName) \(record.status)")
            lines.append("  Source: \(record.sourcePath)")
            if let serverName = record.serverName {
                lines.append("  Server: \(serverName)")
            }
            lines.append("  Field: \(record.fieldKind.rawValue)")
            lines.append("  Service: \(record.reference.service)")
            lines.append("  Account: \(record.reference.account)")
            lines.append("  Updated: \(dateFormatter.string(from: record.updatedAt))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatSecretRecoveryReportText(_ report: SecretRecoveryReport) -> String {
        var lines = ["MCP-HQ registry secrets", ""]
        guard !report.states.isEmpty else {
            lines.append("No secret binding rows found.")
            return lines.joined(separator: "\n") + "\n"
        }
        let dateFormatter = ISO8601DateFormatter()
        lines.append("Keychain validation: \(report.checkedCount) checked, \(report.presentCount) present, \(report.missingCount) missing, \(report.inaccessibleCount) inaccessible, \(report.migrationWriteFailureCount) migration write failed")
        lines.append("")
        for state in report.states {
            lines.append("\(state.fieldName) \(state.recoveryStatus.rawValue)")
            lines.append("  Source: \(state.sourcePath)")
            if let serverName = state.serverName {
                lines.append("  Server: \(serverName)")
            }
            lines.append("  Field: \(state.fieldKind.rawValue)")
            lines.append("  Service: \(state.reference.service)")
            lines.append("  Account: \(state.reference.account)")
            if let previousStatus = state.previousStatus {
                lines.append("  Previous status: \(previousStatus)")
            }
            if let validatedAt = state.validatedAt {
                lines.append("  Validated: \(dateFormatter.string(from: validatedAt))")
            }
            lines.append("  Summary: \(state.summary)")
            lines.append("  Safe action: \(state.safeAction)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func runRuntime(args: [String]) throws -> MCPHQCommandResult {
        guard let action = args.first else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid runtime action\n\(usage())")
        }
        guard ["explain", "start", "stop", "restart"].contains(action) else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid runtime action\n\(usage())")
        }

        var outputJSON = false
        var explicitSources: [ConfigSource] = []
        var serverName: String?
        var runtimeInstanceID: String?
        var logDirectory: String?
        var endpointFile: String?
        var index = 1
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--source":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --source\n\(usage())")
                }
                guard let source = parseSource(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Invalid --source value: \(args[index + 1])\n\(usage())")
                }
                explicitSources.append(source)
                index += 2
            case "--server":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --server\n\(usage())")
                }
                serverName = args[index + 1]
                index += 2
            case "--runtime-id":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --runtime-id\n\(usage())")
                }
                runtimeInstanceID = args[index + 1]
                index += 2
            case "--log-directory":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --log-directory\n\(usage())")
                }
                logDirectory = args[index + 1]
                index += 2
            case "--endpoint-file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --endpoint-file\n\(usage())")
                }
                endpointFile = args[index + 1]
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown runtime option: \(argument)\n\(usage())")
            }
        }

        if endpointFile != nil, explicitSources.count > 1, action == "explain" {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime explain accepts at most one --source with --endpoint-file\n\(usage())")
        }

        switch action {
        case "explain":
            let explanations: [RuntimeLifecycleExplanation]
            if let endpointFile {
                let response = try sendLocalControlRequest(
                    LocalControlRequest(route: .runtimeExplain, source: explicitSources.first),
                    endpointFile: endpointFile,
                    probeProvider: probeProvider
                ).response
                guard let remoteExplanations = response.runtimeExplanations else {
                    return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Runtime explain failed: \(response.error ?? "missing runtime explain response")")
                }
                explanations = remoteExplanations
            } else {
                let sources = explicitSources.isEmpty ? defaultSourceProvider.sources() : explicitSources
                let result = ScanCoordinator(processScanner: processScanner, probeProvider: probeProvider, secretStore: secretStore)
                    .scan(sources: sources, includeProbes: false)
                let storedInstances = ((try? scanHistoryStore?.listRuntimeInstanceRecords(ownership: .hubOwned)) ?? [])
                    .map(\.instance)
                explanations = RuntimeLifecycleExplainer().explain(scanResult: result, knownHubRuntimes: storedInstances)
            }
            let stdout = outputJSON ? try formatRuntimeExplanationsJSON(explanations) : formatRuntimeExplanationsText(explanations)
            return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
        case "start", "restart":
            guard let endpointFile else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime \(action) requires --endpoint-file so hub-owned processes are supervised by the helper\n\(usage())")
            }
            guard let source = explicitSources.first, explicitSources.count == 1 else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime \(action) requires exactly one --source\n\(usage())")
            }
            guard let serverName, !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime \(action) requires --server\n\(usage())")
            }
            guard let logDirectory, !logDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime \(action) requires --log-directory\n\(usage())")
            }
            if action == "restart", runtimeInstanceID == nil {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime restart requires --runtime-id\n\(usage())")
            }
            let server = try loadServer(named: serverName, from: source)
            let response = try sendLocalControlRequest(
                LocalControlRequest(
                    route: action == "start" ? .runtimeStart : .runtimeRestart,
                    runtimeInstanceID: runtimeInstanceID,
                    server: server,
                    logDirectory: logDirectory
                ),
                endpointFile: endpointFile,
                probeProvider: probeProvider
            ).response
            guard let instance = response.runtimeInstance else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Runtime \(action) failed: \(response.error ?? "missing runtime response")")
            }
            let stdout = outputJSON ? try formatRuntimeInstanceJSON(instance) : formatRuntimeActionText(action: action, instance: instance)
            return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
        case "stop":
            guard let endpointFile else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime stop requires --endpoint-file so hub-owned processes are supervised by the helper\n\(usage())")
            }
            guard let runtimeInstanceID, !runtimeInstanceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "runtime stop requires --runtime-id\n\(usage())")
            }
            let response = try sendLocalControlRequest(
                LocalControlRequest(route: .runtimeStop, runtimeInstanceID: runtimeInstanceID),
                endpointFile: endpointFile,
                probeProvider: probeProvider
            ).response
            guard let instance = response.runtimeInstance else {
                return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Runtime stop failed: \(response.error ?? "missing runtime response")")
            }
            let stdout = outputJSON ? try formatRuntimeInstanceJSON(instance) : formatRuntimeActionText(action: action, instance: instance)
            return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
        default:
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid runtime action\n\(usage())")
        }
    }

    private func loadServer(named name: String, from source: ConfigSource) throws -> ServerDefinition {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let servers = try loadServers(from: source)
        if let exact = servers.first(where: { $0.id == needle || $0.displayName == needle }) {
            return exact
        }
        if let insensitive = servers.first(where: {
            $0.displayName.localizedCaseInsensitiveCompare(needle) == .orderedSame
                || $0.id.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) {
            return insensitive
        }
        throw ConfigCommandError.serverNotFound(needle, source)
    }

    private func runLogs(args: [String]) -> MCPHQCommandResult {
        var outputJSON = false
        var filePath: String?
        var runtimeInstanceID = "manual"
        var lineLimit = 100
        var index = 0

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--file":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --file\n\(usage())")
                }
                filePath = args[index + 1]
                index += 2
            case "--runtime-id":
                guard index + 1 < args.count else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing value for --runtime-id\n\(usage())")
                }
                runtimeInstanceID = args[index + 1]
                index += 2
            case "--lines":
                guard index + 1 < args.count, let parsedLimit = Int(args[index + 1]) else {
                    return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing or invalid value for --lines\n\(usage())")
                }
                lineLimit = parsedLimit
                index += 2
            default:
                return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Unknown logs option: \(argument)\n\(usage())")
            }
        }

        guard let filePath else {
            return MCPHQCommandResult(exitCode: 2, stdout: "", stderr: "Missing required --file\n\(usage())")
        }

        do {
            let request = RuntimeLogTailRequest(runtimeInstanceID: runtimeInstanceID, filePath: filePath, lineLimit: lineLimit)
            let result = try logTailer.tail(request: request)
            let stdout = outputJSON ? try formatLogTailJSON(result) : formatLogTailText(result)
            return MCPHQCommandResult(exitCode: 0, stdout: stdout, stderr: "")
        } catch {
            return MCPHQCommandResult(exitCode: 1, stdout: "", stderr: "Logs failed: \(error)")
        }
    }

    private func formatRuntimeExplanationsText(_ explanations: [RuntimeLifecycleExplanation]) -> String {
        var lines = ["MCP-HQ runtime", ""]
        if explanations.isEmpty {
            lines.append("No MCP-like runtime processes found.")
            return lines.joined(separator: "\n") + "\n"
        }

        for explanation in explanations {
            let pidText = explanation.pid.map(String.init) ?? "no pid"
            lines.append("\(explanation.runtimeInstanceID) (\(pidText))")
            if let serverID = explanation.serverID {
                lines.append("  server: \(serverID)")
            }
            lines.append("  ownership: \(explanation.ownership.displayLabel)")
            lines.append("  status: \(explanation.status.rawValue)")
            lines.append("  control: \(explanation.controlSummary)")
            lines.append("  logs: \(explanation.logSummary)")
            for capability in explanation.capabilities {
                let availability = capability.isAvailable ? "available" : "disabled"
                lines.append("  \(capability.action.rawValue): \(availability) - \(capability.reason)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatRuntimeExplanationsJSON(_ explanations: [RuntimeLifecycleExplanation]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(explanations), encoding: .utf8) ?? "[]"
    }

    private func formatRuntimeActionText(action: String, instance: RuntimeInstance) -> String {
        [
            "MCP-HQ runtime \(action)",
            "Runtime: \(instance.id)",
            "Server: \(instance.serverID ?? "none")",
            "PID: \(instance.pid.map(String.init) ?? "none")",
            "Ownership: \(instance.ownership.displayLabel)",
            "Status: \(instance.status.rawValue)",
            "Logs: \(instance.logPath.map(SecretRedactor.redactText) ?? "none")",
        ].joined(separator: "\n") + "\n"
    }

    private func formatRuntimeInstanceJSON(_ instance: RuntimeInstance) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(instance), encoding: .utf8) ?? "{}"
    }

    private func formatLogTailText(_ result: RuntimeLogTailResult) -> String {
        var lines = [
            "MCP-HQ logs",
            "Runtime: \(result.runtimeInstanceID)",
            "File: \(result.filePath)",
            "Truncated: \(result.truncated ? "yes" : "no")",
            "",
        ]
        lines.append(contentsOf: result.entries.map { entry in
            "[\(entry.stream.rawValue)] \(entry.message)"
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatLogTailJSON(_ result: RuntimeLogTailResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(result), encoding: .utf8) ?? "{}"
    }

    private func usage() -> String {
        """
        Usage:
          mcphq scan [--json] [--probe] [--source agent:/path/to/config] [--endpoint-file path]
          mcphq doctor [--json] [--probe] [--source agent:/path/to/config] [--endpoint-file path] [--severity error|warning|info] [--category source|config|server|probe] [--source-path path] [--server id-or-name]
          mcphq config preview --source agent:/path/to/target [--server-source agent:/path/to/source] [--endpoint-file path]
          mcphq config apply --source agent:/path/to/target [--server-source agent:/path/to/source] [--dry-run] [--endpoint-file path]
          mcphq config connect-all preview --template-source agent:/path/to/source [--target-source agent:/path/to/target...] [--profile name] [--save-profile name] [--endpoint-file path]
          mcphq config connect-all apply --template-source agent:/path/to/source [--target-source agent:/path/to/target...] [--profile name] [--save-profile name] [--dry-run] [--probe] [--endpoint-file path]
          mcphq config connect-all rollback --transaction-id id
          mcphq control status [--json] [--probe] [--source agent:/path/to/config] [--endpoint-file path]
          mcphq control serve [--port port] [--token token|--no-token] [--endpoint-file path]
          mcphq control launch-agent install [--program path] [--port port] [--token token|--no-token] [--dry-run]
          mcphq control launch-agent bootstrap
          mcphq control launch-agent bootout
          mcphq control launch-agent uninstall [--dry-run]
          mcphq control launch-agent status
          mcphq history list [--json] [--limit count]
          mcphq history show run-id [--json]
          mcphq history doctor [run-id] [--json] [--limit count]
          mcphq registry agents|sources|desired|backups|rollbacks|target-profiles|runtimes|secrets [--json] [--source agent:/path/to/config]
          mcphq runtime explain [--json] [--source agent:/path/to/config] [--endpoint-file path]
          mcphq runtime start --source agent:/path/to/config --server name --log-directory path --endpoint-file path [--json]
          mcphq runtime stop --runtime-id id --endpoint-file path [--json]
          mcphq runtime restart --runtime-id id --source agent:/path/to/config --server name --log-directory path --endpoint-file path [--json]
          mcphq logs --file /path/to/log [--runtime-id id] [--lines count] [--json]

        Examples:
          mcphq scan
          mcphq scan --json
          mcphq scan --probe
          mcphq doctor
          mcphq doctor --json
          mcphq doctor --severity warning --server github
          mcphq scan --source claude:/Users/me/.config/claude.json
          mcphq doctor --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json
          mcphq config preview --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json
          mcphq config apply --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json --dry-run
          mcphq config connect-all preview --template-source hermes:/tmp/hermes.yaml --target-source claude:/tmp/claude.json --target-source codex:/tmp/config.toml --save-profile local
          mcphq config preview --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json --source claude:/tmp/claude.json --server-source pi:/tmp/pi.json
          mcphq control status --json
          mcphq control status --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json
          mcphq control serve --port 37373
          mcphq control launch-agent install --program /usr/local/bin/mcphq --dry-run
          mcphq control launch-agent bootstrap
          mcphq history list --limit 5
          mcphq history show 00000000-0000-0000-0000-000000000000 --json
          mcphq history doctor --limit 5
          mcphq history doctor 00000000-0000-0000-0000-000000000000 --json
          mcphq registry sources
          mcphq registry desired --json
          mcphq registry runtimes
          mcphq registry secrets --json
          mcphq registry secrets --validate
          mcphq runtime explain
          mcphq runtime explain --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json
          mcphq runtime start --source hermes:~/.hermes/config.yaml --server memory --log-directory ~/Library/Application\\ Support/MCP-HQ/logs --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json
          mcphq runtime stop --runtime-id hub:<server-id-from-start-output> --endpoint-file ~/Library/Application\\ Support/MCP-HQ/control-endpoint.json
          mcphq logs --file ~/Library/ApplicationSupport/MCP-HQ/logs/server.log --lines 50
        """
    }
}

public struct MCPHQCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
