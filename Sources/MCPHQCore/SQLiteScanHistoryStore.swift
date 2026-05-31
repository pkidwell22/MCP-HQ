import Foundation
import SQLite3

public struct SQLiteScanHistoryCounts: Equatable, Sendable {
    public let runCount: Int
    public let sourceCount: Int
    public let serverCount: Int
    public let findingCount: Int
    public let processSnapshotCount: Int

    public init(
        runCount: Int,
        sourceCount: Int,
        serverCount: Int,
        findingCount: Int,
        processSnapshotCount: Int
    ) {
        self.runCount = runCount
        self.sourceCount = sourceCount
        self.serverCount = serverCount
        self.findingCount = findingCount
        self.processSnapshotCount = processSnapshotCount
    }
}

public struct SQLiteScanHistoryRunSummary: Codable, Equatable, Sendable {
    public let runID: String
    public let scannedAt: Date
    public let sourceCount: Int
    public let serverCount: Int
    public let findingCount: Int
    public let processCount: Int
    public let probeCount: Int

    public init(
        runID: String,
        scannedAt: Date,
        sourceCount: Int,
        serverCount: Int,
        findingCount: Int,
        processCount: Int,
        probeCount: Int
    ) {
        self.runID = runID
        self.scannedAt = scannedAt
        self.sourceCount = sourceCount
        self.serverCount = serverCount
        self.findingCount = findingCount
        self.processCount = processCount
        self.probeCount = probeCount
    }
}

public struct SQLiteDoctorReportSummary: Codable, Equatable, Sendable {
    public let runID: String
    public let scannedAt: Date
    public let reportedAt: Date
    public let findingCount: Int
    public let errorCount: Int
    public let warningCount: Int
    public let infoCount: Int
    public let sourceCount: Int
    public let serverCount: Int

    public init(
        runID: String,
        scannedAt: Date,
        reportedAt: Date,
        findingCount: Int,
        errorCount: Int,
        warningCount: Int,
        infoCount: Int,
        sourceCount: Int,
        serverCount: Int
    ) {
        self.runID = runID
        self.scannedAt = scannedAt
        self.reportedAt = reportedAt
        self.findingCount = findingCount
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.infoCount = infoCount
        self.sourceCount = sourceCount
        self.serverCount = serverCount
    }
}

public struct SQLiteStoredDoctorReport: Codable, Equatable, Sendable {
    public let runID: String
    public let scannedAt: Date
    public let reportedAt: Date
    public let report: DoctorReport

    public init(runID: String, scannedAt: Date, reportedAt: Date, report: DoctorReport) {
        self.runID = runID
        self.scannedAt = scannedAt
        self.reportedAt = reportedAt
        self.report = report
    }
}

public struct SQLiteAgentRecord: Codable, Equatable, Sendable {
    public let agent: AgentID
    public let displayName: String
    public let configFormat: AgentConfigFormat
    public let parserStatus: AgentCapabilityStatus
    public let rendererStatus: AgentCapabilityStatus
    public let configPaths: [String]
    public let launchContextNotes: String
    public let updatedAt: Date

    public init(
        agent: AgentID,
        displayName: String,
        configFormat: AgentConfigFormat,
        parserStatus: AgentCapabilityStatus,
        rendererStatus: AgentCapabilityStatus,
        configPaths: [String],
        launchContextNotes: String,
        updatedAt: Date
    ) {
        self.agent = agent
        self.displayName = displayName
        self.configFormat = configFormat
        self.parserStatus = parserStatus
        self.rendererStatus = rendererStatus
        self.configPaths = configPaths
        self.launchContextNotes = launchContextNotes
        self.updatedAt = updatedAt
    }
}

public struct SQLiteSourceBindingRecord: Codable, Equatable, Sendable {
    public let source: ConfigSource
    public let state: ConfigSourceState?
    public let serverCount: Int
    public let message: String
    public let lastRunID: String?
    public let lastSeenAt: Date

    public init(
        source: ConfigSource,
        state: ConfigSourceState?,
        serverCount: Int,
        message: String,
        lastRunID: String?,
        lastSeenAt: Date
    ) {
        self.source = source
        self.state = state
        self.serverCount = serverCount
        self.message = message
        self.lastRunID = lastRunID
        self.lastSeenAt = lastSeenAt
    }
}

public struct SQLiteDesiredServerState: Codable, Equatable, Sendable {
    public let source: ConfigSource
    public let serverName: String
    public let enabled: Bool
    public let server: ServerDefinition
    public let updatedAt: Date

    public init(source: ConfigSource, serverName: String, enabled: Bool, server: ServerDefinition, updatedAt: Date) {
        self.source = source
        self.serverName = serverName
        self.enabled = enabled
        self.server = server
        self.updatedAt = updatedAt
    }
}

public struct SQLiteConfigBackupRecord: Codable, Equatable, Sendable {
    public let backupID: String
    public let source: ConfigSource
    public let backupPath: String
    public let reason: String
    public let runID: String?
    public let createdAt: Date

    public init(
        backupID: String,
        source: ConfigSource,
        backupPath: String,
        reason: String,
        runID: String?,
        createdAt: Date
    ) {
        self.backupID = backupID
        self.source = source
        self.backupPath = backupPath
        self.reason = reason
        self.runID = runID
        self.createdAt = createdAt
    }
}

public struct SQLiteBulkRollbackTransactionRecord: Codable, Equatable, Sendable {
    public let transactionID: String
    public let status: String
    public let reason: String
    public let plan: AgentBulkConnectRollbackPlan
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        transactionID: String,
        status: String,
        reason: String,
        plan: AgentBulkConnectRollbackPlan,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.transactionID = transactionID
        self.status = SecretRedactor.redactText(status)
        self.reason = SecretRedactor.redactText(reason)
        self.plan = plan
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SQLiteConnectAllTargetProfileRecord: Codable, Equatable, Sendable {
    public let name: String
    public let targetSources: [ConfigSource]
    public let updatedAt: Date

    public init(name: String, targetSources: [ConfigSource], updatedAt: Date) {
        self.name = SecretRedactor.redactText(name)
        self.targetSources = targetSources
        self.updatedAt = updatedAt
    }
}

public struct SQLiteRuntimeInstanceRecord: Codable, Equatable, Sendable {
    public let instance: RuntimeInstance
    public let updatedAt: Date

    public init(instance: RuntimeInstance, updatedAt: Date) {
        self.instance = instance
        self.updatedAt = updatedAt
    }
}

public struct SQLiteSecretBindingRecord: Codable, Equatable, Sendable {
    public let secretID: String
    public let sourcePath: String
    public let serverName: String?
    public let fieldKind: SecretFieldKind
    public let fieldName: String
    public let reference: KeychainSecretReference
    public let status: String
    public let updatedAt: Date
    public let validatedAt: Date?

    public init(
        secretID: String,
        sourcePath: String,
        serverName: String?,
        fieldKind: SecretFieldKind,
        fieldName: String,
        reference: KeychainSecretReference,
        status: String,
        updatedAt: Date,
        validatedAt: Date?
    ) {
        self.secretID = secretID
        self.sourcePath = sourcePath
        self.serverName = serverName
        self.fieldKind = fieldKind
        self.fieldName = fieldName
        self.reference = reference
        self.status = status
        self.updatedAt = updatedAt
        self.validatedAt = validatedAt
    }
}

public enum SQLiteScanHistoryStoreError: Error, Equatable, CustomStringConvertible {
    case invalidApplicationSupportDirectory
    case invalidUTF8
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case executionFailed(String)

    public var description: String {
        switch self {
        case .invalidApplicationSupportDirectory:
            return "Could not resolve the Application Support directory"
        case .invalidUTF8:
            return "SQLite scan history payload was not valid UTF-8"
        case .openFailed(let message):
            return "Could not open SQLite scan history: \(message)"
        case .prepareFailed(let message):
            return "Could not prepare SQLite statement: \(message)"
        case .bindFailed(let message):
            return "Could not bind SQLite statement: \(message)"
        case .stepFailed(let message):
            return "Could not step SQLite statement: \(message)"
        case .executionFailed(let message):
            return "Could not execute SQLite statement: \(message)"
        }
    }
}

public struct SQLiteScanHistoryStore: @unchecked Sendable {
    public let databaseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func applicationSupport(fileManager: FileManager = .default) throws -> SQLiteScanHistoryStore {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SQLiteScanHistoryStoreError.invalidApplicationSupportDirectory
        }
        let databaseURL = directory
            .appendingPathComponent("MCP-HQ", isDirectory: true)
            .appendingPathComponent("history.sqlite3")
        return SQLiteScanHistoryStore(databaseURL: databaseURL, fileManager: fileManager)
    }

    public func migrate() throws {
        try withDatabase { database in
            try execute(Self.schemaSQL, database: database)
        }
    }

    public func saveAgentRegistry(_ registry: AgentRegistry = .default(), updatedAt: Date = Date()) throws {
        try migrate()
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try upsertAgents(registry.agents, updatedAt: updatedAt, database: database)
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func listAgentRecords() throws -> [SQLiteAgentRecord] {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT agent, display_name, config_format, parser_status, renderer_status,
                       config_paths_json, launch_context_notes, updated_at
                FROM agents
                ORDER BY display_name COLLATE NOCASE, agent
                """
            )
            var records: [SQLiteAgentRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                let configPathsJSON = try stringColumn(statement, 5)
                let configPathsData = try data(from: configPathsJSON)
                let agent = AgentID(rawValue: try stringColumn(statement, 0)) ?? .unknown
                let configFormat = AgentConfigFormat(rawValue: try stringColumn(statement, 2)) ?? .json
                let parserStatus = AgentCapabilityStatus(rawValue: try stringColumn(statement, 3)) ?? .unsupported
                let rendererStatus = AgentCapabilityStatus(rawValue: try stringColumn(statement, 4)) ?? .unsupported
                records.append(SQLiteAgentRecord(
                    agent: agent,
                    displayName: try stringColumn(statement, 1),
                    configFormat: configFormat,
                    parserStatus: parserStatus,
                    rendererStatus: rendererStatus,
                    configPaths: try decoder.decode([String].self, from: configPathsData),
                    launchContextNotes: try stringColumn(statement, 6),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 7))
                ))
            }
            return records
        }
    }

    public func syncControlPlane(from result: ScanResult, runID: String? = nil, scannedAt: Date = Date()) throws {
        try migrate()
        let sourceRows = sourceHistoryRows(from: result)
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try upsertAgents(AgentRegistry.default().agents, updatedAt: scannedAt, database: database)
                try upsertSourceBindings(sourceRows, runID: runID, seenAt: scannedAt, database: database)
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func listSourceBindings() throws -> [SQLiteSourceBindingRecord] {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT source_id, agent, path, state, server_count, message, last_run_id, last_seen_at
                FROM source_bindings
                ORDER BY agent, path
                """
            )
            var records: [SQLiteSourceBindingRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                let source = ConfigSource(
                    agent: AgentID(rawValue: try stringColumn(statement, 1)) ?? .unknown,
                    path: try stringColumn(statement, 2)
                )
                let stateText = optionalStringColumn(statement, 3)
                records.append(SQLiteSourceBindingRecord(
                    source: source,
                    state: stateText.flatMap(ConfigSourceState.init(rawValue:)),
                    serverCount: Int(sqlite3_column_int64(statement.pointer, 4)),
                    message: try stringColumn(statement, 5),
                    lastRunID: optionalStringColumn(statement, 6),
                    lastSeenAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 7))
                ))
            }
            return records
        }
    }

    public func upsertDesiredServerStates(
        _ servers: [ServerDefinition],
        for source: ConfigSource,
        enabled: Bool,
        updatedAt: Date = Date()
    ) throws {
        try migrate()
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try upsertDesiredServerStates(
                    servers,
                    source: source,
                    enabled: enabled,
                    updatedAt: updatedAt,
                    database: database
                )
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func listDesiredServerStates(source: ConfigSource? = nil) throws -> [SQLiteDesiredServerState] {
        try migrate()
        return try withDatabase { database in
            let sql: String
            if source == nil {
                sql = """
                SELECT source_id, agent, path, server_name, enabled, server_json, updated_at
                FROM desired_server_states
                ORDER BY agent, path, server_name COLLATE NOCASE
                """
            } else {
                sql = """
                SELECT source_id, agent, path, server_name, enabled, server_json, updated_at
                FROM desired_server_states
                WHERE source_id = ?
                ORDER BY server_name COLLATE NOCASE
                """
            }
            let statement = try SQLiteStatement(database: database, sql: sql)
            if let source {
                try statement.bind(source.id, at: 1)
            }

            var states: [SQLiteDesiredServerState] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                let rowSource = ConfigSource(
                    agent: AgentID(rawValue: try stringColumn(statement, 1)) ?? .unknown,
                    path: try stringColumn(statement, 2)
                )
                let serverJSON = try stringColumn(statement, 5)
                let serverData = try data(from: serverJSON)
                let server = try decoder.decode(ServerDefinition.self, from: serverData)
                states.append(SQLiteDesiredServerState(
                    source: rowSource,
                    serverName: try stringColumn(statement, 3),
                    enabled: sqlite3_column_int(statement.pointer, 4) != 0,
                    server: server,
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 6))
                ))
            }
            return states
        }
    }

    @discardableResult
    public func recordConfigBackup(
        source: ConfigSource,
        backupPath: String,
        reason: String,
        runID: String? = nil,
        createdAt: Date = Date()
    ) throws -> String {
        try migrate()
        let backupID = UUID().uuidString
        try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                INSERT INTO config_backups (
                    backup_id, source_id, agent, path, backup_path, reason, run_id, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            try statement.bind(backupID, at: 1)
            try statement.bind(source.id, at: 2)
            try statement.bind(source.agent.rawValue, at: 3)
            try statement.bind(source.path, at: 4)
            try statement.bind(SecretRedactor.redactText(backupPath), at: 5)
            try statement.bind(SecretRedactor.redactText(reason), at: 6)
            try statement.bind(runID.map(SecretRedactor.redactText), at: 7)
            try statement.bind(createdAt.timeIntervalSince1970, at: 8)
            try statement.stepDone()
        }
        return backupID
    }

    public func listConfigBackups(source: ConfigSource? = nil) throws -> [SQLiteConfigBackupRecord] {
        try migrate()
        return try withDatabase { database in
            let sql: String
            if source == nil {
                sql = """
                SELECT backup_id, agent, path, backup_path, reason, run_id, created_at
                FROM config_backups
                ORDER BY created_at DESC, rowid DESC
                """
            } else {
                sql = """
                SELECT backup_id, agent, path, backup_path, reason, run_id, created_at
                FROM config_backups
                WHERE source_id = ?
                ORDER BY created_at DESC, rowid DESC
                """
            }
            let statement = try SQLiteStatement(database: database, sql: sql)
            if let source {
                try statement.bind(source.id, at: 1)
            }

            var records: [SQLiteConfigBackupRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                let rowSource = ConfigSource(
                    agent: AgentID(rawValue: try stringColumn(statement, 1)) ?? .unknown,
                    path: try stringColumn(statement, 2)
                )
                records.append(SQLiteConfigBackupRecord(
                    backupID: try stringColumn(statement, 0),
                    source: rowSource,
                    backupPath: try stringColumn(statement, 3),
                    reason: try stringColumn(statement, 4),
                    runID: optionalStringColumn(statement, 5),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 6))
                ))
            }
            return records
        }
    }

    public func recordBulkRollbackTransaction(
        plan: AgentBulkConnectRollbackPlan,
        reason: String,
        status: String = "available",
        createdAt: Date? = nil
    ) throws {
        try migrate()
        let timestamp = createdAt ?? plan.createdAt
        let planData = try encoder.encode(plan)
        let planJSON = String(decoding: planData, as: UTF8.self)
        try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                INSERT INTO bulk_rollback_transactions (
                    transaction_id, status, reason, plan_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(transaction_id) DO UPDATE SET
                    status = excluded.status,
                    reason = excluded.reason,
                    plan_json = excluded.plan_json,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(plan.id, at: 1)
            try statement.bind(SecretRedactor.redactText(status), at: 2)
            try statement.bind(SecretRedactor.redactText(reason), at: 3)
            try statement.bind(planJSON, at: 4)
            try statement.bind(timestamp.timeIntervalSince1970, at: 5)
            try statement.bind(Date().timeIntervalSince1970, at: 6)
            try statement.stepDone()
        }
    }

    public func markBulkRollbackTransaction(_ transactionID: String, status: String, updatedAt: Date = Date()) throws {
        try migrate()
        try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                UPDATE bulk_rollback_transactions
                SET status = ?, updated_at = ?
                WHERE transaction_id = ?
                """
            )
            try statement.bind(SecretRedactor.redactText(status), at: 1)
            try statement.bind(updatedAt.timeIntervalSince1970, at: 2)
            try statement.bind(SecretRedactor.redactText(transactionID), at: 3)
            try statement.stepDone()
        }
    }

    public func loadBulkRollbackTransaction(_ transactionID: String) throws -> SQLiteBulkRollbackTransactionRecord? {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT transaction_id, status, reason, plan_json, created_at, updated_at
                FROM bulk_rollback_transactions
                WHERE transaction_id = ?
                """
            )
            try statement.bind(SecretRedactor.redactText(transactionID), at: 1)
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            return try bulkRollbackTransactionRecord(from: statement)
        }
    }

    public func listBulkRollbackTransactions(status: String? = nil) throws -> [SQLiteBulkRollbackTransactionRecord] {
        try migrate()
        return try withDatabase { database in
            let sql: String
            if status == nil {
                sql = """
                SELECT transaction_id, status, reason, plan_json, created_at, updated_at
                FROM bulk_rollback_transactions
                ORDER BY created_at DESC, rowid DESC
                """
            } else {
                sql = """
                SELECT transaction_id, status, reason, plan_json, created_at, updated_at
                FROM bulk_rollback_transactions
                WHERE status = ?
                ORDER BY created_at DESC, rowid DESC
                """
            }
            let statement = try SQLiteStatement(database: database, sql: sql)
            if let status {
                try statement.bind(SecretRedactor.redactText(status), at: 1)
            }
            var records: [SQLiteBulkRollbackTransactionRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                records.append(try bulkRollbackTransactionRecord(from: statement))
            }
            return records
        }
    }

    public func upsertConnectAllTargetProfile(
        name: String,
        targetSources: [ConfigSource],
        updatedAt: Date = Date()
    ) throws {
        try migrate()
        let profileName = try normalizedProfileName(name)
        let targetSourcesJSON = try jsonString(uniqueSources(targetSources))
        try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                INSERT INTO connect_all_target_profiles (
                    profile_name, target_sources_json, updated_at
                ) VALUES (?, ?, ?)
                ON CONFLICT(profile_name) DO UPDATE SET
                    target_sources_json = excluded.target_sources_json,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(profileName, at: 1)
            try statement.bind(targetSourcesJSON, at: 2)
            try statement.bind(updatedAt.timeIntervalSince1970, at: 3)
            try statement.stepDone()
        }
    }

    public func loadConnectAllTargetProfile(name: String) throws -> SQLiteConnectAllTargetProfileRecord? {
        try migrate()
        let profileName = try normalizedProfileName(name)
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT profile_name, target_sources_json, updated_at
                FROM connect_all_target_profiles
                WHERE profile_name = ?
                LIMIT 1
                """
            )
            try statement.bind(profileName, at: 1)
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            return try connectAllTargetProfileRecord(from: statement)
        }
    }

    public func listConnectAllTargetProfiles() throws -> [SQLiteConnectAllTargetProfileRecord] {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT profile_name, target_sources_json, updated_at
                FROM connect_all_target_profiles
                ORDER BY profile_name COLLATE NOCASE
                """
            )
            var records: [SQLiteConnectAllTargetProfileRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                records.append(try connectAllTargetProfileRecord(from: statement))
            }
            return records
        }
    }

    public func upsertRuntimeInstance(_ instance: RuntimeInstance, updatedAt: Date = Date()) throws {
        try migrate()
        try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                INSERT INTO runtime_instances (
                    runtime_id, server_id, pid, ownership, status, command_line, stdout_log_path, stderr_log_path, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(runtime_id) DO UPDATE SET
                    server_id = excluded.server_id,
                    pid = excluded.pid,
                    ownership = excluded.ownership,
                    status = excluded.status,
                    command_line = excluded.command_line,
                    stdout_log_path = excluded.stdout_log_path,
                    stderr_log_path = excluded.stderr_log_path,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(instance.id, at: 1)
            try statement.bind(instance.serverID, at: 2)
            try statement.bind(instance.pid.map(Int.init), at: 3)
            try statement.bind(instance.ownership.rawValue, at: 4)
            try statement.bind(instance.status.rawValue, at: 5)
            try statement.bind(instance.commandLine, at: 6)
            try statement.bind(instance.logPath, at: 7)
            try statement.bind(nil as String?, at: 8)
            try statement.bind(updatedAt.timeIntervalSince1970, at: 9)
            try statement.stepDone()
        }
    }

    public func listRuntimeInstanceRecords(ownership: RuntimeOwnership? = nil) throws -> [SQLiteRuntimeInstanceRecord] {
        try migrate()
        return try withDatabase { database in
            let sql: String
            if ownership == nil {
                sql = """
                SELECT runtime_id, server_id, pid, ownership, status, command_line, stdout_log_path, updated_at
                FROM runtime_instances
                ORDER BY updated_at DESC, runtime_id
                """
            } else {
                sql = """
                SELECT runtime_id, server_id, pid, ownership, status, command_line, stdout_log_path, updated_at
                FROM runtime_instances
                WHERE ownership = ?
                ORDER BY updated_at DESC, runtime_id
                """
            }
            let statement = try SQLiteStatement(database: database, sql: sql)
            if let ownership {
                try statement.bind(ownership.rawValue, at: 1)
            }

            var records: [SQLiteRuntimeInstanceRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                let runtimeOwnership = RuntimeOwnership(rawValue: try stringColumn(statement, 3)) ?? .unknown
                let status = RuntimeInstanceStatus(rawValue: try stringColumn(statement, 4)) ?? .observed
                let pid: Int32? = sqlite3_column_type(statement.pointer, 2) == SQLITE_NULL
                    ? nil
                    : Int32(sqlite3_column_int(statement.pointer, 2))
                let instance = RuntimeInstance(
                    id: try stringColumn(statement, 0),
                    serverID: optionalStringColumn(statement, 1),
                    pid: pid,
                    ownership: runtimeOwnership,
                    commandLine: try stringColumn(statement, 5),
                    status: status,
                    logPath: optionalStringColumn(statement, 6)
                )
                records.append(SQLiteRuntimeInstanceRecord(
                    instance: instance,
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 7))
                ))
            }
            return records
        }
    }

    public func upsertSecretBindings(
        _ detectedSecrets: [DetectedSecret],
        status: String,
        updatedAt: Date = Date(),
        validatedAt: Date? = nil
    ) throws {
        try migrate()
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                let statement = try SQLiteStatement(
                    database: database,
                    sql: """
                    INSERT INTO secret_bindings (
                        secret_id, source_id, server_name, field_kind, field_name, service, account,
                        reference_uri, status, updated_at, validated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(secret_id) DO UPDATE SET
                        source_id = excluded.source_id,
                        server_name = excluded.server_name,
                        field_kind = excluded.field_kind,
                        field_name = excluded.field_name,
                        service = excluded.service,
                        account = excluded.account,
                        reference_uri = excluded.reference_uri,
                        status = excluded.status,
                        updated_at = excluded.updated_at,
                        validated_at = excluded.validated_at
                    """
                )
                for secret in detectedSecrets {
                    try statement.reset()
                    try statement.bind(secret.id, at: 1)
                    try statement.bind(secret.location.sourcePath, at: 2)
                    try statement.bind(secret.location.serverDisplayName, at: 3)
                    try statement.bind(secret.location.field.rawValue, at: 4)
                    try statement.bind(secret.location.name, at: 5)
                    try statement.bind(secret.reference.service, at: 6)
                    try statement.bind(secret.reference.account, at: 7)
                    try statement.bind(secret.reference.configValue, at: 8)
                    try statement.bind(SecretRedactor.redactText(status), at: 9)
                    try statement.bind(updatedAt.timeIntervalSince1970, at: 10)
                    try statement.bind(validatedAt?.timeIntervalSince1970, at: 11)
                    try statement.stepDone()
                }
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func listSecretBindingRecords(sourcePath: String? = nil) throws -> [SQLiteSecretBindingRecord] {
        try migrate()
        return try withDatabase { database in
            let sql: String
            if sourcePath == nil {
                sql = """
                SELECT secret_id, source_id, server_name, field_kind, field_name, service, account,
                       status, updated_at, validated_at
                FROM secret_bindings
                ORDER BY updated_at DESC, source_id, server_name, field_name
                """
            } else {
                sql = """
                SELECT secret_id, source_id, server_name, field_kind, field_name, service, account,
                       status, updated_at, validated_at
                FROM secret_bindings
                WHERE source_id = ?
                ORDER BY updated_at DESC, server_name, field_name
                """
            }
            let statement = try SQLiteStatement(database: database, sql: sql)
            if let sourcePath {
                try statement.bind(sourcePath, at: 1)
            }

            var records: [SQLiteSecretBindingRecord] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                records.append(SQLiteSecretBindingRecord(
                    secretID: try stringColumn(statement, 0),
                    sourcePath: try stringColumn(statement, 1),
                    serverName: optionalStringColumn(statement, 2),
                    fieldKind: SecretFieldKind(rawValue: try stringColumn(statement, 3)) ?? .environment,
                    fieldName: try stringColumn(statement, 4),
                    reference: KeychainSecretReference(
                        service: try stringColumn(statement, 5),
                        account: try stringColumn(statement, 6)
                    ),
                    status: try stringColumn(statement, 7),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 8)),
                    validatedAt: sqlite3_column_type(statement.pointer, 9) == SQLITE_NULL
                        ? nil
                        : Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 9))
                ))
            }
            return records
        }
    }

    public func validateSecretBindings(
        sourcePath: String? = nil,
        store: SecretStore,
        validatedAt: Date = Date()
    ) throws -> SecretRecoveryReport {
        let records = try listSecretBindingRecords(sourcePath: sourcePath)
        let report = SecretRecoveryReporter(store: store).report(records: records, validatedAt: validatedAt)
        try updateSecretBindingValidation(report.states, validatedAt: validatedAt)
        return report
    }

    private func updateSecretBindingValidation(_ states: [SecretRecoveryState], validatedAt: Date) throws {
        guard !states.isEmpty else { return }
        try migrate()
        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                let statement = try SQLiteStatement(
                    database: database,
                    sql: """
                    UPDATE secret_bindings
                    SET status = ?, validated_at = ?
                    WHERE secret_id = ?
                    """
                )
                for state in states {
                    try statement.reset()
                    try statement.bind(state.persistedStatus, at: 1)
                    try statement.bind(validatedAt.timeIntervalSince1970, at: 2)
                    try statement.bind(state.id, at: 3)
                    try statement.stepDone()
                }
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    @discardableResult
    public func save(_ result: ScanResult, scannedAt: Date = Date()) throws -> String {
        try migrate()
        let runID = UUID().uuidString
        let report = DoctorReportBuilder().build(from: result)
        let findings = report.findings
        let redactedReport = redactedDoctorReport(report)
        let reportJSON = try jsonString(redactedReport)
        let doctorSourceCount = Set(redactedReport.findings.map(\.sourcePath)).count
        let doctorServerCount = Set(redactedReport.findings.compactMap { finding in
            finding.serverID?.isEmpty == false ? finding.serverID : nil
        }).count
        let stored = StoredScanResult(result: result, scannedAt: scannedAt)
        let storedJSON = try jsonString(stored)
        let sourceRows = sourceHistoryRows(from: result)

        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try insertScanRun(
                    runID: runID,
                    scannedAt: scannedAt,
                    result: result,
                    findingCount: findings.count,
                    sourceCount: sourceRows.count,
                    resultJSON: storedJSON,
                    database: database
                )
                try insertSources(sourceRows, runID: runID, database: database)
                try insertServers(result.servers, runID: runID, database: database)
                try insertFindings(findings, runID: runID, database: database)
                try insertProcessSnapshots(result.processes, runID: runID, database: database)
                try insertDoctorReport(
                    redactedReport,
                    runID: runID,
                    scannedAt: scannedAt,
                    reportedAt: scannedAt,
                    sourceCount: doctorSourceCount,
                    serverCount: doctorServerCount,
                    reportJSON: reportJSON,
                    database: database
                )
                try insertDoctorReportFindings(redactedReport.findings, runID: runID, database: database)
                try upsertAgents(AgentRegistry.default().agents, updatedAt: scannedAt, database: database)
                try upsertSourceBindings(sourceRows, runID: runID, seenAt: scannedAt, database: database)
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }

        return runID
    }

    public func loadLatest() throws -> StoredScanResult? {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT result_json
                FROM scan_runs
                ORDER BY scanned_at DESC, rowid DESC
                LIMIT 1
                """
            )
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            guard let text = sqlite3_column_text(statement.pointer, 0) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            let json = String(cString: text)
            guard let data = json.data(using: .utf8) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            return try decoder.decode(StoredScanResult.self, from: data)
        }
    }

    public func load(runID: String) throws -> StoredScanResult? {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT result_json
                FROM scan_runs
                WHERE id = ?
                LIMIT 1
                """
            )
            try statement.bind(runID, at: 1)
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            guard let text = sqlite3_column_text(statement.pointer, 0) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            let json = String(cString: text)
            guard let data = json.data(using: .utf8) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            return try decoder.decode(StoredScanResult.self, from: data)
        }
    }

    public func listRunSummaries(limit: Int = 10) throws -> [SQLiteScanHistoryRunSummary] {
        try migrate()
        let boundedLimit = max(0, min(limit, 100))
        guard boundedLimit > 0 else { return [] }

        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT id, scanned_at, source_count, server_count, finding_count, process_count, probe_count
                FROM scan_runs
                ORDER BY scanned_at DESC, rowid DESC
                LIMIT ?
                """
            )
            try statement.bind(boundedLimit, at: 1)

            var summaries: [SQLiteScanHistoryRunSummary] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                guard let runIDText = sqlite3_column_text(statement.pointer, 0) else {
                    throw SQLiteScanHistoryStoreError.invalidUTF8
                }
                summaries.append(SQLiteScanHistoryRunSummary(
                    runID: String(cString: runIDText),
                    scannedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 1)),
                    sourceCount: Int(sqlite3_column_int64(statement.pointer, 2)),
                    serverCount: Int(sqlite3_column_int64(statement.pointer, 3)),
                    findingCount: Int(sqlite3_column_int64(statement.pointer, 4)),
                    processCount: Int(sqlite3_column_int64(statement.pointer, 5)),
                    probeCount: Int(sqlite3_column_int64(statement.pointer, 6))
                ))
            }
            return summaries
        }
    }

    @discardableResult
    public func saveDoctorReport(
        _ report: DoctorReport,
        runID: String = UUID().uuidString,
        scannedAt: Date,
        reportedAt: Date = Date()
    ) throws -> String {
        try migrate()
        let redactedReport = redactedDoctorReport(report)
        let reportJSON = try jsonString(redactedReport)
        let sourceCount = Set(redactedReport.findings.map(\.sourcePath)).count
        let serverCount = Set(redactedReport.findings.compactMap { finding in
            finding.serverID?.isEmpty == false ? finding.serverID : nil
        }).count

        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try insertDoctorReport(
                    redactedReport,
                    runID: runID,
                    scannedAt: scannedAt,
                    reportedAt: reportedAt,
                    sourceCount: sourceCount,
                    serverCount: serverCount,
                    reportJSON: reportJSON,
                    database: database
                )
                try deleteDoctorReportFindings(runID: runID, database: database)
                try insertDoctorReportFindings(redactedReport.findings, runID: runID, database: database)
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }

        return runID
    }

    public func loadDoctorReport(runID: String) throws -> SQLiteStoredDoctorReport? {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT scanned_at, reported_at, report_json
                FROM doctor_reports
                WHERE run_id = ?
                LIMIT 1
                """
            )
            try statement.bind(runID, at: 1)
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            guard let text = sqlite3_column_text(statement.pointer, 2) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            let json = String(cString: text)
            guard let data = json.data(using: .utf8) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            return SQLiteStoredDoctorReport(
                runID: runID,
                scannedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 0)),
                reportedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 1)),
                report: try decoder.decode(DoctorReport.self, from: data)
            )
        }
    }

    public func exportDoctorReportJSON(runID: String) throws -> String? {
        try migrate()
        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT report_json
                FROM doctor_reports
                WHERE run_id = ?
                LIMIT 1
                """
            )
            try statement.bind(runID, at: 1)
            let stepResult = sqlite3_step(statement.pointer)
            if stepResult == SQLITE_DONE { return nil }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
            }
            guard let text = sqlite3_column_text(statement.pointer, 0) else {
                throw SQLiteScanHistoryStoreError.invalidUTF8
            }
            return String(cString: text)
        }
    }

    public func listDoctorReportSummaries(limit: Int = 10) throws -> [SQLiteDoctorReportSummary] {
        try migrate()
        let boundedLimit = max(0, min(limit, 100))
        guard boundedLimit > 0 else { return [] }

        return try withDatabase { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT run_id, scanned_at, reported_at, finding_count, error_count, warning_count, info_count,
                       source_count, server_count
                FROM doctor_reports
                ORDER BY reported_at DESC, rowid DESC
                LIMIT ?
                """
            )
            try statement.bind(boundedLimit, at: 1)

            var summaries: [SQLiteDoctorReportSummary] = []
            while true {
                let stepResult = sqlite3_step(statement.pointer)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
                }
                guard let runIDText = sqlite3_column_text(statement.pointer, 0) else {
                    throw SQLiteScanHistoryStoreError.invalidUTF8
                }
                summaries.append(SQLiteDoctorReportSummary(
                    runID: String(cString: runIDText),
                    scannedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 1)),
                    reportedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 2)),
                    findingCount: Int(sqlite3_column_int64(statement.pointer, 3)),
                    errorCount: Int(sqlite3_column_int64(statement.pointer, 4)),
                    warningCount: Int(sqlite3_column_int64(statement.pointer, 5)),
                    infoCount: Int(sqlite3_column_int64(statement.pointer, 6)),
                    sourceCount: Int(sqlite3_column_int64(statement.pointer, 7)),
                    serverCount: Int(sqlite3_column_int64(statement.pointer, 8))
                ))
            }
            return summaries
        }
    }

    public func counts(forRunID runID: String) throws -> SQLiteScanHistoryCounts {
        try migrate()
        return try withDatabase { database in
            SQLiteScanHistoryCounts(
                runCount: try countRows(in: "scan_runs", idColumn: "id", runID: runID, database: database),
                sourceCount: try countRows(in: "scan_sources", runID: runID, database: database),
                serverCount: try countRows(in: "scan_servers", runID: runID, database: database),
                findingCount: try countRows(in: "scan_findings", runID: runID, database: database),
                processSnapshotCount: try countRows(in: "runtime_process_snapshots", runID: runID, database: database)
            )
        }
    }

    private struct SourceHistoryRow {
        let source: ConfigSource
        let state: ConfigSourceState?
        let serverCount: Int
        let message: String
    }

    private static let schemaSQL = """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS scan_runs (
        id TEXT PRIMARY KEY,
        scanned_at REAL NOT NULL,
        source_count INTEGER NOT NULL,
        server_count INTEGER NOT NULL,
        finding_count INTEGER NOT NULL,
        process_count INTEGER NOT NULL,
        probe_count INTEGER NOT NULL,
        result_json TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS scan_sources (
        run_id TEXT NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
        source_id TEXT NOT NULL,
        agent TEXT NOT NULL,
        path TEXT NOT NULL,
        state TEXT,
        server_count INTEGER NOT NULL,
        message TEXT NOT NULL,
        PRIMARY KEY (run_id, source_id)
    );

    CREATE TABLE IF NOT EXISTS scan_servers (
        run_id TEXT NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
        server_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        transport TEXT NOT NULL,
        command TEXT,
        args_json TEXT NOT NULL,
        url TEXT,
        headers_json TEXT NOT NULL,
        env_bindings_json TEXT NOT NULL,
        source_path TEXT NOT NULL,
        PRIMARY KEY (run_id, server_id)
    );

    CREATE TABLE IF NOT EXISTS scan_findings (
        run_id TEXT NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
        finding_id TEXT NOT NULL,
        severity TEXT NOT NULL,
        category TEXT NOT NULL,
        agent_name TEXT NOT NULL,
        source_path TEXT NOT NULL,
        server_id TEXT,
        server_name TEXT,
        title TEXT NOT NULL,
        why_it_matters TEXT NOT NULL,
        suggested_fix TEXT NOT NULL,
        PRIMARY KEY (run_id, finding_id)
    );

    CREATE TABLE IF NOT EXISTS runtime_process_snapshots (
        run_id TEXT NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
        pid INTEGER NOT NULL,
        executable_name TEXT NOT NULL,
        command_line TEXT NOT NULL,
        match_reason TEXT NOT NULL,
        cpu_percent REAL,
        memory_bytes INTEGER,
        PRIMARY KEY (run_id, pid)
    );

    CREATE TABLE IF NOT EXISTS doctor_reports (
        run_id TEXT PRIMARY KEY,
        scanned_at REAL NOT NULL,
        reported_at REAL NOT NULL,
        finding_count INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        warning_count INTEGER NOT NULL,
        info_count INTEGER NOT NULL,
        source_count INTEGER NOT NULL,
        server_count INTEGER NOT NULL,
        report_json TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS doctor_report_findings (
        run_id TEXT NOT NULL REFERENCES doctor_reports(run_id) ON DELETE CASCADE,
        ordinal INTEGER NOT NULL,
        finding_id TEXT NOT NULL,
        severity TEXT NOT NULL,
        category TEXT NOT NULL,
        agent_name TEXT NOT NULL,
        source_path TEXT NOT NULL,
        server_id TEXT,
        server_name TEXT,
        title TEXT NOT NULL,
        why_it_matters TEXT NOT NULL,
        suggested_fix TEXT NOT NULL,
        PRIMARY KEY (run_id, ordinal)
    );

    CREATE TABLE IF NOT EXISTS agents (
        agent TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        config_format TEXT NOT NULL,
        parser_status TEXT NOT NULL,
        renderer_status TEXT NOT NULL,
        config_paths_json TEXT NOT NULL,
        launch_context_notes TEXT NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS source_bindings (
        source_id TEXT PRIMARY KEY,
        agent TEXT NOT NULL,
        path TEXT NOT NULL,
        state TEXT,
        server_count INTEGER NOT NULL,
        message TEXT NOT NULL,
        last_run_id TEXT,
        last_seen_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS desired_server_states (
        source_id TEXT NOT NULL,
        server_name TEXT NOT NULL,
        agent TEXT NOT NULL,
        path TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        transport TEXT NOT NULL,
        command TEXT,
        args_json TEXT NOT NULL,
        url TEXT,
        headers_json TEXT NOT NULL,
        env_bindings_json TEXT NOT NULL,
        server_json TEXT NOT NULL,
        updated_at REAL NOT NULL,
        PRIMARY KEY (source_id, server_name)
    );

    CREATE TABLE IF NOT EXISTS runtime_instances (
        runtime_id TEXT PRIMARY KEY,
        server_id TEXT,
        pid INTEGER,
        ownership TEXT NOT NULL,
        status TEXT NOT NULL,
        command_line TEXT,
        stdout_log_path TEXT,
        stderr_log_path TEXT,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS config_backups (
        backup_id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        agent TEXT NOT NULL,
        path TEXT NOT NULL,
        backup_path TEXT NOT NULL,
        reason TEXT NOT NULL,
        run_id TEXT,
        created_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS bulk_rollback_transactions (
        transaction_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        reason TEXT NOT NULL,
        plan_json TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS connect_all_target_profiles (
        profile_name TEXT PRIMARY KEY,
        target_sources_json TEXT NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS secret_bindings (
        secret_id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        server_name TEXT,
        field_kind TEXT NOT NULL,
        field_name TEXT NOT NULL,
        service TEXT NOT NULL,
        account TEXT NOT NULL,
        reference_uri TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at REAL NOT NULL,
        validated_at REAL
    );

    CREATE INDEX IF NOT EXISTS idx_scan_runs_scanned_at ON scan_runs(scanned_at);
    CREATE INDEX IF NOT EXISTS idx_scan_servers_server_id ON scan_servers(server_id);
    CREATE INDEX IF NOT EXISTS idx_scan_sources_path ON scan_sources(path);
    CREATE INDEX IF NOT EXISTS idx_scan_findings_server_id ON scan_findings(server_id);
    CREATE INDEX IF NOT EXISTS idx_doctor_reports_reported_at ON doctor_reports(reported_at);
    CREATE INDEX IF NOT EXISTS idx_doctor_report_findings_server_id ON doctor_report_findings(server_id);
    CREATE INDEX IF NOT EXISTS idx_doctor_report_findings_source_path ON doctor_report_findings(source_path);
    CREATE INDEX IF NOT EXISTS idx_source_bindings_agent ON source_bindings(agent);
    CREATE INDEX IF NOT EXISTS idx_source_bindings_path ON source_bindings(path);
    CREATE INDEX IF NOT EXISTS idx_desired_server_states_server_name ON desired_server_states(server_name);
    CREATE INDEX IF NOT EXISTS idx_runtime_instances_server_id ON runtime_instances(server_id);
    CREATE INDEX IF NOT EXISTS idx_config_backups_source_id ON config_backups(source_id);
    CREATE INDEX IF NOT EXISTS idx_bulk_rollback_transactions_status ON bulk_rollback_transactions(status);
    CREATE INDEX IF NOT EXISTS idx_connect_all_target_profiles_updated_at ON connect_all_target_profiles(updated_at);
    CREATE INDEX IF NOT EXISTS idx_secret_bindings_source_id ON secret_bindings(source_id);
    CREATE INDEX IF NOT EXISTS idx_secret_bindings_account ON secret_bindings(service, account);

    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (1, CAST(strftime('%s', 'now') AS REAL));
    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (2, CAST(strftime('%s', 'now') AS REAL));
    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (3, CAST(strftime('%s', 'now') AS REAL));
    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (4, CAST(strftime('%s', 'now') AS REAL));
    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (5, CAST(strftime('%s', 'now') AS REAL));
    """

    private func sourceHistoryRows(from result: ScanResult) -> [SourceHistoryRow] {
        var rows: [SourceHistoryRow] = []
        var seenSourceIDs = Set<String>()
        for health in result.sourceHealth {
            rows.append(SourceHistoryRow(
                source: health.source,
                state: health.state,
                serverCount: health.serverCount,
                message: health.message
            ))
            seenSourceIDs.insert(health.source.id)
        }
        for source in result.sources where !seenSourceIDs.contains(source.id) {
            let serverCount = result.servers.filter { $0.sourcePath == source.path }.count
            rows.append(SourceHistoryRow(
                source: source,
                state: .found,
                serverCount: serverCount,
                message: ""
            ))
        }
        return rows
    }

    private func upsertAgents(_ agents: [AgentDefinition], updatedAt: Date, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO agents (
                agent, display_name, config_format, parser_status, renderer_status,
                config_paths_json, launch_context_notes, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(agent) DO UPDATE SET
                display_name = excluded.display_name,
                config_format = excluded.config_format,
                parser_status = excluded.parser_status,
                renderer_status = excluded.renderer_status,
                config_paths_json = excluded.config_paths_json,
                launch_context_notes = excluded.launch_context_notes,
                updated_at = excluded.updated_at
            """
        )
        for agent in agents {
            try statement.reset()
            try statement.bind(agent.agent.rawValue, at: 1)
            try statement.bind(agent.displayName, at: 2)
            try statement.bind(agent.configFormat.rawValue, at: 3)
            try statement.bind(agent.parserStatus.rawValue, at: 4)
            try statement.bind(agent.rendererStatus.rawValue, at: 5)
            try statement.bind(jsonString(agent.configPaths), at: 6)
            try statement.bind(agent.launchContextNotes, at: 7)
            try statement.bind(updatedAt.timeIntervalSince1970, at: 8)
            try statement.stepDone()
        }
    }

    private func upsertSourceBindings(
        _ rows: [SourceHistoryRow],
        runID: String?,
        seenAt: Date,
        database: OpaquePointer
    ) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO source_bindings (
                source_id, agent, path, state, server_count, message, last_run_id, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id) DO UPDATE SET
                agent = excluded.agent,
                path = excluded.path,
                state = excluded.state,
                server_count = excluded.server_count,
                message = excluded.message,
                last_run_id = excluded.last_run_id,
                last_seen_at = excluded.last_seen_at
            """
        )
        for row in rows {
            try statement.reset()
            try statement.bind(row.source.id, at: 1)
            try statement.bind(row.source.agent.rawValue, at: 2)
            try statement.bind(row.source.path, at: 3)
            try statement.bind(row.state?.rawValue, at: 4)
            try statement.bind(row.serverCount, at: 5)
            try statement.bind(SecretRedactor.redactText(row.message), at: 6)
            try statement.bind(runID, at: 7)
            try statement.bind(seenAt.timeIntervalSince1970, at: 8)
            try statement.stepDone()
        }
    }

    private func upsertDesiredServerStates(
        _ servers: [ServerDefinition],
        source: ConfigSource,
        enabled: Bool,
        updatedAt: Date,
        database: OpaquePointer
    ) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO desired_server_states (
                source_id, server_name, agent, path, enabled, transport, command, args_json, url,
                headers_json, env_bindings_json, server_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id, server_name) DO UPDATE SET
                agent = excluded.agent,
                path = excluded.path,
                enabled = excluded.enabled,
                transport = excluded.transport,
                command = excluded.command,
                args_json = excluded.args_json,
                url = excluded.url,
                headers_json = excluded.headers_json,
                env_bindings_json = excluded.env_bindings_json,
                server_json = excluded.server_json,
                updated_at = excluded.updated_at
            """
        )
        for server in servers {
            let redactedServer = redactedServer(server, for: source)
            try statement.reset()
            try statement.bind(source.id, at: 1)
            try statement.bind(redactedServer.displayName, at: 2)
            try statement.bind(source.agent.rawValue, at: 3)
            try statement.bind(source.path, at: 4)
            try statement.bind(enabled ? 1 : 0, at: 5)
            try statement.bind(redactedServer.transport.rawValue, at: 6)
            try statement.bind(redactedServer.command, at: 7)
            try statement.bind(jsonString(redactedServer.args), at: 8)
            try statement.bind(redactedServer.url, at: 9)
            try statement.bind(jsonString(redactedServer.headers), at: 10)
            try statement.bind(jsonString(redactedServer.envBindings), at: 11)
            try statement.bind(jsonString(redactedServer), at: 12)
            try statement.bind(updatedAt.timeIntervalSince1970, at: 13)
            try statement.stepDone()
        }
    }

    private func insertScanRun(
        runID: String,
        scannedAt: Date,
        result: ScanResult,
        findingCount: Int,
        sourceCount: Int,
        resultJSON: String,
        database: OpaquePointer
    ) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO scan_runs (
                id, scanned_at, source_count, server_count, finding_count, process_count, probe_count, result_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try statement.bind(runID, at: 1)
        try statement.bind(scannedAt.timeIntervalSince1970, at: 2)
        try statement.bind(sourceCount, at: 3)
        try statement.bind(result.servers.count, at: 4)
        try statement.bind(findingCount, at: 5)
        try statement.bind(result.processes.count, at: 6)
        try statement.bind(result.probeResults.count, at: 7)
        try statement.bind(resultJSON, at: 8)
        try statement.stepDone()
    }

    private func insertSources(_ sources: [SourceHistoryRow], runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO scan_sources (run_id, source_id, agent, path, state, server_count, message)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        for row in sources {
            try statement.reset()
            try statement.bind(runID, at: 1)
            try statement.bind(row.source.id, at: 2)
            try statement.bind(row.source.agent.rawValue, at: 3)
            try statement.bind(row.source.path, at: 4)
            try statement.bind(row.state?.rawValue, at: 5)
            try statement.bind(row.serverCount, at: 6)
            try statement.bind(row.message, at: 7)
            try statement.stepDone()
        }
    }

    private func insertServers(_ servers: [ServerDefinition], runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO scan_servers (
                run_id, server_id, display_name, transport, command, args_json, url, headers_json, env_bindings_json, source_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        for server in servers {
            try statement.reset()
            try statement.bind(runID, at: 1)
            try statement.bind(server.id, at: 2)
            try statement.bind(server.displayName, at: 3)
            try statement.bind(server.transport.rawValue, at: 4)
            try statement.bind(server.command, at: 5)
            try statement.bind(jsonString(server.args), at: 6)
            try statement.bind(server.url, at: 7)
            try statement.bind(jsonString(server.redactedHeaders), at: 8)
            try statement.bind(jsonString(server.redactedEnvBindings), at: 9)
            try statement.bind(server.sourcePath, at: 10)
            try statement.stepDone()
        }
    }

    private func insertFindings(_ findings: [DoctorFinding], runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO scan_findings (
                run_id, finding_id, severity, category, agent_name, source_path, server_id, server_name,
                title, why_it_matters, suggested_fix
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        for finding in findings {
            try statement.reset()
            try statement.bind(runID, at: 1)
            try statement.bind(finding.id, at: 2)
            try statement.bind(finding.severity.rawValue, at: 3)
            try statement.bind(finding.category.rawValue, at: 4)
            try statement.bind(finding.agentName, at: 5)
            try statement.bind(finding.sourcePath, at: 6)
            try statement.bind(finding.serverID, at: 7)
            try statement.bind(finding.serverName, at: 8)
            try statement.bind(finding.title, at: 9)
            try statement.bind(finding.whyItMatters, at: 10)
            try statement.bind(finding.suggestedFix, at: 11)
            try statement.stepDone()
        }
    }

    private func insertProcessSnapshots(_ processes: [MCPProcessSnapshot], runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO runtime_process_snapshots (
                run_id, pid, executable_name, command_line, match_reason, cpu_percent, memory_bytes
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        for process in processes {
            try statement.reset()
            try statement.bind(runID, at: 1)
            try statement.bind(Int(process.pid), at: 2)
            try statement.bind(process.executableName, at: 3)
            try statement.bind(process.commandLine, at: 4)
            try statement.bind(process.matchReason, at: 5)
            try statement.bind(process.cpuPercent, at: 6)
            try statement.bind(process.memoryBytes, at: 7)
            try statement.stepDone()
        }
    }

    private func insertDoctorReport(
        _ report: DoctorReport,
        runID: String,
        scannedAt: Date,
        reportedAt: Date,
        sourceCount: Int,
        serverCount: Int,
        reportJSON: String,
        database: OpaquePointer
    ) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT OR REPLACE INTO doctor_reports (
                run_id, scanned_at, reported_at, finding_count, error_count, warning_count, info_count,
                source_count, server_count, report_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try statement.bind(runID, at: 1)
        try statement.bind(scannedAt.timeIntervalSince1970, at: 2)
        try statement.bind(reportedAt.timeIntervalSince1970, at: 3)
        try statement.bind(report.findings.count, at: 4)
        try statement.bind(report.errorCount, at: 5)
        try statement.bind(report.warningCount, at: 6)
        try statement.bind(report.infoCount, at: 7)
        try statement.bind(sourceCount, at: 8)
        try statement.bind(serverCount, at: 9)
        try statement.bind(reportJSON, at: 10)
        try statement.stepDone()
    }

    private func deleteDoctorReportFindings(runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(database: database, sql: "DELETE FROM doctor_report_findings WHERE run_id = ?")
        try statement.bind(runID, at: 1)
        try statement.stepDone()
    }

    private func insertDoctorReportFindings(_ findings: [DoctorFinding], runID: String, database: OpaquePointer) throws {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            INSERT INTO doctor_report_findings (
                run_id, ordinal, finding_id, severity, category, agent_name, source_path, server_id, server_name,
                title, why_it_matters, suggested_fix
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        for (index, finding) in findings.enumerated() {
            try statement.reset()
            try statement.bind(runID, at: 1)
            try statement.bind(index, at: 2)
            try statement.bind(finding.id, at: 3)
            try statement.bind(finding.severity.rawValue, at: 4)
            try statement.bind(finding.category.rawValue, at: 5)
            try statement.bind(finding.agentName, at: 6)
            try statement.bind(finding.sourcePath, at: 7)
            try statement.bind(finding.serverID, at: 8)
            try statement.bind(finding.serverName, at: 9)
            try statement.bind(finding.title, at: 10)
            try statement.bind(finding.whyItMatters, at: 11)
            try statement.bind(finding.suggestedFix, at: 12)
            try statement.stepDone()
        }
    }

    private func redactedDoctorReport(_ report: DoctorReport) -> DoctorReport {
        DoctorReport(findings: report.findings.map(redactedDoctorFinding))
    }

    private func redactedDoctorFinding(_ finding: DoctorFinding) -> DoctorFinding {
        DoctorFinding(
            severity: finding.severity,
            category: finding.category,
            agentName: redactedStoredText(finding.agentName),
            sourcePath: redactedStoredText(finding.sourcePath),
            serverID: finding.serverID.map(redactedStoredText),
            serverName: finding.serverName.map(redactedStoredText),
            title: redactedStoredText(finding.title),
            whyItMatters: redactedStoredText(finding.whyItMatters),
            suggestedFix: redactedStoredText(finding.suggestedFix)
        )
    }

    private func redactedStoredText(_ value: String) -> String {
        SecretRedactor.redactText(value)
    }

    private func redactedServer(_ server: ServerDefinition, for source: ConfigSource) -> ServerDefinition {
        ServerDefinition(
            id: ServerDefinition.canonicalID(agent: source.agent, sourcePath: source.path, name: server.displayName),
            displayName: SecretRedactor.redactText(server.displayName),
            transport: server.transport,
            command: server.command.map(SecretRedactor.redactText),
            args: SecretRedactor.redactCommandArguments(server.args),
            url: server.url.map(SecretRedactor.redactText),
            headers: server.redactedHeaders,
            envBindings: server.redactedEnvBindings,
            sourcePath: source.path
        )
    }

    private func countRows(in table: String, runID: String, database: OpaquePointer) throws -> Int {
        try countRows(in: table, idColumn: "run_id", runID: runID, database: database)
    }

    private func countRows(in table: String, idColumn: String, runID: String, database: OpaquePointer) throws -> Int {
        let statement = try SQLiteStatement(database: database, sql: "SELECT COUNT(*) FROM \(table) WHERE \(idColumn) = ?")
        try statement.bind(runID, at: 1)
        let stepResult = sqlite3_step(statement.pointer)
        guard stepResult == SQLITE_ROW else {
            throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
        }
        return Int(sqlite3_column_int64(statement.pointer, 0))
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteScanHistoryStoreError.invalidUTF8
        }
        return string
    }

    private func bulkRollbackTransactionRecord(from statement: SQLiteStatement) throws -> SQLiteBulkRollbackTransactionRecord {
        let planJSON = try stringColumn(statement, 3)
        let plan = try decoder.decode(AgentBulkConnectRollbackPlan.self, from: try data(from: planJSON))
        return SQLiteBulkRollbackTransactionRecord(
            transactionID: try stringColumn(statement, 0),
            status: try stringColumn(statement, 1),
            reason: try stringColumn(statement, 2),
            plan: plan,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 4)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 5))
        )
    }

    private func connectAllTargetProfileRecord(from statement: SQLiteStatement) throws -> SQLiteConnectAllTargetProfileRecord {
        let sourcesJSON = try stringColumn(statement, 1)
        let sources = try decoder.decode([ConfigSource].self, from: try data(from: sourcesJSON))
        return SQLiteConnectAllTargetProfileRecord(
            name: try stringColumn(statement, 0),
            targetSources: sources,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement.pointer, 2))
        )
    }

    private func normalizedProfileName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SQLiteScanHistoryStoreError.executionFailed("Connect All target profile name cannot be empty")
        }
        return normalized
    }

    private func uniqueSources(_ sources: [ConfigSource]) -> [ConfigSource] {
        var seen = Set<String>()
        var unique: [ConfigSource] = []
        for source in sources where seen.insert(source.id).inserted {
            unique.append(source)
        }
        return unique
    }

    private func data(from text: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw SQLiteScanHistoryStoreError.invalidUTF8
        }
        return data
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map(lastErrorMessage) ?? "unknown SQLite open error"
            if let database { sqlite3_close(database) }
            throw SQLiteScanHistoryStoreError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA foreign_keys = ON", database: database)
        return try body(database)
    }
}

private final class SQLiteStatement {
    let pointer: OpaquePointer
    private let database: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        self.database = database
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteScanHistoryStoreError.prepareFailed(lastErrorMessage(database))
        }
        self.pointer = statement
    }

    deinit {
        sqlite3_finalize(pointer)
    }

    func reset() throws {
        guard sqlite3_reset(pointer) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
        }
        sqlite3_clear_bindings(pointer)
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(pointer, index, value, -1, SQLITE_TRANSIENT)
        } else {
            result = sqlite3_bind_null(pointer, index)
        }
        guard result == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }

    func bind(_ value: Int, at index: Int32) throws {
        guard sqlite3_bind_int64(pointer, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }

    func bind(_ value: Int?, at index: Int32) throws {
        guard let value else {
            try bindNil(at: index)
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: UInt64?, at index: Int32) throws {
        guard let value else {
            try bindNil(at: index)
            return
        }
        let boundedValue = min(value, UInt64(Int64.max))
        guard sqlite3_bind_int64(pointer, index, sqlite3_int64(Int64(boundedValue))) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        guard let value else {
            try bindNil(at: index)
            return
        }
        guard sqlite3_bind_double(pointer, index, value) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }

    func bind(_ value: Double, at index: Int32) throws {
        guard sqlite3_bind_double(pointer, index, value) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }

    func stepDone() throws {
        let result = sqlite3_step(pointer)
        guard result == SQLITE_DONE else {
            throw SQLiteScanHistoryStoreError.stepFailed(lastErrorMessage(database))
        }
    }

    private func bindNil(at index: Int32) throws {
        guard sqlite3_bind_null(pointer, index) == SQLITE_OK else {
            throw SQLiteScanHistoryStoreError.bindFailed(lastErrorMessage(database))
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func stringColumn(_ statement: SQLiteStatement, _ index: Int32) throws -> String {
    guard let text = sqlite3_column_text(statement.pointer, index) else {
        throw SQLiteScanHistoryStoreError.invalidUTF8
    }
    return String(cString: text)
}

private func optionalStringColumn(_ statement: SQLiteStatement, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement.pointer, index) != SQLITE_NULL,
          let text = sqlite3_column_text(statement.pointer, index) else {
        return nil
    }
    return String(cString: text)
}

private func execute(_ sql: String, database: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
        let message: String
        if let errorMessage {
            message = String(cString: errorMessage)
            sqlite3_free(errorMessage)
        } else {
            message = lastErrorMessage(database)
        }
        throw SQLiteScanHistoryStoreError.executionFailed(message)
    }
}

private func lastErrorMessage(_ database: OpaquePointer) -> String {
    guard let message = sqlite3_errmsg(database) else { return "unknown SQLite error" }
    return String(cString: message)
}
