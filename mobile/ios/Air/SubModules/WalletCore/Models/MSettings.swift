import Foundation
import GRDB
import WalletContext

private func settingsJsonString(from object: Any?) -> String? {
    guard let object else { return nil }
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

public struct MSettings: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let defaultCurrentTokenPeriod = "1D"
    public static let defaultWalletTokensLimit = HomeWalletVisibleTokensLimit.defaultValue.rawValue

    public let id: Int64
    public var theme: String
    public var areAnimationsDisabled: Bool
    public var isSeasonalThemingDisabled: Bool
    public var canPlaySounds: Bool
    public var areTinyTransfersHidden: Bool
    public var areTokensWithNoCostHidden: Bool
    public var authConfig: String?
    public var autolockValue: String
    public var isSensitiveDataHidden: Bool
    public var selectedExplorerIds: [String: String]
    public var isTokenChartExpanded: Bool
    public var pushNotifications: GlobalPushNotifications?
    // Air intentionally keeps token period shared across accounts.
    public var currentTokenPeriod: String
    public var walletTokensLimit: Int

    public init(
        id: Int64 = SINGLETON_TABLE_ROW_ID,
        theme: String = NightMode.system.rawValue,
        areAnimationsDisabled: Bool = false,
        isSeasonalThemingDisabled: Bool = false,
        canPlaySounds: Bool = true,
        areTinyTransfersHidden: Bool = true,
        areTokensWithNoCostHidden: Bool = true,
        authConfig: String? = nil,
        autolockValue: String = DEFAULT_AUTOLOCK_OPTION.rawValue,
        isSensitiveDataHidden: Bool = false,
        selectedExplorerIds: [String: String] = [:],
        isTokenChartExpanded: Bool = false,
        pushNotifications: GlobalPushNotifications? = nil,
        currentTokenPeriod: String = defaultCurrentTokenPeriod,
        walletTokensLimit: Int = defaultWalletTokensLimit
    ) {
        self.id = id
        self.theme = theme
        self.areAnimationsDisabled = areAnimationsDisabled
        self.isSeasonalThemingDisabled = isSeasonalThemingDisabled
        self.canPlaySounds = canPlaySounds
        self.areTinyTransfersHidden = areTinyTransfersHidden
        self.areTokensWithNoCostHidden = areTokensWithNoCostHidden
        self.authConfig = authConfig
        self.autolockValue = autolockValue
        self.isSensitiveDataHidden = isSensitiveDataHidden
        self.selectedExplorerIds = selectedExplorerIds
        self.isTokenChartExpanded = isTokenChartExpanded
        self.pushNotifications = pushNotifications
        self.currentTokenPeriod = currentTokenPeriod
        self.walletTokensLimit = HomeWalletVisibleTokensLimit(storedValue: walletTokensLimit).rawValue
    }

    @MainActor public init(global: GlobalStorage, currentAccountId: String? = nil) {
        self.init(
            theme: global.getString(key: "settings.theme") ?? NightMode.system.rawValue,
            areAnimationsDisabled: (global.getInt(key: "settings.animationLevel") ?? 2) <= 0,
            isSeasonalThemingDisabled: global.getBool(key: "settings.isSeasonalThemingDisabled") ?? false,
            canPlaySounds: global.getBool(key: "settings.canPlaySounds") ?? true,
            areTinyTransfersHidden: global.getBool(key: "settings.areTinyTransfersHidden") ?? true,
            areTokensWithNoCostHidden: global.getBool(key: "settings.areTokensWithNoCostHidden") ?? true,
            authConfig: settingsJsonString(from: global["settings.authConfig"]),
            autolockValue: MSettings.autolockValue(from: global),
            isSensitiveDataHidden: global["settings.isSensitiveDataHidden"] as? Bool ?? false,
            selectedExplorerIds: global.getDict(key: "settings.selectedExplorerIds")
                .flatMap { try? JSONSerialization.decode([String: String].self, from: $0) } ?? [:],
            isTokenChartExpanded: global.getBool(key: "settings.isTokenChartExpanded") ?? false,
            pushNotifications: global["pushNotifications"]
                .flatMap { try? JSONSerialization.decode(GlobalPushNotifications.self, from: $0) },
            currentTokenPeriod: MSettings.currentTokenPeriod(from: global, currentAccountId: currentAccountId),
            walletTokensLimit: MSettings.defaultWalletTokensLimit
        )
    }

    public static let databaseTableName: String = "settings"
}

public extension MSettings {
    var authConfigKind: String? {
        guard
            let authConfig,
            let data = authConfig.data(using: .utf8),
            let value = try? JSONDecoder().decode(AnyCodable.self, from: data),
            let dictionary = value.dictionaryValue
        else {
            return nil
        }
        return dictionary["kind"]?.stringValue
    }

    var authConfigObject: Any? {
        guard let authConfig else { return nil }
        return try? JSONSerialization.jsonObject(withString: authConfig)
    }

    var pushNotificationsObject: Any? {
        guard let pushNotifications else { return nil }
        return try? JSONSerialization.encode(pushNotifications)
    }

    var globalAnimationLevel: Int {
        areAnimationsDisabled ? 0 : 2
    }

    @MainActor private static func autolockValue(from global: GlobalStorage) -> String {
        if global.getBool(key: "settings.isAppLockEnabled") == false {
            return MAutolockOption.never.rawValue
        }
        return global.getString(key: "settings.autolockValue") ?? DEFAULT_AUTOLOCK_OPTION.rawValue
    }

    @MainActor private static func currentTokenPeriod(from global: GlobalStorage, currentAccountId: String?) -> String {
        let candidateAccountIds =
            [currentAccountId].compactMap { $0 }
            + (global["settings.orderedAccountIds"] as? [String] ?? [])
            + (global.keysIn(key: "byAccountId") ?? [])

        var seenAccountIds = Set<String>()
        for accountId in candidateAccountIds where seenAccountIds.insert(accountId).inserted {
            if let currentTokenPeriod = global.getString(key: "byAccountId.\(accountId).currentTokenPeriod") {
                return currentTokenPeriod
            }
        }

        return defaultCurrentTokenPeriod
    }
}
