#if DEBUG && targetEnvironment(simulator)

import Foundation
import WalletContext
import WalletCoreTypes

private let log = Log("WalletsExport")

@MainActor
public enum AppWalletsExport {
    public static let environmentVariable = "IMPORT_WALLETS_PATH"
    public static let environmentPinVariable = "IMPORT_WALLETS_PIN"
    public static let defaultPin = "2222"

    public struct ExportResult: Sendable {
        public let fileURL: URL
        public let walletCount: Int
    }

    public enum ExportError: LocalizedError {
        case notRunningOnSimulator
        case databaseNotReady
        case walletsMissing
        case passcodeRequired
        case desktopUnavailable
        case writeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .notRunningOnSimulator:
                return "Wallet dump is available on Simulator only."
            case .databaseNotReady:
                return "Database is not ready."
            case .walletsMissing:
                return "No wallets found."
            case .passcodeRequired:
                return "Passcode is required to export mnemonic wallets."
            case .desktopUnavailable:
                return "Desktop/MyWalletDumps folder is not available."
            case .writeFailed(let error):
                return "Failed to write dump file: \(error.localizedDescription)"
            }
        }
    }

    public enum ImportError: LocalizedError {
        case notRunningOnSimulator
        case dumpNotFound(String)
        case invalidDump(String)
        case restoreFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .notRunningOnSimulator:
                return "Wallet import is available on Simulator only."
            case .dumpNotFound(let path):
                return "Wallets import file was not found at \(path)."
            case .invalidDump(let reason):
                return "Invalid wallets import file: \(reason)"
            case .restoreFailed(let error):
                return "Failed to import wallets: \(error.localizedDescription)"
            }
        }
    }

    private struct NativeSnapshot: Sendable {
        let accounts: [MAccount]
        let orderedAccountIds: [String]?
    }

    private struct WalletDumpPayload: Codable, Sendable {
        let exportedAt: Date
        let wallets: [WalletDumpWallet]
    }

    private struct WalletDumpWallet: Codable, Sendable {
        let name: String
        let type: AccountType
        let mnemonic: [String]?
        let addressByChain: [String: String]?

        func validated() throws -> WalletDumpWallet {
            guard !name.isEmpty else {
                throw ImportError.invalidDump("wallet name is missing")
            }

            switch type {
            case .mnemonic:
                guard let mnemonic, !mnemonic.isEmpty else {
                    throw ImportError.invalidDump("mnemonic wallet \(name) is missing mnemonic words")
                }
            case .view:
                guard let addressByChain, !addressByChain.isEmpty else {
                    throw ImportError.invalidDump("view wallet \(name) is missing addressByChain")
                }
            case .hardware:
                break
            }

            return self
        }
    }

    private static let dumpJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let dumpJSONDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func runStartupImportIfConfigured() async -> Error? {
        guard isRunningOnSimulator else { return nil }
        guard let importPath = importPathFromEnvironment else { return nil }

        let fileURL = URL(fileURLWithPath: importPath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ImportError.dumpNotFound(importPath)
        }

        do {
            try await importFromFile(fileURL: fileURL)
            return nil
        } catch {
            return error
        }
    }

    private static var importPathFromEnvironment: String? {
        guard let rawValue = ProcessInfo.processInfo.environment[environmentVariable] else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func hasDecryptableMnemonicAccounts() -> Bool {
        guard let database = db else { return false }
        return (try? database.read { db in
            try MAccount.fetchAll(db).contains { $0.type == .mnemonic }
        }) ?? false
    }

    public static func export(passcode: String?) async throws -> ExportResult {
        guard isRunningOnSimulator else {
            throw ExportError.notRunningOnSimulator
        }

        let native = try await readNativeSnapshot()
        guard !native.accounts.isEmpty else {
            throw ExportError.walletsMissing
        }

        let hasMnemonicWallets = native.accounts.contains { $0.type == .mnemonic }
        if hasMnemonicWallets {
            guard let passcode, !passcode.isEmpty else {
                throw ExportError.passcodeRequired
            }
        }

        let orderedAccounts = orderedAccounts(from: native)
        var wallets: [WalletDumpWallet] = []
        wallets.reserveCapacity(orderedAccounts.count)

        for account in orderedAccounts {
            wallets.append(try await buildWalletExportEntry(account: account, passcode: passcode))
        }

        let payload = WalletDumpPayload(
            exportedAt: Date(),
            wallets: wallets
        )

        let fileURL = try writePayloadToDumpDirectory(payload)
        log.info("exported to=\(fileURL.path, .public) wallets=\(wallets.count)")
        return ExportResult(fileURL: fileURL, walletCount: wallets.count)
    }

    public static func importFromFile(fileURL: URL) async throws {
        log.info("importing from \(fileURL.path, .public)")

        guard isRunningOnSimulator else {
            throw ImportError.notRunningOnSimulator
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ImportError.dumpNotFound(fileURL.path)
        }

        let data = try Data(contentsOf: fileURL)
        let payload: WalletDumpPayload
        do {
            payload = try dumpJSONDecoder.decode(WalletDumpPayload.self, from: data)
        } catch {
            throw ImportError.invalidDump(error.localizedDescription)
        }

        let wallets = try payload.wallets.map { try $0.validated() }
        guard !wallets.isEmpty else {
            throw ImportError.invalidDump("no wallet entries found")
        }

        try await importWalletDump(wallets)
    }

    private static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func readNativeSnapshot() async throws -> NativeSnapshot {
        guard let database = db else {
            throw ExportError.databaseNotReady
        }

        return try await database.read { db in
            NativeSnapshot(
                accounts: try MAccount.fetchAll(db),
                orderedAccountIds: try MOrderedAccountIds.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)?.orderedAccountIds
            )
        }
    }

    private static func orderedAccounts(from native: NativeSnapshot) -> [MAccount] {
        let accountsById = Dictionary(uniqueKeysWithValues: native.accounts.map { ($0.id, $0) })
        if let orderedAccountIds = native.orderedAccountIds, !orderedAccountIds.isEmpty {
            let ordered = orderedAccountIds.compactMap { accountsById[$0] }
            if !ordered.isEmpty {
                return ordered
            }
        }
        return native.accounts
    }

    private static func buildWalletExportEntry(account: MAccount, passcode: String?) async throws -> WalletDumpWallet {
        let name = account.title?.nilIfEmpty ?? account.id

        switch account.type {
        case .mnemonic:
            guard let passcode, !passcode.isEmpty else {
                throw ExportError.passcodeRequired
            }
            return WalletDumpWallet(
                name: name,
                type: .mnemonic,
                mnemonic: try await Api.fetchMnemonic(accountId: account.id, password: passcode),
                addressByChain: nil
            )
        case .view, .hardware:
            let addressByChain = Dictionary(uniqueKeysWithValues: account.byChain.map { ($0.key, $0.value.address) })
            return WalletDumpWallet(
                name: name,
                type: account.type,
                mnemonic: nil,
                addressByChain: addressByChain.isEmpty ? nil : addressByChain
            )
        }
    }

    private static func importWalletDump(_ wallets: [WalletDumpWallet]) async throws {
        let needsPasscode = wallets.contains { $0.type == .mnemonic }
        let passcode = needsPasscode ? resolveImportPasscode() : nil

        let walletsToImport = await filterNewWallets(wallets, passcode: passcode)
        guard !walletsToImport.isEmpty else {
            log.info("import skipped: all wallets already exist")
            return
        }

        for wallet in walletsToImport {
            do {
                switch wallet.type {
                case .mnemonic:
                    guard let passcode, !passcode.isEmpty else {
                        throw ImportError.invalidDump("passcode is required to import mnemonic wallets")
                    }
                    let imported = try await AccountStore.importMnemonic(
                        network: .mainnet,
                        words: wallet.mnemonic ?? [],
                        passcode: passcode,
                        version: nil
                    )
                    if let accountId = imported.first?.id {
                        try await AccountStore.updateAccountTitle(accountId: accountId, newTitle: wallet.name)
                    }
                case .view:
                    guard let addressByChain = wallet.addressByChain else {
                        throw ImportError.invalidDump("view wallet \(wallet.name) is missing addressByChain")
                    }
                    let account = try await AccountStore.importViewWallet(network: .mainnet, addressByChain: addressByChain)
                    try await AccountStore.updateAccountTitle(accountId: account.id, newTitle: wallet.name)
                case .hardware:
                    log.info("skipping hardware wallet in dump name=\(wallet.name, .public)")
                }
            } catch let error as ImportError {
                throw error
            } catch {
                throw ImportError.restoreFailed(error)
            }
        }

        log.info("wallet dump imported wallets=\(walletsToImport.count, .public) skipped=\(wallets.count - walletsToImport.count, .public)")
    }

    private static func resolveImportPasscode() -> String {
        let savedPasscode = KeychainHelper.biometricPasscode()
        if !savedPasscode.isEmpty {
            return savedPasscode
        }

        let envPin = ProcessInfo.processInfo.environment[environmentPinVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let passcode = envPin ?? defaultPin
        KeychainHelper.save(biometricPasscode: passcode)
        return passcode
    }

    private static func filterNewWallets(_ wallets: [WalletDumpWallet], passcode: String?) async -> [WalletDumpWallet] {
        let existingAccounts = AccountStore.orderedAccounts
        let mnemonicByAccountId = await existingMnemonicSets(passcode: passcode, accounts: existingAccounts)

        return wallets.filter { wallet in
            !isExistingWallet(wallet, among: existingAccounts, mnemonicByAccountId: mnemonicByAccountId)
        }
    }

    private static func existingMnemonicSets(passcode: String?, accounts: [MAccount]) async -> [String: Set<String>] {
        guard let passcode else { return [:] }

        var mnemonicByAccountId: [String: Set<String>] = [:]
        for account in accounts where account.type == .mnemonic {
            if let words = try? await Api.fetchMnemonic(accountId: account.id, password: passcode) {
                mnemonicByAccountId[account.id] = Set(words)
            }
        }
        return mnemonicByAccountId
    }

    private static func isExistingWallet(
        _ wallet: WalletDumpWallet,
        among accounts: [MAccount],
        mnemonicByAccountId: [String: Set<String>]
    ) -> Bool {
        switch wallet.type {
        case .mnemonic:
            guard let mnemonic = wallet.mnemonic else { return true }
            let walletMnemonic = Set(mnemonic)
            return accounts.contains { account in
                account.type == .mnemonic
                    && accountDisplayName(account) == wallet.name
                    && mnemonicByAccountId[account.id] == walletMnemonic
            }
        case .view:
            guard let addressByChain = wallet.addressByChain else { return true }
            return accounts.contains { account in
                account.type == .view
                    && accountDisplayName(account) == wallet.name
                    && accountAddressByChain(from: account) == addressByChain
            }
        case .hardware:
            return true
        }
    }

    private static func accountDisplayName(_ account: MAccount) -> String {
        account.title?.nilIfEmpty ?? account.id
    }

    private static func accountAddressByChain(from account: MAccount) -> [String: String] {
        Dictionary(uniqueKeysWithValues: account.byChain.map { ($0.key, $0.value.address) })
    }

    private static func writePayloadToDumpDirectory(_ payload: WalletDumpPayload) throws -> URL {
        let dumpDirectory = try dumpDirectoryURL(createIfNeeded: true)
        let fileURL = nextAvailableDumpFileURL(in: dumpDirectory)

        do {
            let data = try dumpJSONEncoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    static let dumpFilePrefix = "MyWalletDump"
    static let dumpDirectoryName = "MyWalletDumps"

    private static func nextAvailableDumpFileURL(in dumpDirectory: URL) -> URL {
        let fileManager = FileManager.default
        var index = 1
        while true {
            let fileURL = dumpDirectory.appendingPathComponent("\(dumpFilePrefix)\(index).json")
            if !fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            index += 1
        }
    }

    private static func dumpDirectoryURL(createIfNeeded: Bool) throws -> URL {
        let desktopURL = try simulatorDesktopDirectoryURL()
        let dumpDirectory = desktopURL.appendingPathComponent(dumpDirectoryName, isDirectory: true)

        if createIfNeeded {
            try FileManager.default.createDirectory(at: dumpDirectory, withIntermediateDirectories: true)
        }

        return dumpDirectory
    }

    private static func simulatorDesktopDirectoryURL() throws -> URL {
        guard let homeURL = simulatorHostHomeDirectoryURL() else {
            throw ExportError.desktopUnavailable
        }

        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: desktopURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ExportError.desktopUnavailable
        }
        return desktopURL
    }

    private static func simulatorHostHomeDirectoryURL() -> URL? {
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
           !hostHome.isEmpty {
            return URL(fileURLWithPath: hostHome, isDirectory: true)
        }

        if let passwd = getpwuid(getuid()) {
            let path = String(cString: passwd.pointee.pw_dir)
            if path.hasPrefix("/Users/"), !path.contains("CoreSimulator") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        return nil
    }
}

#endif
