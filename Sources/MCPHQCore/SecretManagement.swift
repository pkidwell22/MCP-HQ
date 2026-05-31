import Foundation
import Security

public enum SecretFieldKind: String, Codable, Equatable, Sendable {
    case environment
    case header
}

public struct SecretLocation: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(serverID):\(field.rawValue):\(name)" }
    public let serverID: String
    public let serverDisplayName: String
    public let sourcePath: String
    public let field: SecretFieldKind
    public let name: String

    public init(serverID: String, serverDisplayName: String, sourcePath: String, field: SecretFieldKind, name: String) {
        self.serverID = serverID
        self.serverDisplayName = serverDisplayName
        self.sourcePath = sourcePath
        self.field = field
        self.name = name
    }
}

public struct KeychainSecretReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let defaultService = "com.mcphq.secrets"

    public var id: String { "\(service):\(account)" }
    public let service: String
    public let account: String

    public init(service: String = Self.defaultService, account: String) {
        self.service = service
        self.account = account
    }

    public static func stable(serverID: String, secretName: String, service: String = Self.defaultService) -> KeychainSecretReference {
        KeychainSecretReference(service: service, account: "\(serverID)/\(normalizedSecretName(secretName))")
    }

    public var configValue: String {
        "keychain://\(service)/\(Self.percentEncode(account))"
    }

    public static func parse(from value: String) -> KeychainSecretReference? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if trimmed.lowercased().hasPrefix("bearer keychain://") {
            candidate = String(trimmed.dropFirst("Bearer ".count))
        } else {
            candidate = trimmed
        }

        guard candidate.lowercased().hasPrefix("keychain://") else { return nil }
        let remainder = String(candidate.dropFirst("keychain://".count))
        guard let slashIndex = remainder.firstIndex(of: "/") else { return nil }
        let service = String(remainder[..<slashIndex])
        let encodedAccount = String(remainder[remainder.index(after: slashIndex)...])
        guard !service.isEmpty,
              !encodedAccount.isEmpty,
              let account = percentDecode(encodedAccount) else { return nil }
        return KeychainSecretReference(service: service, account: account)
    }

    private static func normalizedSecretName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" ? Character(scalar) : "_"
        }
        let normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_-").union(.whitespacesAndNewlines))
        return normalized.isEmpty ? "secret" : normalized
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=:")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func percentDecode(_ value: String) -> String? {
        value.removingPercentEncoding
    }
}

public struct DetectedSecret: Codable, Equatable, Sendable, Identifiable {
    public var id: String { location.id }
    public let location: SecretLocation
    public let reference: KeychainSecretReference
    public let replacementValue: String
    public let redactedValue: String

    public init(location: SecretLocation, reference: KeychainSecretReference, replacementValue: String, redactedValue: String) {
        self.location = location
        self.reference = reference
        self.replacementValue = replacementValue
        self.redactedValue = redactedValue
    }
}

public struct SecretMigrationResult: Equatable, Sendable {
    public let migratedServer: ServerDefinition
    public let storedReferences: [KeychainSecretReference]

    public init(migratedServer: ServerDefinition, storedReferences: [KeychainSecretReference]) {
        self.migratedServer = migratedServer
        self.storedReferences = storedReferences
    }
}

public struct SecretMigrationPlan: Equatable, Sendable {
    public let detectedSecrets: [DetectedSecret]

    public var literalSecretCount: Int { detectedSecrets.count }

    public var affectedServerIDs: [String] {
        Array(Set(detectedSecrets.map(\.location.serverID))).sorted()
    }

    public init(detectedSecrets: [DetectedSecret]) {
        self.detectedSecrets = detectedSecrets
    }
}

public struct SecretBatchMigrationResult: Equatable, Sendable {
    public let migratedServers: [ServerDefinition]
    public let storedReferences: [KeychainSecretReference]

    public init(migratedServers: [ServerDefinition], storedReferences: [KeychainSecretReference]) {
        self.migratedServers = migratedServers
        self.storedReferences = storedReferences
    }
}

public struct SecretMigrationWriteFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let failedSecret: DetectedSecret
    public let plannedSecrets: [DetectedSecret]
    public let storedReferences: [KeychainSecretReference]
    public let attemptedWriteCount: Int
    public let underlyingMessage: String

    public init(
        failedSecret: DetectedSecret,
        plannedSecrets: [DetectedSecret],
        storedReferences: [KeychainSecretReference],
        attemptedWriteCount: Int,
        underlyingError: Error
    ) {
        self.failedSecret = failedSecret
        self.plannedSecrets = plannedSecrets
        self.storedReferences = storedReferences
        self.attemptedWriteCount = attemptedWriteCount
        self.underlyingMessage = SecretRedactor.redactText(String(describing: underlyingError))
    }

    private init(
        failedSecret: DetectedSecret,
        plannedSecrets: [DetectedSecret],
        storedReferences: [KeychainSecretReference],
        attemptedWriteCount: Int,
        underlyingMessage: String
    ) {
        self.failedSecret = failedSecret
        self.plannedSecrets = plannedSecrets
        self.storedReferences = storedReferences
        self.attemptedWriteCount = attemptedWriteCount
        self.underlyingMessage = SecretRedactor.redactText(underlyingMessage)
    }

    public var failedReference: KeychainSecretReference { failedSecret.reference }
    public var writtenCount: Int { storedReferences.count }
    public var plannedCount: Int { plannedSecrets.count }
    public var pendingWriteCount: Int { max(plannedSecrets.count - attemptedWriteCount, 0) }

    public var failedAndPendingSecrets: [DetectedSecret] {
        guard let failedIndex = plannedSecrets.firstIndex(where: { $0.id == failedSecret.id }) else {
            return [failedSecret]
        }
        return Array(plannedSecrets[failedIndex...])
    }

    public var safeRecoveryAction: String {
        "MCP-HQ should keep the config snapshot unchanged or restore it, delete any Keychain references written during this failed attempt, then rerun migration after Keychain access is fixed. Do not paste plaintext secrets into config."
    }

    public var description: String {
        let location = failedSecret.location
        let referenceText = "service \(failedReference.service), account \(failedReference.account)"
        let partialText = writtenCount == 0
            ? "No Keychain references were written before the failure."
            : "\(writtenCount) Keychain reference\(writtenCount == 1 ? "" : "s") \(writtenCount == 1 ? "was" : "were") written before the failure and should be removed before retrying: \(storedReferences.map(Self.referenceLabel).joined(separator: ", "))."
        let pendingText = pendingWriteCount == 0
            ? "No later writes were pending."
            : "\(pendingWriteCount) later write\(pendingWriteCount == 1 ? "" : "s") were not attempted."
        return SecretRedactor.redactText(
            "Keychain migration write failed for \(location.serverDisplayName) \(location.field.rawValue) \(location.name) (\(referenceText)). \(partialText) \(pendingText) Underlying error: \(underlyingMessage). Safe recovery: \(safeRecoveryAction)"
        )
    }

    public func addingPriorStoredReferences(_ priorReferences: [KeychainSecretReference]) -> SecretMigrationWriteFailure {
        guard !priorReferences.isEmpty else { return self }
        return SecretMigrationWriteFailure(
            failedSecret: failedSecret,
            plannedSecrets: plannedSecrets,
            storedReferences: priorReferences + storedReferences,
            attemptedWriteCount: attemptedWriteCount,
            underlyingMessage: underlyingMessage
        )
    }

    private static func referenceLabel(_ reference: KeychainSecretReference) -> String {
        "service \(reference.service), account \(reference.account)"
    }
}

public enum SecretStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case notFound(KeychainSecretReference)
    case invalidValue
    case keychainStatus(operation: String, status: OSStatus)

    public var description: String {
        switch self {
        case .notFound(let reference):
            return "Secret not found in Keychain service \(reference.service) account \(reference.account)"
        case .invalidValue:
            return "Secret value was not valid UTF-8"
        case .keychainStatus(let operation, let status):
            return "Keychain \(operation) failed with status \(status)"
        }
    }
}

public protocol SecretStore: Sendable {
    func setSecret(_ value: String, for reference: KeychainSecretReference) throws
    func readSecret(for reference: KeychainSecretReference) throws -> String?
    func secretExists(for reference: KeychainSecretReference) throws -> Bool
    func deleteSecret(for reference: KeychainSecretReference) throws
}

public struct MacOSKeychainSecretStore: SecretStore {
    public init() {}

    public func setSecret(_ value: String, for reference: KeychainSecretReference) throws {
        guard let data = value.data(using: .utf8) else { throw SecretStoreError.invalidValue }
        let query = baseQuery(reference)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychainStatus(operation: "update", status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychainStatus(operation: "add", status: addStatus)
        }
    }

    public func readSecret(for reference: KeychainSecretReference) throws -> String? {
        var query = baseQuery(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychainStatus(operation: "read", status: status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidValue
        }
        return value
    }

    public func secretExists(for reference: KeychainSecretReference) throws -> Bool {
        var query = baseQuery(reference)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychainStatus(operation: "lookup", status: status)
        }
        return true
    }

    public func deleteSecret(for reference: KeychainSecretReference) throws {
        let status = SecItemDelete(baseQuery(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychainStatus(operation: "delete", status: status)
        }
    }

    private func baseQuery(_ reference: KeychainSecretReference) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [KeychainSecretReference: String]
    private let lock = NSLock()

    public init(values: [KeychainSecretReference: String] = [:]) {
        self.values = values
    }

    public func setSecret(_ value: String, for reference: KeychainSecretReference) throws {
        lock.withLock { values[reference] = value }
    }

    public func readSecret(for reference: KeychainSecretReference) throws -> String? {
        lock.withLock { values[reference] }
    }

    public func secretExists(for reference: KeychainSecretReference) throws -> Bool {
        lock.withLock { values[reference] != nil }
    }

    public func deleteSecret(for reference: KeychainSecretReference) throws {
        lock.withLock { _ = values.removeValue(forKey: reference) }
    }
}

public struct SecretDetector: Sendable {
    public init() {}

    public func detect(in server: ServerDefinition) -> [DetectedSecret] {
        let envSecrets = server.envBindings.keys.sorted().compactMap { key -> DetectedSecret? in
            guard let value = server.envBindings[key], shouldMigrate(value: value, fieldName: key) else { return nil }
            let location = SecretLocation(serverID: server.id, serverDisplayName: server.displayName, sourcePath: server.sourcePath, field: .environment, name: key)
            let reference = KeychainSecretReference.stable(serverID: server.id, secretName: key)
            return DetectedSecret(
                location: location,
                reference: reference,
                replacementValue: reference.configValue,
                redactedValue: redactedSecretValue(value, fieldName: key)
            )
        }

        let headerSecrets = server.headers.keys.sorted().compactMap { key -> DetectedSecret? in
            guard let value = server.headers[key], shouldMigrate(value: value, fieldName: key) else { return nil }
            let location = SecretLocation(serverID: server.id, serverDisplayName: server.displayName, sourcePath: server.sourcePath, field: .header, name: key)
            let reference = KeychainSecretReference.stable(serverID: server.id, secretName: "header_\(key)")
            return DetectedSecret(
                location: location,
                reference: reference,
                replacementValue: replacementValue(for: value, reference: reference),
                redactedValue: redactedSecretValue(value, fieldName: key)
            )
        }

        return envSecrets + headerSecrets
    }

    public func migrationPlan(for servers: [ServerDefinition]) -> SecretMigrationPlan {
        SecretMigrationPlan(detectedSecrets: servers.flatMap { detect(in: $0) })
    }

    public func migrating(_ servers: [ServerDefinition], store: SecretStore) throws -> SecretBatchMigrationResult {
        var migratedServers: [ServerDefinition] = []
        var storedReferences: [KeychainSecretReference] = []

        for server in servers {
            do {
                let result = try migrating(server, store: store)
                migratedServers.append(result.migratedServer)
                storedReferences.append(contentsOf: result.storedReferences)
            } catch let failure as SecretMigrationWriteFailure {
                throw failure.addingPriorStoredReferences(storedReferences)
            }
        }

        return SecretBatchMigrationResult(migratedServers: migratedServers, storedReferences: storedReferences)
    }

    public func migrating(_ server: ServerDefinition, store: SecretStore) throws -> SecretMigrationResult {
        var env = server.envBindings
        var headers = server.headers
        var storedReferences: [KeychainSecretReference] = []
        let plannedSecrets = detect(in: server)

        for (index, secret) in plannedSecrets.enumerated() {
            let value: String?
            switch secret.location.field {
            case .environment:
                value = server.envBindings[secret.location.name]
            case .header:
                value = server.headers[secret.location.name]
            }
            guard let value else { continue }

            do {
                try store.setSecret(value, for: secret.reference)
            } catch {
                throw SecretMigrationWriteFailure(
                    failedSecret: secret,
                    plannedSecrets: plannedSecrets,
                    storedReferences: storedReferences,
                    attemptedWriteCount: index + 1,
                    underlyingError: error
                )
            }

            switch secret.location.field {
            case .environment:
                env[secret.location.name] = secret.replacementValue
            case .header:
                headers[secret.location.name] = secret.replacementValue
            }
            storedReferences.append(secret.reference)
        }

        let migrated = ServerDefinition(
            id: server.id,
            displayName: server.displayName,
            transport: server.transport,
            command: server.command,
            args: server.args,
            url: server.url,
            headers: headers,
            envBindings: env,
            sourcePath: server.sourcePath
        )
        return SecretMigrationResult(migratedServer: migrated, storedReferences: storedReferences)
    }

    private func shouldMigrate(value: String, fieldName: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isExistingReference(trimmed) { return false }
        if isSensitiveName(fieldName) { return true }
        if isLikelyNonSecretLiteral(trimmed, fieldName: fieldName) { return false }
        return SecretRedactor.redactText(trimmed) != trimmed || SecretRedactor.redactIfSensitive(trimmed) == "<redacted>"
    }

    private func isExistingReference(_ value: String) -> Bool {
        value.hasPrefix("$") || value.contains("${") || KeychainSecretReference.parse(from: value) != nil
    }

    private func isSensitiveName(_ name: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        let sensitiveParts = ["token", "api_key", "apikey", "secret", "password", "authorization", "auth"]
        return sensitiveParts.contains { normalized.contains($0) }
    }

    private func isLikelyNonSecretLiteral(_ value: String, fieldName: String) -> Bool {
        let normalizedName = fieldName.lowercased().replacingOccurrences(of: "-", with: "_")
        if normalizedName.hasSuffix("_path") || normalizedName == "path" {
            return true
        }
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }
        if value.lowercased().hasPrefix("file://") {
            return true
        }
        if isDigestOrFingerprintList(value, fieldName: fieldName) {
            return true
        }
        return false
    }

    private func isDigestOrFingerprintList(_ value: String, fieldName: String) -> Bool {
        let normalizedName = fieldName.lowercased().replacingOccurrences(of: "-", with: "_")
        let nameSignals = ["sha", "sha256", "fingerprint", "digest", "checksum", "trusted"]
        guard nameSignals.contains(where: { normalizedName.contains($0) }) else { return false }

        let separators = CharacterSet(charactersIn: ",;: \n\t")
        let parts = value
            .split(whereSeparator: { scalar in
                guard let first = String(scalar).unicodeScalars.first else { return false }
                return separators.contains(first)
            })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }

        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return parts.allSatisfy { part in
            let length = part.count
            guard length == 32 || length == 40 || length == 64 || length == 96 || length == 128 else { return false }
            return part.unicodeScalars.allSatisfy { hexDigits.contains($0) }
        }
    }

    private func redactedSecretValue(_ value: String, fieldName: String) -> String {
        let redacted = SecretRedactor.redactIfSensitive(SecretRedactor.redactText(value))
        if redacted != value { return redacted }
        return isSensitiveName(fieldName) ? "<redacted>" : redacted
    }

    private func replacementValue(for value: String, reference: KeychainSecretReference) -> String {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("bearer ") {
            return "Bearer \(reference.configValue)"
        }
        return reference.configValue
    }
}

public enum SecretPresenceStatus: String, Codable, Equatable, Sendable {
    case present
    case missing
    case unavailable
}

public enum SecretRecoveryStatus: String, Codable, Equatable, Sendable {
    case present
    case missing
    case inaccessible
    case migrationWriteFailed = "migration_write_failed"
}

public struct SecretPresenceCheck: Codable, Equatable, Sendable, Identifiable {
    public var id: String { reference.id }
    public let reference: KeychainSecretReference
    public let status: SecretPresenceStatus
    public let message: String

    public init(reference: KeychainSecretReference, status: SecretPresenceStatus, message: String) {
        self.reference = reference
        self.status = status
        self.message = SecretRedactor.redactText(message)
    }
}

public struct SecretRecoveryState: Codable, Equatable, Sendable, Identifiable {
    public var id: String { secretID ?? "\(sourcePath):\(serverName ?? ""):\(fieldKind.rawValue):\(fieldName):\(reference.id)" }
    public let secretID: String?
    public let sourcePath: String
    public let serverName: String?
    public let fieldKind: SecretFieldKind
    public let fieldName: String
    public let reference: KeychainSecretReference
    public let presence: SecretPresenceCheck
    public let recoveryStatus: SecretRecoveryStatus
    public let previousStatus: String?
    public let validatedAt: Date?
    public let summary: String
    public let safeAction: String

    public init(
        secretID: String? = nil,
        sourcePath: String,
        serverName: String?,
        fieldKind: SecretFieldKind,
        fieldName: String,
        reference: KeychainSecretReference,
        presence: SecretPresenceCheck,
        previousStatus: String? = nil,
        validatedAt: Date? = nil
    ) {
        self.secretID = secretID
        self.sourcePath = sourcePath
        self.serverName = serverName
        self.fieldKind = fieldKind
        self.fieldName = fieldName
        self.reference = reference
        self.presence = presence
        self.recoveryStatus = Self.recoveryStatus(for: presence.status, previousStatus: previousStatus)
        self.previousStatus = previousStatus.map(SecretRedactor.redactText)
        self.validatedAt = validatedAt
        self.summary = Self.summary(
            status: self.recoveryStatus,
            serverName: serverName,
            fieldKind: fieldKind,
            fieldName: fieldName,
            reference: reference,
            presenceMessage: presence.message
        )
        self.safeAction = Self.safeAction(status: self.recoveryStatus)
    }

    public var isRecoverable: Bool { recoveryStatus != .present }
    public var persistedStatus: String { recoveryStatus.rawValue }

    public func diagnosticMessage(serverDisplayName: String, fieldDescription: String) -> String {
        let referenceText = "service \(reference.service), account \(reference.account)"
        switch recoveryStatus {
        case .present:
            return "Keychain secret is present for \(serverDisplayName) \(fieldDescription) \(fieldName) (\(referenceText))."
        case .missing:
            return "Missing Keychain secret for \(serverDisplayName) \(fieldDescription) \(fieldName) (\(referenceText)). Safe recovery: \(safeAction)"
        case .inaccessible:
            return "Could not validate Keychain secret for \(serverDisplayName) \(fieldDescription) \(fieldName) (\(referenceText)). Safe recovery: \(safeAction)"
        case .migrationWriteFailed:
            return "Previous Keychain migration write failed for \(serverDisplayName) \(fieldDescription) \(fieldName) (\(referenceText)). Safe recovery: \(safeAction)"
        }
    }

    private static func recoveryStatus(for presenceStatus: SecretPresenceStatus, previousStatus: String?) -> SecretRecoveryStatus {
        if let previousStatus, isMigrationWriteFailureStatus(previousStatus) {
            return .migrationWriteFailed
        }
        switch presenceStatus {
        case .present:
            return .present
        case .missing:
            return .missing
        case .unavailable:
            return .inaccessible
        }
    }

    private static func isMigrationWriteFailureStatus(_ status: String) -> Bool {
        let normalized = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return normalized == "writefailed" || normalized == "migrationwritefailed"
    }

    private static func summary(
        status: SecretRecoveryStatus,
        serverName: String?,
        fieldKind: SecretFieldKind,
        fieldName: String,
        reference: KeychainSecretReference,
        presenceMessage: String
    ) -> String {
        let serverText = serverName.map { " for \($0)" } ?? ""
        let fieldText = fieldKind == .environment ? "environment" : "header"
        let referenceText = "service \(reference.service), account \(reference.account)"
        switch status {
        case .present:
            return "Keychain secret\(serverText) \(fieldText) \(fieldName) is present (\(referenceText))."
        case .missing:
            return "Keychain secret\(serverText) \(fieldText) \(fieldName) is missing (\(referenceText))."
        case .inaccessible:
            let redactedMessage = SecretRedactor.redactText(presenceMessage)
            return "Keychain secret\(serverText) \(fieldText) \(fieldName) could not be validated (\(referenceText)): \(redactedMessage)."
        case .migrationWriteFailed:
            let redactedMessage = SecretRedactor.redactText(presenceMessage)
            return "Previous Keychain migration write failed for\(serverText) \(fieldText) \(fieldName) (\(referenceText)); config snapshots and partial Keychain writes should be rolled back before retrying. Latest presence check: \(redactedMessage)."
        }
    }

    private static func safeAction(status: SecretRecoveryStatus) -> String {
        switch status {
        case .present:
            return "No recovery action is needed."
        case .missing:
            return "Re-enter the secret value and migrate/store it back to Keychain; do not paste plaintext into config. If the credential was intentionally removed, remove the keychain:// reference."
        case .inaccessible:
            return "Unlock Keychain and grant access to MCP-HQ or this terminal, then rerun validation. If access cannot be restored, re-enter the secret and migrate/store it back to Keychain."
        case .migrationWriteFailed:
            return "Confirm MCP-HQ rolled back config snapshots and deleted partial Keychain writes, then rerun migration after fixing Keychain access. Do not paste plaintext into config; if retry is not desired, leave the literal secret unchanged or remove the pending migration row."
        }
    }
}

public struct SecretRecoveryReport: Codable, Equatable, Sendable {
    public let states: [SecretRecoveryState]

    public init(states: [SecretRecoveryState]) {
        self.states = states
    }

    public var checkedCount: Int { states.count }
    public var presentCount: Int { states.filter { $0.recoveryStatus == .present }.count }
    public var missingCount: Int { states.filter { $0.recoveryStatus == .missing }.count }
    public var inaccessibleCount: Int { states.filter { $0.recoveryStatus == .inaccessible }.count }
    public var migrationWriteFailureCount: Int { states.filter { $0.recoveryStatus == .migrationWriteFailed }.count }
    public var recoverableStates: [SecretRecoveryState] { states.filter(\.isRecoverable) }
}

public struct SecretPresenceValidator {
    private let store: SecretStore

    public init(store: SecretStore) {
        self.store = store
    }

    public func validate(_ reference: KeychainSecretReference) -> SecretPresenceCheck {
        do {
            if try store.secretExists(for: reference) {
                return SecretPresenceCheck(reference: reference, status: .present, message: "Secret is present")
            }
            return SecretPresenceCheck(reference: reference, status: .missing, message: "Secret is missing")
        } catch {
            return SecretPresenceCheck(
                reference: reference,
                status: .unavailable,
                message: "Secret presence could not be validated: \(SecretRedactor.redactText(String(describing: error)))"
            )
        }
    }
}

public struct SecretRecoveryReporter {
    private let validator: SecretPresenceValidator

    public init(store: SecretStore) {
        self.validator = SecretPresenceValidator(store: store)
    }

    public func state(
        secretID: String? = nil,
        sourcePath: String,
        serverName: String?,
        fieldKind: SecretFieldKind,
        fieldName: String,
        reference: KeychainSecretReference,
        previousStatus: String? = nil,
        validatedAt: Date? = nil
    ) -> SecretRecoveryState {
        SecretRecoveryState(
            secretID: secretID,
            sourcePath: sourcePath,
            serverName: serverName,
            fieldKind: fieldKind,
            fieldName: fieldName,
            reference: reference,
            presence: validator.validate(reference),
            previousStatus: previousStatus,
            validatedAt: validatedAt
        )
    }

    public func report(records: [SQLiteSecretBindingRecord], validatedAt: Date = Date()) -> SecretRecoveryReport {
        let states = records.map { record in
            state(
                secretID: record.secretID,
                sourcePath: record.sourcePath,
                serverName: record.serverName,
                fieldKind: record.fieldKind,
                fieldName: record.fieldName,
                reference: record.reference,
                previousStatus: record.status,
                validatedAt: validatedAt
            )
        }
        return SecretRecoveryReport(states: states)
    }
}

public struct SecretMigrationWriteFailureRecoveryPlan: Equatable, Sendable {
    public let targetSecretIDs: [String]
    public let referencesToDelete: [KeychainSecretReference]

    public init(states: [SecretRecoveryState]) {
        var seenIDs = Set<String>()
        var targetSecretIDs: [String] = []
        for state in states where state.recoveryStatus == .migrationWriteFailed {
            guard seenIDs.insert(state.id).inserted else { continue }
            targetSecretIDs.append(state.id)
        }

        self.targetSecretIDs = targetSecretIDs
        self.referencesToDelete = Array(
            Set(targetSecretIDs.compactMap { id in
                states.first(where: { $0.id == id })?.reference
            })
        ).sorted {
            $0.service == $1.service ? $0.account < $1.account : $0.service < $1.service
        }
    }

    public var isEmpty: Bool { targetSecretIDs.isEmpty || referencesToDelete.isEmpty }
    public var canRetry: Bool { !isEmpty }

    public var previewMessage: String {
        if isEmpty {
            return "No migration-write-failed Keychain references are pending cleanup."
        }
        return "Planned cleanup for \(targetSecretIDs.count) migration-write-failed row(s) covering \(referencesToDelete.count) Keychain reference(s)."
    }
}

public struct SecretMigrationWriteFailureRecoveryResult: Equatable, Sendable {
    public let attemptedReferenceCount: Int
    public let deletedReferenceCount: Int
    public let alreadyMissingReferenceCount: Int

    public init(attemptedReferenceCount: Int, deletedReferenceCount: Int, alreadyMissingReferenceCount: Int) {
        self.attemptedReferenceCount = attemptedReferenceCount
        self.deletedReferenceCount = deletedReferenceCount
        self.alreadyMissingReferenceCount = alreadyMissingReferenceCount
    }

    public var message: String {
        guard attemptedReferenceCount > 0 else {
            return "No migration-write-failed cleanup actions were needed."
        }

        return [
            "Migration-write-failed cleanup complete:",
            "\(deletedReferenceCount) reference(s) deleted.",
            "\(alreadyMissingReferenceCount) already missing (idempotent cleanup)."
        ].joined(separator: " ")
    }
}

public struct SecretMigrationWriteFailureRecoveryService {
    public init() {}

    public func plan(
        for states: [SecretRecoveryState],
        secretIDs: Set<String>? = nil
    ) -> SecretMigrationWriteFailureRecoveryPlan {
        let filteredStates = if let secretIDs {
            states.filter { secretIDs.contains($0.id) }
        } else {
            states
        }
        return SecretMigrationWriteFailureRecoveryPlan(states: filteredStates)
    }

    public func execute(
        plan: SecretMigrationWriteFailureRecoveryPlan,
        store: SecretStore
    ) throws -> SecretMigrationWriteFailureRecoveryResult {
        guard !plan.referencesToDelete.isEmpty else {
            return SecretMigrationWriteFailureRecoveryResult(
                attemptedReferenceCount: 0,
                deletedReferenceCount: 0,
                alreadyMissingReferenceCount: 0
            )
        }

        var deletedCount = 0
        var missingCount = 0
        for reference in plan.referencesToDelete {
            guard try store.secretExists(for: reference) else {
                missingCount += 1
                continue
            }

            do {
                try store.deleteSecret(for: reference)
                deletedCount += 1
            } catch {
                if case let SecretStoreError.keychainStatus(_, status) = error,
                   status == errSecItemNotFound {
                    missingCount += 1
                } else {
                    throw error
                }
            }
        }
        return SecretMigrationWriteFailureRecoveryResult(
            attemptedReferenceCount: plan.referencesToDelete.count,
            deletedReferenceCount: deletedCount,
            alreadyMissingReferenceCount: missingCount
        )
    }
}
