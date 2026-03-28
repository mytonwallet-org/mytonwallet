import Foundation
import WalletContext

private let log = Log("SupportDiagnostics")

@MainActor
public enum SupportDiagnostics {
    public static let supportURL = URL(string: "https://t.me/\(SUPPORT_USERNAME)")!

    public static func prepareLogsExportFile() async throws -> URL {
        captureCurrentState()
        LogStore.shared.syncronize()
        return try await LogStore.shared.exportFile()
    }

    private static func captureCurrentState() {
        log.info("support diagnostics export requested")
        logKeychainState()
        logAccountState()
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
}
