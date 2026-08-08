import Foundation
import NativeEnclave
import WalletContext
import ZIPFoundation

private let log = Log("SupportDiagnostics")

@MainActor
public enum SupportDiagnostics {
    public static let supportURL = URL(string: "https://t.me/\(SUPPORT_USERNAME)")!

    public static func prepareLogsExportFile() async throws -> URL {
        await captureCurrentState()
        let sdkLogs = await collectSDKLogs()
        let nativeLogsURL = try await LogStore.shared.exportFile()
        defer { try? FileManager.default.removeItem(at: nativeLogsURL) }

        return try SupportDiagnosticsArchive.create(
            nativeLogsURL: nativeLogsURL,
            sdkLogsData: sdkLogs.data,
            sdkLogsError: sdkLogs.error
        )
    }

    private static func collectSDKLogs() async -> SDKLogsCollection {
        do {
            let logs = try await Api.getLogsIfReady() ?? []
            return SDKLogsCollection(data: try SupportDiagnosticsArchive.encodeSDKLogs(logs), error: nil)
        } catch {
            log.error("failed to collect SDK logs: \(error, .public)")
            return SDKLogsCollection(data: Data("[]\n".utf8), error: String(reflecting: error))
        }
    }

    private static func captureCurrentState() async {
        log.info("support diagnostics export requested")
        logKeychainState()
        logAccountState()
        await logSecretMigrationState()
    }

    private static func logKeychainState() {
        log.info("keychain state:")
        log.info("keys = \(KeychainStorageProvider.keys() as Any, .public)")
        log.info("stateVersion = \(KeychainStorageProvider.get(key: "stateVersion") as Any, .public)")
        log.info("currentAccountId = \(KeychainStorageProvider.get(key: "currentAccountId") as Any, .public)")
        log.info("clientId = \(KeychainStorageProvider.get(key: "clientId") as Any, .public)")
        log.info("baseCurrency = \(KeychainStorageProvider.get(key: "baseCurrency") as Any, .public)")
        let accounts = KeychainStorageProvider.get(key: "accounts")
        var accountIdsInKeychain: [String]?
        if let value = accounts.1, let keys = try? (JSONSerialization.jsonObject(withString: value) as? [String: Any])?.keys {
            accountIdsInKeychain = Array(keys)
        }
        log.info("accounts = \(accounts.0 as Any) length=\(accounts.1?.count ?? -1)")
        log.info("accountIds in keychain = \(accountIdsInKeychain?.jsonString() ?? "<accounts is not a valid dict>", .public)")

        let areCredentialsValid: Bool
        if let credentials = CapacitorCredentialsStorage.getCredentials() {
            log.info("credentials discovered username = \(credentials.username, .public) password.count = \(credentials.password.count)")
            areCredentialsValid = credentials.password.wholeMatch(of: /[0-9]{4}/) != nil || credentials.password.wholeMatch(of: /[0-9]{6}/) != nil
        } else {
            log.info("credentials do not exist")
            areCredentialsValid = false
        }
        log.info("areCredentialsValid = \(areCredentialsValid)")
    }

    private static func logAccountState() {
        log.info("account state:")
        log.info("currentAccountId = \(AccountStore.accountId ?? "<AccountStore.accountId is nil>", .public)")
        let orderedAccountIds = AccountStore.orderedAccountIds
        log.info("orderedAccountIds = #\(orderedAccountIds.count) \(orderedAccountIds.jsonString(), .public)")
        let accountsById = AccountStore.accountsById
        log.info("accountsById = #\(accountsById.count) \(accountsById.jsonString(), .public)")
    }

    private static func logSecretMigrationState() async {
        let accountsById = AccountStore.accountsById
        let databaseAccountIds = Set(accountsById.keys)
        let storedEncryptedAccountIds = Set(
            accountsById.values
                .filter { $0.type.isStoredEncrypted }
                .map(\.id)
        )
        let recoveryRequiredAccountIds = Set(
            accountsById.values
                .filter { $0.type.isStoredEncrypted && $0.secretState?.isRecoveryRequired == true }
                .map(\.id)
        )

        log.info("secret migration state:")
        log.info(
            "database encrypted accounts count=\(storedEncryptedAccountIds.count) ids=\(storedEncryptedAccountIds.sorted(), .public)"
        )
        if recoveryRequiredAccountIds.isEmpty {
            log.info("database recovery-required accounts count=0")
        } else {
            log.fault(
                "database recovery-required accounts count=\(recoveryRequiredAccountIds.count) ids=\(recoveryRequiredAccountIds.sorted(), .public)"
            )
        }

        do {
            let keychainAccounts = try KeychainHelper.loadAccounts() ?? [:]
            let keychainAccountIds = Set(keychainAccounts.keys)
            let legacyCiphertextAccountIds: Set<String> = Set(
                keychainAccounts.compactMap { accountId, account in
                    guard let ciphertext = account["mnemonicEncrypted"] as? String,
                          !ciphertext.isEmpty else {
                        return nil
                    }
                    return accountId
                }
            )
            let malformedLegacySecretAccountIds: Set<String> = Set(
                keychainAccounts.compactMap { accountId, account in
                    guard account.keys.contains("mnemonicEncrypted") else {
                        return nil
                    }
                    if let ciphertext = account["mnemonicEncrypted"] as? String,
                       !ciphertext.isEmpty {
                        return nil
                    }
                    return accountId
                }
            )

            log.info(
                "legacy ciphertext accounts count=\(legacyCiphertextAccountIds.count) ids=\(legacyCiphertextAccountIds.sorted(), .public)"
            )
            if !malformedLegacySecretAccountIds.isEmpty {
                log.fault(
                    "malformed legacy secret fields count=\(malformedLegacySecretAccountIds.count) ids=\(malformedLegacySecretAccountIds.sorted(), .public)"
                )
            }
            let keychainOnlyAccountIds = keychainAccountIds.subtracting(databaseAccountIds)
            let databaseOnlyAccountIds = databaseAccountIds.subtracting(keychainAccountIds)
            log.info(
                "account storage mismatch keychainOnly=\(keychainOnlyAccountIds.sorted(), .public) databaseOnly=\(databaseOnlyAccountIds.sorted(), .public)"
            )
        } catch {
            log.error("failed to inspect legacy keychain accounts for support export: \(error, .public)")
        }

        let configuredAuthTypes = EnclaveManager.configuredAuthTypes()
        log.info(
            "enclave configuredAuthTypes=\(configuredAuthTypes.map(\.rawValue).sorted(), .public) legacyMigrationAllowed=\(EnclaveManager.isLegacyMigrationAllowed())"
        )
        guard !configuredAuthTypes.isEmpty else {
            return
        }

        do {
            let enclaveSecretAccountIds = try await EnclaveManager.shared.existingSecretIds(
                in: storedEncryptedAccountIds
            )
            let missingEnclaveSecretAccountIds = storedEncryptedAccountIds.subtracting(enclaveSecretAccountIds)
            log.info(
                "enclave database-secret coverage present=\(enclaveSecretAccountIds.sorted(), .public) missing=\(missingEnclaveSecretAccountIds.sorted(), .public)"
            )
        } catch {
            log.error("failed to inspect enclave secret coverage for support export: \(error, .public)")
        }
    }
}

private struct SDKLogsCollection {
    let data: Data
    let error: String?
}

struct SupportDiagnosticsArchive {
    static let nativeLogsFilename = "native-logs.tsv"
    static let sdkLogsFilename = "sdk-logs.json"
    static let sdkLogsErrorFilename = "sdk-logs-error.txt"

    static func encodeSDKLogs(_ logs: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(logs) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return try JSONSerialization.data(
            withJSONObject: logs,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data("\n".utf8)
    }

    static func create(
        nativeLogsURL: URL,
        sdkLogsData: Data,
        sdkLogsError: String?,
        destinationDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagingDirectory = fileManager.temporaryDirectory
            .appending(component: "air-logs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        try fileManager.copyItem(
            at: nativeLogsURL,
            to: stagingDirectory.appending(component: nativeLogsFilename)
        )
        try sdkLogsData.write(
            to: stagingDirectory.appending(component: sdkLogsFilename),
            options: .atomic
        )
        if let sdkLogsError {
            try Data("\(sdkLogsError)\n".utf8).write(
                to: stagingDirectory.appending(component: sdkLogsErrorFilename),
                options: .atomic
            )
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let archiveURL = destinationDirectory.appending(component: "air-logs-\(timestamp).zip")
        try fileManager.zipItem(
            at: stagingDirectory,
            to: archiveURL,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
        return archiveURL
    }
}
