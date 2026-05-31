import XCTest
@testable import MCPHQCore

final class SecretManagementTests: XCTestCase {
    func testDetectsLiteralEnvironmentAndHeaderSecrets() throws {
        let server = ServerDefinition(
            id: "github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            headers: ["Authorization": "Bearer ghp_headersecret1234567890"],
            envBindings: [
                "GITHUB_TOKEN": "ghp_envsecret1234567890",
                "SAFE_REFERENCE": "${GITHUB_TOKEN}",
            ],
            sourcePath: "/tmp/claude.json"
        )

        let detected = SecretDetector().detect(in: server)

        XCTAssertEqual(detected.map(\.location.name), ["GITHUB_TOKEN", "Authorization"])
        XCTAssertEqual(detected[0].replacementValue, KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN").configValue)
        XCTAssertEqual(detected[1].replacementValue, "Bearer \(KeychainSecretReference.stable(serverID: "github", secretName: "header_Authorization").configValue)")
        XCTAssertFalse(String(describing: detected).contains("ghp_envsecret"))
        XCTAssertFalse(String(describing: detected).contains("ghp_headersecret"))
    }

    func testMigratesSecretsIntoStoreAndReplacesConfigValues() throws {
        let server = ServerDefinition(
            id: "github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            headers: ["Authorization": "Bearer ghp_headersecret1234567890"],
            envBindings: ["GITHUB_TOKEN": "ghp_envsecret1234567890"],
            sourcePath: "/tmp/claude.json"
        )
        let store = InMemorySecretStore()

        let result = try SecretDetector().migrating(server, store: store)

        XCTAssertEqual(result.storedReferences.count, 2)
        XCTAssertEqual(result.migratedServer.envBindings["GITHUB_TOKEN"], KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN").configValue)
        XCTAssertEqual(result.migratedServer.headers["Authorization"], "Bearer \(KeychainSecretReference.stable(serverID: "github", secretName: "header_Authorization").configValue)")
        XCTAssertEqual(try store.readSecret(for: KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")), "ghp_envsecret1234567890")
        XCTAssertEqual(try store.readSecret(for: KeychainSecretReference.stable(serverID: "github", secretName: "header_Authorization")), "Bearer ghp_headersecret1234567890")
    }

    func testDetectorDoesNotMigratePlainPathOrTrustedDigestValuesThatLookTokenLike() throws {
        let server = ServerDefinition(
            id: "node-repl",
            displayName: "node_repl",
            transport: .stdio,
            command: "node",
            envBindings: [
                "SKY_CUA_SERVICE_PATH": "/Users/patkidwell/Library/Application Support/Codex/2026/service",
                "NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S": "a1b2c3d4e5f678901234567890abcdef",
            ],
            sourcePath: "/tmp/codex.toml"
        )

        let detected = SecretDetector().detect(in: server)

        XCTAssertTrue(detected.isEmpty)
        XCTAssertFalse(detected.map(\.location.name).contains("SKY_CUA_SERVICE_PATH"))
    }

    func testMigrationPlanAndBatchMigrationDoNotExposePlaintext() throws {
        let first = ServerDefinition(
            id: "claude:/tmp/claude.json:github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            envBindings: ["API_TOKEN": "short"],
            sourcePath: "/tmp/claude.json"
        )
        let second = ServerDefinition(
            id: "gemini:/tmp/gemini.json:github",
            displayName: "GitHub",
            transport: .http,
            headers: ["Authorization": "Bearer short"],
            sourcePath: "/tmp/gemini.json"
        )
        let detector = SecretDetector()

        let plan = detector.migrationPlan(for: [first, second])

        XCTAssertEqual(plan.literalSecretCount, 2)
        XCTAssertEqual(plan.affectedServerIDs, [first.id, second.id])
        XCTAssertEqual(Set(plan.detectedSecrets.map(\.redactedValue)), ["<redacted>"])
        XCTAssertFalse(String(describing: plan).contains("Bearer short"))

        let store = InMemorySecretStore()
        let result = try detector.migrating([first, second], store: store)

        XCTAssertEqual(result.storedReferences.count, 2)
        XCTAssertEqual(result.migratedServers[0].envBindings["API_TOKEN"], KeychainSecretReference.stable(serverID: first.id, secretName: "API_TOKEN").configValue)
        XCTAssertEqual(result.migratedServers[1].headers["Authorization"], "Bearer \(KeychainSecretReference.stable(serverID: second.id, secretName: "header_Authorization").configValue)")
        XCTAssertEqual(try store.readSecret(for: KeychainSecretReference.stable(serverID: first.id, secretName: "API_TOKEN")), "short")
        XCTAssertEqual(try store.readSecret(for: KeychainSecretReference.stable(serverID: second.id, secretName: "header_Authorization")), "Bearer short")
    }

    func testMigrationWriteFailureReportsPartialWritesWithoutPlaintext() throws {
        let server = ServerDefinition(
            id: "github",
            displayName: "GitHub",
            transport: .stdio,
            command: "npx",
            headers: ["Authorization": "Bearer ghp_headersecret1234567890"],
            envBindings: ["GITHUB_TOKEN": "ghp_envsecret1234567890"],
            sourcePath: "/tmp/claude.json"
        )
        let store = FailingWriteSecretStore(failOnAttempt: 2)

        XCTAssertThrowsError(try SecretDetector().migrating(server, store: store)) { error in
            guard let failure = error as? SecretMigrationWriteFailure else {
                return XCTFail("Expected SecretMigrationWriteFailure, got \(error)")
            }
            XCTAssertEqual(failure.writtenCount, 1)
            XCTAssertEqual(failure.plannedCount, 2)
            XCTAssertEqual(failure.pendingWriteCount, 0)
            XCTAssertEqual(failure.failedSecret.location.name, "Authorization")
            XCTAssertEqual(failure.storedReferences, [KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")])
            XCTAssertEqual(failure.failedAndPendingSecrets.map(\.location.name), ["Authorization"])
            XCTAssertTrue(failure.description.contains("1 Keychain reference"))
            XCTAssertTrue(failure.description.contains("Safe recovery"))
            XCTAssertFalse(failure.description.contains("ghp_envsecret"))
            XCTAssertFalse(failure.description.contains("ghp_headersecret"))
            XCTAssertFalse(String(describing: failure).contains("ghp_envsecret"))
            XCTAssertFalse(String(describing: failure).contains("ghp_headersecret"))
        }

        XCTAssertEqual(store.values.count, 1)
    }

    func testBatchMigrationWriteFailureIncludesPriorSuccessfulReferencesForRollback() throws {
        let first = ServerDefinition(
            id: "first",
            displayName: "First",
            transport: .stdio,
            command: "npx",
            envBindings: ["API_TOKEN": "first-secret"],
            sourcePath: "/tmp/first.json"
        )
        let second = ServerDefinition(
            id: "second",
            displayName: "Second",
            transport: .stdio,
            command: "npx",
            envBindings: ["API_TOKEN": "second-secret"],
            sourcePath: "/tmp/second.json"
        )
        let store = FailingWriteSecretStore(failOnAttempt: 2)

        XCTAssertThrowsError(try SecretDetector().migrating([first, second], store: store)) { error in
            guard let failure = error as? SecretMigrationWriteFailure else {
                return XCTFail("Expected SecretMigrationWriteFailure, got \(error)")
            }
            XCTAssertEqual(failure.storedReferences, [KeychainSecretReference.stable(serverID: "first", secretName: "API_TOKEN")])
            XCTAssertEqual(failure.failedSecret.location.serverID, "second")
            XCTAssertFalse(failure.description.contains("first-secret"))
            XCTAssertFalse(failure.description.contains("second-secret"))
        }
    }

    func testMigrationWriteFailureRecoveryPlanTargetsOnlyMigrationRows() {
        let missingReference = KeychainSecretReference.stable(serverID: "github", secretName: "OTHER_TOKEN")
        let migrationReference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let missingState = SecretRecoveryState(
            secretID: "github:environment:OTHER_TOKEN",
            sourcePath: "/tmp/other.json",
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "OTHER_TOKEN",
            reference: missingReference,
            presence: SecretPresenceCheck(
                reference: missingReference,
                status: .missing,
                message: "Secret is missing"
            ),
            previousStatus: "present",
            validatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let migrationState = SecretRecoveryState(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: "/tmp/claude.json",
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: migrationReference,
            presence: SecretPresenceCheck(
                reference: migrationReference,
                status: .missing,
                message: "Secret is missing"
            ),
            previousStatus: SecretRecoveryStatus.migrationWriteFailed.rawValue,
            validatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let plan = SecretMigrationWriteFailureRecoveryService().plan(
            for: [missingState, migrationState],
            secretIDs: nil
        )

        XCTAssertTrue(plan.canRetry)
        XCTAssertEqual(plan.targetSecretIDs, ["github:environment:GITHUB_TOKEN"])
        XCTAssertEqual(plan.referencesToDelete, [migrationReference])
        XCTAssertFalse(plan.previewMessage.contains("other-token"))
    }

    func testMigrationWriteFailureCleanupIsIdempotent() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let failureState = SecretRecoveryState(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: "/tmp/claude.json",
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: reference,
            presence: SecretPresenceCheck(reference: reference, status: .missing, message: "Secret is missing"),
            previousStatus: SecretRecoveryStatus.migrationWriteFailed.rawValue,
            validatedAt: Date(timeIntervalSince1970: 2_500)
        )
        let store = InMemorySecretStore(values: [reference: "ghp_retrySecret1234567890"])
        let service = SecretMigrationWriteFailureRecoveryService()
        let plan = service.plan(for: [failureState], secretIDs: nil)

        let firstRun = try service.execute(plan: plan, store: store)
        XCTAssertEqual(firstRun.attemptedReferenceCount, 1)
        XCTAssertEqual(firstRun.deletedReferenceCount, 1)
        XCTAssertEqual(firstRun.alreadyMissingReferenceCount, 0)
        XCTAssertFalse(try store.secretExists(for: reference))

        let secondRun = try service.execute(plan: plan, store: store)
        XCTAssertEqual(secondRun.attemptedReferenceCount, 1)
        XCTAssertEqual(secondRun.deletedReferenceCount, 0)
        XCTAssertEqual(secondRun.alreadyMissingReferenceCount, 1)
    }

    func testMigrationWriteFailureRecoveryResultDoesNotExposePlainText() throws {
        let sensitiveValue = "ghp_recoverySecret1234567890"
        let failureReference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let recoveryState = SecretRecoveryState(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: "/tmp/claude.json",
            serverName: "GitHub",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: failureReference,
            presence: SecretPresenceCheck(
                reference: failureReference,
                status: .missing,
                message: "Secret value was \(sensitiveValue)"
            ),
            previousStatus: SecretRecoveryStatus.migrationWriteFailed.rawValue,
            validatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let service = SecretMigrationWriteFailureRecoveryService()
        let report = SecretRecoveryReport(states: [recoveryState])
        let plan = service.plan(for: report.recoverableStates)
        let store = InMemorySecretStore(values: [failureReference: sensitiveValue])

        let result = try service.execute(plan: plan, store: store)

        XCTAssertFalse(plan.previewMessage.contains(sensitiveValue))
        XCTAssertFalse(result.message.contains(sensitiveValue))
        XCTAssertFalse(String(describing: result).contains(sensitiveValue))
    }

    func testKeychainReferenceRoundTripsPercentEncodedAccount() throws {
        let reference = KeychainSecretReference.stable(serverID: "agent:/tmp/config.json:github", secretName: "AUTH TOKEN")

        let parsed = try XCTUnwrap(KeychainSecretReference.parse(from: reference.configValue))

        XCTAssertEqual(parsed, reference)
        XCTAssertTrue(reference.configValue.contains("%2F"))
    }

    func testPresenceValidatorDoesNotReadOrExposeSecretValue() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let store = InMemorySecretStore(values: [reference: "ghp_realvalue1234567890"])

        let check = SecretPresenceValidator(store: store).validate(reference)

        XCTAssertEqual(check.status, .present)
        XCTAssertEqual(check.message, "Secret is present")
        XCTAssertFalse(String(describing: check).contains("ghp_realvalue"))
    }

    func testRecoveryReporterUsesPresenceOnlyForMissingAndInaccessibleStates() throws {
        let missingReference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let missingRecord = SQLiteSecretBindingRecord(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: "/tmp/claude.json",
            serverName: "github",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: missingReference,
            status: "present",
            updatedAt: Date(timeIntervalSince1970: 1),
            validatedAt: nil
        )
        let missingReport = SecretRecoveryReporter(store: InMemorySecretStore())
            .report(records: [missingRecord], validatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(missingReport.missingCount, 1)
        XCTAssertEqual(missingReport.recoverableStates.first?.recoveryStatus, .missing)
        XCTAssertTrue(missingReport.recoverableStates.first?.safeAction.contains("Re-enter the secret value") == true)

        let inaccessibleStore = ThrowingPresenceSecretStore()
        let inaccessibleReport = SecretRecoveryReporter(store: inaccessibleStore)
            .report(records: [missingRecord], validatedAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(inaccessibleReport.inaccessibleCount, 1)
        XCTAssertEqual(inaccessibleReport.recoverableStates.first?.recoveryStatus, .inaccessible)
        XCTAssertEqual(inaccessibleStore.readCount, 0)
        XCTAssertTrue(inaccessibleReport.recoverableStates.first?.safeAction.contains("rerun validation") == true)
        XCTAssertFalse(String(describing: inaccessibleReport).contains("ghp_"))
    }

    func testRecoveryReporterDistinguishesMigrationWriteFailureRows() throws {
        let reference = KeychainSecretReference.stable(serverID: "github", secretName: "GITHUB_TOKEN")
        let record = SQLiteSecretBindingRecord(
            secretID: "github:environment:GITHUB_TOKEN",
            sourcePath: "/tmp/claude.json",
            serverName: "github",
            fieldKind: .environment,
            fieldName: "GITHUB_TOKEN",
            reference: reference,
            status: SecretRecoveryStatus.migrationWriteFailed.rawValue,
            updatedAt: Date(timeIntervalSince1970: 1),
            validatedAt: nil
        )

        let report = SecretRecoveryReporter(store: InMemorySecretStore())
            .report(records: [record], validatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(report.migrationWriteFailureCount, 1)
        XCTAssertEqual(report.missingCount, 0)
        XCTAssertEqual(report.recoverableStates.first?.recoveryStatus, .migrationWriteFailed)
        XCTAssertTrue(report.recoverableStates.first?.summary.contains("migration write failed") == true)
        XCTAssertTrue(report.recoverableStates.first?.safeAction.contains("deleted partial Keychain writes") == true)
    }

    func testRealKeychainStoreSmokeTestIsOptIn() throws {
        guard ProcessInfo.processInfo.environment["MCPHQ_RUN_KEYCHAIN_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set MCPHQ_RUN_KEYCHAIN_INTEGRATION_TESTS=1 to run the real Keychain integration test.")
        }
        let reference = KeychainSecretReference(service: "com.mcphq.tests", account: UUID().uuidString)
        let store = MacOSKeychainSecretStore()
        try store.setSecret("integration-secret", for: reference)
        defer { try? store.deleteSecret(for: reference) }

        XCTAssertTrue(try store.secretExists(for: reference))
        XCTAssertEqual(try store.readSecret(for: reference), "integration-secret")
    }
}

private final class FailingWriteSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private let failOnAttempt: Int
    private var attempts = 0
    private(set) var values: [KeychainSecretReference: String] = [:]

    init(failOnAttempt: Int) {
        self.failOnAttempt = failOnAttempt
    }

    func setSecret(_ value: String, for reference: KeychainSecretReference) throws {
        try lock.withLock {
            attempts += 1
            if attempts == failOnAttempt {
                throw SecretStoreError.keychainStatus(operation: "add token ghp_shouldRedact1234567890", status: -25308)
            }
            values[reference] = value
        }
    }

    func readSecret(for reference: KeychainSecretReference) throws -> String? {
        lock.withLock { values[reference] }
    }

    func secretExists(for reference: KeychainSecretReference) throws -> Bool {
        lock.withLock { values[reference] != nil }
    }

    func deleteSecret(for reference: KeychainSecretReference) throws {
        lock.withLock { _ = values.removeValue(forKey: reference) }
    }
}

private final class ThrowingPresenceSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _readCount = 0

    var readCount: Int {
        lock.withLock { _readCount }
    }

    func setSecret(_ value: String, for reference: KeychainSecretReference) throws {}

    func readSecret(for reference: KeychainSecretReference) throws -> String? {
        lock.withLock { _readCount += 1 }
        return "ghp_shouldNeverBeRead1234567890"
    }

    func secretExists(for reference: KeychainSecretReference) throws -> Bool {
        throw SecretStoreError.keychainStatus(operation: "lookup", status: -25308)
    }

    func deleteSecret(for reference: KeychainSecretReference) throws {}
}
