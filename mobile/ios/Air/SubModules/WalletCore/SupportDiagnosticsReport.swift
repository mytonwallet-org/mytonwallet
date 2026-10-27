import Foundation
import NativeEnclave
import UIKit
import WalletContext

struct SupportDiagnosticsReport: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let app: AppInfo
    let device: DeviceInfo
    let installation: InstallationInfo
    let accounts: AccountsInfo
    let security: SecurityInfo
    let walletRecovery: WalletRecoveryDiagnostics?

    @MainActor
    static func collect() async -> SupportDiagnosticsReport {
        let generatedAt = Date()
        let accountsById: [String: MAccount] = AccountStore.accountsById
        let currentAccountId = AccountStore.accountId
        let databaseAccountIds = Set(accountsById.keys)
        let orderedAccountIds = Array(AccountStore.orderedAccountIds)
        let storedEncryptedAccountIds = Set(
            accountsById.values
                .filter { $0.type.isStoredEncrypted }
                .map(\.id)
        )
        let appInfo = makeAppInfo()
        var deviceInfo = makeDeviceInfo()
        let installationContext = makeInstallationContext()
        let databasePath = installationContext.databasePath
        let storageTask = Task.detached(priority: .userInitiated) {
            collectStorageInspection(databasePath: databasePath)
        }
        let storageInspection = await storageTask.value
        deviceInfo.availableStorageBytes = storageInspection.availableStorageBytes
        deviceInfo.totalStorageBytes = storageInspection.totalStorageBytes

        let keychainInspection = storageInspection.keychainAccounts
        let configuredAuthTypes = storageInspection.configuredAuthTypes
        var inspectionErrors = keychainInspection.error.map { ["keychainAccounts": $0] } ?? [:]
        var enclaveSecretAccountIds: Set<String>?

        if !configuredAuthTypes.isEmpty {
            do {
                enclaveSecretAccountIds = try await EnclaveManager.shared.existingSecretIds(
                    in: storedEncryptedAccountIds
                )
            } catch {
                inspectionErrors["enclaveSecrets"] = String(reflecting: error)
            }
        }

        let missingEnclaveSecretAccountIds = enclaveSecretAccountIds.map {
            storedEncryptedAccountIds.subtracting($0)
        }
        let accountSummaries = makeAccountSummaries(
            accountsById: accountsById,
            currentAccountId: currentAccountId,
            orderedAccountIds: orderedAccountIds,
            keychainInspection: keychainInspection,
            configuredAuthTypes: configuredAuthTypes,
            enclaveSecretAccountIds: enclaveSecretAccountIds
        )
        let accountHealth = makeOverallAccountHealth(
            summaries: accountSummaries,
            hasInspectionErrors: !inspectionErrors.isEmpty
        )
        let keychainAccountIds = keychainInspection.accountIds

        return SupportDiagnosticsReport(
            schemaVersion: 1,
            generatedAt: generatedAt,
            app: appInfo,
            device: deviceInfo,
            installation: makeInstallationInfo(
                generatedAt: generatedAt,
                context: installationContext,
                storage: storageInspection.installation
            ),
            accounts: AccountsInfo(
                currentAccountId: currentAccountId,
                orderedAccountIds: orderedAccountIds,
                databaseAccountIds: databaseAccountIds.sorted(),
                keychainAccountIds: keychainAccountIds?.sorted(),
                keychainOnlyAccountIds: keychainAccountIds.map { $0.subtracting(databaseAccountIds).sorted() },
                databaseOnlyAccountIds: keychainAccountIds.map { databaseAccountIds.subtracting($0).sorted() },
                health: accountHealth,
                items: accountSummaries
            ),
            security: SecurityInfo(
                credentials: storageInspection.credentials,
                configuredAuthTypes: configuredAuthTypes.map(\.rawValue).sorted(),
                isLegacyMigrationAllowed: storageInspection.isLegacyMigrationAllowed,
                legacyCiphertextAccountIds: keychainInspection.legacyCiphertextAccountIds.sorted(),
                malformedLegacySecretAccountIds: keychainInspection.malformedLegacySecretAccountIds.sorted(),
                enclaveSecretAccountIds: enclaveSecretAccountIds?.sorted(),
                missingEnclaveSecretAccountIds: missingEnclaveSecretAccountIds?.sorted(),
                inspectionErrors: inspectionErrors
            ),
            walletRecovery: await WalletRecoveryDiagnostics.collect(
                accounts: Array(accountsById.values),
                isLegacyMigrationAllowed: storageInspection.isLegacyMigrationAllowed,
                enclaveSecretAccountIds: enclaveSecretAccountIds
            )
        )
    }
}

extension SupportDiagnosticsReport {
    struct AppInfo: Encodable {
        let name: String
        let bundleIdentifier: String
        let version: String
        let build: String
        let distribution: String
        let isTestFlight: Bool
        let isDebugBuild: Bool
        let isDebugProductionModeEnabled: Bool
    }

    struct DeviceInfo: Encodable {
        let hardwareModel: String
        let deviceFamily: String
        let systemName: String
        let systemVersion: String
        let operatingSystemVersion: String
        let userInterfaceIdiom: String
        let isSimulator: Bool
        let localeIdentifier: String
        let preferredLanguages: [String]
        let timeZone: String
        let physicalMemoryBytes: UInt64
        var availableStorageBytes: Int64?
        var totalStorageBytes: Int64?
        let isLowPowerModeEnabled: Bool
        let thermalState: String
        let screen: ScreenInfo?
    }

    struct ScreenInfo: Encodable {
        let nativeWidthPixels: Int
        let nativeHeightPixels: Int
        let scale: Double
        let maximumFramesPerSecond: Int
    }

    struct InstallationInfo: Encodable {
        let firstLaunchAt: Date?
        let firstLaunchVersion: String?
        let lastLaunchAt: Date?
        let lastLaunchVersion: String?
        let processStartedAt: Date
        let processUptimeSeconds: Double
        let protectedDataAvailable: Bool
        let clientId: String?
        let stateVersion: String?
        let keychainCurrentAccountId: String?
        let baseCurrency: String?
        let keychainKeys: [String]
        let databaseReady: Bool
        let databaseFileExists: Bool
        let databaseSizeBytes: Int64?
    }

    struct AccountsInfo: Encodable {
        let currentAccountId: String?
        let orderedAccountIds: [String]
        let databaseAccountIds: [String]
        let keychainAccountIds: [String]?
        let keychainOnlyAccountIds: [String]?
        let databaseOnlyAccountIds: [String]?
        let health: HealthInfo
        let items: [AccountInfo]
    }

    struct AccountInfo: Encodable {
        let id: String
        let type: String?
        let chains: [String]
        let isTemporary: Bool?
        let isCurrent: Bool
        let orderIndex: Int?
        let existsInDatabase: Bool
        let existsInKeychain: Bool?
        let legacySecretState: String
        let enclaveSecretState: String
        let health: HealthInfo
    }

    struct HealthInfo: Encodable {
        let status: String
        let issues: [String]
    }

    struct SecurityInfo: Encodable {
        let credentials: CredentialsInfo
        let configuredAuthTypes: [String]
        let isLegacyMigrationAllowed: Bool
        let legacyCiphertextAccountIds: [String]
        let malformedLegacySecretAccountIds: [String]
        let enclaveSecretAccountIds: [String]?
        let missingEnclaveSecretAccountIds: [String]?
        let inspectionErrors: [String: String]
    }

    struct CredentialsInfo: Encodable, Sendable {
        let state: String
        let hasUsername: Bool?
        let passwordLength: Int?
        let hasValidPasscodeFormat: Bool?
        let error: String?
    }
}

private extension SupportDiagnosticsReport {
    struct InstallationContext: Sendable {
        let firstLaunchAt: Date?
        let firstLaunchVersion: String?
        let lastLaunchAt: Date?
        let lastLaunchVersion: String?
        let protectedDataAvailable: Bool
        let databaseReady: Bool
        let databasePath: String
    }

    struct InstallationStorageInfo: Sendable {
        let clientId: String?
        let stateVersion: String?
        let keychainCurrentAccountId: String?
        let baseCurrency: String?
        let keychainKeys: [String]
        let databaseFileExists: Bool
        let databaseSizeBytes: Int64?
    }

    struct StorageInspection: Sendable {
        let keychainAccounts: KeychainAccountsInspection
        let credentials: CredentialsInfo
        let configuredAuthTypes: Set<AuthType>
        let isLegacyMigrationAllowed: Bool
        let installation: InstallationStorageInfo
        let availableStorageBytes: Int64?
        let totalStorageBytes: Int64?
    }

    struct KeychainAccountsInspection: Sendable {
        let accountIds: Set<String>?
        let legacyCiphertextAccountIds: Set<String>
        let malformedLegacySecretAccountIds: Set<String>
        let error: String?
    }

    static func makeAppInfo() -> AppInfo {
        let bundle = Bundle.main
        let isTestFlight = isTestFlightBuild
        let distribution: String
        if isSimulatorBuild {
            distribution = "simulator"
        } else if isDebugBuild {
            distribution = "debug"
        } else if isTestFlight {
            distribution = "testFlight"
        } else {
            distribution = "appStore"
        }

        return AppInfo(
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? APP_NAME,
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            distribution: distribution,
            isTestFlight: isTestFlight,
            isDebugBuild: isDebugBuild,
            isDebugProductionModeEnabled: DebugProductionMode.isEnabled
        )
    }

    @MainActor
    static func makeDeviceInfo() -> DeviceInfo {
        let processInfo = ProcessInfo.processInfo
        let device = UIDevice.current
        let screen = UIApplication.shared.anySceneKeyWindow?.windowScene?.screen
            ?? UIApplication.shared.connectedWindowScene?.screen
        let screenInfo = screen.map {
            ScreenInfo(
                nativeWidthPixels: Int($0.nativeBounds.width),
                nativeHeightPixels: Int($0.nativeBounds.height),
                scale: Double($0.nativeScale),
                maximumFramesPerSecond: $0.maximumFramesPerSecond
            )
        }

        return DeviceInfo(
            hardwareModel: hardwareModel,
            deviceFamily: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            operatingSystemVersion: processInfo.operatingSystemVersionString,
            userInterfaceIdiom: userInterfaceIdiom(device.userInterfaceIdiom),
            isSimulator: isSimulatorBuild,
            localeIdentifier: Locale.autoupdatingCurrent.identifier,
            preferredLanguages: Locale.preferredLanguages,
            timeZone: TimeZone.autoupdatingCurrent.identifier,
            physicalMemoryBytes: processInfo.physicalMemory,
            availableStorageBytes: nil,
            totalStorageBytes: nil,
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            thermalState: thermalState(processInfo.thermalState),
            screen: screenInfo
        )
    }

    @MainActor
    static func makeInstallationContext() -> InstallationContext {
        let defaults = UserDefaults.standard
        return InstallationContext(
            firstLaunchAt: defaults.object(forKey: "firstLaunchDate") as? Date,
            firstLaunchVersion: defaults.string(forKey: "firstLaunchVersion"),
            lastLaunchAt: defaults.object(forKey: "lastLaunchDate") as? Date,
            lastLaunchVersion: defaults.string(forKey: "lastLaunchVersion"),
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            databaseReady: db != nil,
            databasePath: dbUrl.path(percentEncoded: false)
        )
    }

    static func makeInstallationInfo(
        generatedAt: Date,
        context: InstallationContext,
        storage: InstallationStorageInfo
    ) -> InstallationInfo {
        return InstallationInfo(
            firstLaunchAt: context.firstLaunchAt,
            firstLaunchVersion: context.firstLaunchVersion,
            lastLaunchAt: context.lastLaunchAt,
            lastLaunchVersion: context.lastLaunchVersion,
            processStartedAt: appStart,
            processUptimeSeconds: max(0, generatedAt.timeIntervalSince(appStart)),
            protectedDataAvailable: context.protectedDataAvailable,
            clientId: storage.clientId,
            stateVersion: storage.stateVersion,
            keychainCurrentAccountId: storage.keychainCurrentAccountId,
            baseCurrency: storage.baseCurrency,
            keychainKeys: storage.keychainKeys,
            databaseReady: context.databaseReady,
            databaseFileExists: storage.databaseFileExists,
            databaseSizeBytes: storage.databaseSizeBytes
        )
    }

    static func collectStorageInspection(databasePath: String) -> StorageInspection {
        let fileManager = FileManager.default
        let databaseAttributes = try? fileManager.attributesOfItem(atPath: databasePath)
        let databaseSize = (databaseAttributes?[.size] as? NSNumber)?.int64Value
        let storage = try? URL.documentsDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ])
        let availableStorage = storage?.volumeAvailableCapacityForImportantUsage
            ?? storage?.volumeAvailableCapacity.map { Int64($0) }

        return StorageInspection(
            keychainAccounts: inspectKeychainAccounts(),
            credentials: inspectCredentials(),
            configuredAuthTypes: EnclaveManager.configuredAuthTypes(),
            isLegacyMigrationAllowed: EnclaveManager.isLegacyMigrationAllowed(),
            installation: InstallationStorageInfo(
                clientId: KeychainStorageProvider.get(key: "clientId").1,
                stateVersion: KeychainStorageProvider.get(key: "stateVersion").1,
                keychainCurrentAccountId: KeychainStorageProvider.get(key: "currentAccountId").1,
                baseCurrency: KeychainStorageProvider.get(key: "baseCurrency").1,
                keychainKeys: KeychainStorageProvider.keys().sorted(),
                databaseFileExists: fileManager.fileExists(atPath: databasePath),
                databaseSizeBytes: databaseSize
            ),
            availableStorageBytes: availableStorage,
            totalStorageBytes: storage?.volumeTotalCapacity.map { Int64($0) }
        )
    }

    static func inspectCredentials() -> CredentialsInfo {
        do {
            guard let credentials = try CapacitorCredentialsStorage.loadCredentials() else {
                return CredentialsInfo(
                    state: "missing",
                    hasUsername: false,
                    passwordLength: nil,
                    hasValidPasscodeFormat: nil,
                    error: nil
                )
            }
            let isValid = credentials.password.wholeMatch(of: /[0-9]{4}/) != nil
                || credentials.password.wholeMatch(of: /[0-9]{6}/) != nil
            return CredentialsInfo(
                state: "present",
                hasUsername: !credentials.username.isEmpty,
                passwordLength: credentials.password.count,
                hasValidPasscodeFormat: isValid,
                error: nil
            )
        } catch {
            return CredentialsInfo(
                state: "unreadable",
                hasUsername: nil,
                passwordLength: nil,
                hasValidPasscodeFormat: nil,
                error: String(reflecting: error)
            )
        }
    }

    static func inspectKeychainAccounts() -> KeychainAccountsInspection {
        do {
            let accounts = try KeychainHelper.loadAccounts() ?? [:]
            var legacyCiphertextAccountIds = Set<String>()
            var malformedLegacySecretAccountIds = Set<String>()
            for (accountId, account) in accounts {
                guard account.keys.contains("mnemonicEncrypted") else {
                    continue
                }
                if let ciphertext = account["mnemonicEncrypted"] as? String, !ciphertext.isEmpty {
                    legacyCiphertextAccountIds.insert(accountId)
                } else {
                    malformedLegacySecretAccountIds.insert(accountId)
                }
            }
            return KeychainAccountsInspection(
                accountIds: Set(accounts.keys),
                legacyCiphertextAccountIds: legacyCiphertextAccountIds,
                malformedLegacySecretAccountIds: malformedLegacySecretAccountIds,
                error: nil
            )
        } catch {
            return KeychainAccountsInspection(
                accountIds: nil,
                legacyCiphertextAccountIds: [],
                malformedLegacySecretAccountIds: [],
                error: String(reflecting: error)
            )
        }
    }

    static func makeAccountSummaries(
        accountsById: [String: MAccount],
        currentAccountId: String?,
        orderedAccountIds: [String],
        keychainInspection: KeychainAccountsInspection,
        configuredAuthTypes: Set<AuthType>,
        enclaveSecretAccountIds: Set<String>?
    ) -> [AccountInfo] {
        let keychainAccountIds = keychainInspection.accountIds ?? []
        var allAccountIds = Set(accountsById.keys)
            .union(keychainAccountIds)
            .union(orderedAccountIds)
        if let currentAccountId {
            allAccountIds.insert(currentAccountId)
        }
        let orderByAccountId = Dictionary(uniqueKeysWithValues: orderedAccountIds.enumerated().map { ($1, $0) })

        return allAccountIds.sorted().map { accountId in
            let account = accountsById[accountId]
            var issues: [String] = []

            if account == nil && (currentAccountId == accountId || orderByAccountId[accountId] != nil) {
                issues.append("missingDatabaseRecord")
            }
            if let account, account.isTemporary != true, orderByAccountId[accountId] == nil {
                issues.append("missingFromAccountOrder")
            }
            if currentAccountId == accountId && orderByAccountId[accountId] == nil {
                issues.append("currentAccountMissingFromOrder")
            }
            if account?.secretState?.isRecoveryRequired == true {
                issues.append("secretRecoveryRequired")
            }
            if keychainInspection.malformedLegacySecretAccountIds.contains(accountId) {
                issues.append("malformedLegacySecret")
            }
            if account?.type.isStoredEncrypted == true,
               !configuredAuthTypes.isEmpty,
               let enclaveSecretAccountIds,
               !enclaveSecretAccountIds.contains(accountId) {
                issues.append("missingEnclaveSecret")
            }

            return AccountInfo(
                id: accountId,
                type: account?.type.rawValue,
                chains: account?.byChain.keys.sorted() ?? [],
                isTemporary: account?.isTemporary,
                isCurrent: currentAccountId == accountId,
                orderIndex: orderByAccountId[accountId],
                existsInDatabase: account != nil,
                existsInKeychain: keychainInspection.accountIds.map { $0.contains(accountId) },
                legacySecretState: legacySecretState(accountId: accountId, inspection: keychainInspection),
                enclaveSecretState: enclaveSecretState(
                    account: account,
                    configuredAuthTypes: configuredAuthTypes,
                    enclaveSecretAccountIds: enclaveSecretAccountIds
                ),
                health: HealthInfo(
                    status: account == nil && issues.isEmpty ? "legacyOnly" : (issues.isEmpty ? "healthy" : "needsAttention"),
                    issues: issues
                )
            )
        }
    }

    static func makeOverallAccountHealth(
        summaries: [AccountInfo],
        hasInspectionErrors: Bool
    ) -> HealthInfo {
        var issueSet = Set(summaries.flatMap(\.health.issues))
        if hasInspectionErrors {
            issueSet.insert("inspectionIncomplete")
        }
        let issues = issueSet.sorted()
        let status: String
        if hasInspectionErrors {
            status = "unknown"
        } else if !issues.isEmpty {
            status = "needsAttention"
        } else {
            status = "healthy"
        }
        return HealthInfo(status: status, issues: issues)
    }

    static func legacySecretState(
        accountId: String,
        inspection: KeychainAccountsInspection
    ) -> String {
        guard let accountIds = inspection.accountIds else {
            return "unknown"
        }
        guard accountIds.contains(accountId) else {
            return "accountNotInKeychain"
        }
        guard inspection.legacyCiphertextAccountIds.contains(accountId)
                || inspection.malformedLegacySecretAccountIds.contains(accountId) else {
            return "absent"
        }
        return inspection.legacyCiphertextAccountIds.contains(accountId) ? "present" : "malformed"
    }

    static func enclaveSecretState(
        account: MAccount?,
        configuredAuthTypes: Set<AuthType>,
        enclaveSecretAccountIds: Set<String>?
    ) -> String {
        guard let account, account.type.isStoredEncrypted else {
            return "notApplicable"
        }
        guard !configuredAuthTypes.isEmpty else {
            return "notConfigured"
        }
        guard let enclaveSecretAccountIds else {
            return "unknown"
        }
        return enclaveSecretAccountIds.contains(account.id) ? "present" : "missing"
    }

    static var hardwareModel: String {
        #if targetEnvironment(simulator)
        if let simulatedModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatedModel
        }
        #endif
        var systemInfo = utsname()
        _ = uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var isTestFlightBuild: Bool {
        !isDebugBuild
            && !isSimulatorBuild
            && Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func userInterfaceIdiom(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone:
            "phone"
        case .pad:
            "pad"
        case .tv:
            "tv"
        case .carPlay:
            "carPlay"
        case .mac:
            "mac"
        case .vision:
            "vision"
        case .unspecified:
            "unspecified"
        @unknown default:
            "unknown"
        }
    }

    static func thermalState(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }
}
