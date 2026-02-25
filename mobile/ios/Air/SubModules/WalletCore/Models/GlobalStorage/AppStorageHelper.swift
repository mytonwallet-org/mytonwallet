//
//  AppStorageHelper.swift
//  WalletContext
//
//  Created by Sina on 6/30/24.
//

import Foundation
import UIKit
import WalletContext

private let log = Log("AppStorageHelper")

public enum AppStorageHelper {

    public static func reset() {}

    public static func remove(accountId: String) {
        GlobalStorage.remove(keys: [
            "accounts.byId.\(accountId)",
            "byAccountId.\(accountId)",
            "settings.byAccountId.\(accountId)",
        ], persistInstantly: true)
    }

    public static func deleteAllWallets() {
        GlobalStorage.setEmptyObjects(keys: [
            "accounts.byId",
            "byAccountId",
            "settings.byAccountId",
        ], persistInstantly: true)
    }

    // Active night mode
    private static let activeNightModeKey = "settings.theme"
    public static var activeNightMode: NightMode {
        get {
            return NightMode(rawValue: GlobalStorage.getString(key: activeNightModeKey) ?? "") ?? .system
        }
        set {
            GlobalStorage.set(key: activeNightModeKey, value: "\(newValue)", persistInstantly: false)
        }
    }

    // Animations activated or not
    private static let animationsKey = "settings.animationLevel"
    public static var animations: Bool {
        get {
            return (GlobalStorage.getInt(key: animationsKey) ?? 2) > 0
        }
        set {
            UIView.setAnimationsEnabled(newValue)
            GlobalStorage.set(key: animationsKey, value: newValue ? 2 : 0, persistInstantly: false)
        }
    }

    private static let seasonalThemingDisabledKey = "settings.isSeasonalThemingDisabled"
    public static var isSeasonalThemingDisabled: Bool {
        get {
            return GlobalStorage.getBool(key: seasonalThemingDisabledKey) ?? false
        }
        set {
            GlobalStorage.set(
                key: seasonalThemingDisabledKey,
                value: newValue ? true : nil,
                persistInstantly: false
            )
            WalletCoreData.notify(event: .configChanged)
        }
    }

    // Sounds activated or not
    private static let soundsKey = "settings.canPlaySounds"
    public static var sounds: Bool {
        get {
            return GlobalStorage.getBool(key: soundsKey) ?? true
        }
        set {
            GlobalStorage.set(key: soundsKey, value: newValue, persistInstantly: false)
        }
    }

    // Hide tiny transfers or not
    private static let hideTinyTransfersKey = "settings.areTinyTransfersHidden"
    public static var hideTinyTransfers: Bool {
        get {
            return GlobalStorage.getBool(key: hideTinyTransfersKey) ?? true
        }
        set {
            GlobalStorage.set(key: hideTinyTransfersKey, value: newValue, persistInstantly: false)
        }
    }

    // Hide tiny transfers or not
    private static let hideNoCostTokensKey = "settings.areTokensWithNoCostHidden"
    public static var hideNoCostTokens: Bool {
        get {
            return GlobalStorage.getBool(key: hideNoCostTokensKey) ?? true
        }
        set {
            GlobalStorage.set(key: hideNoCostTokensKey, value: newValue, persistInstantly: false)
            WalletCoreData.notify(event: .hideNoCostTokensChanged)
        }
    }

    // Is chart view expanded
    private static let isTokenChartExpandedKey = "settings.isTokenChartExpanded"
    public static var isTokenChartExpanded: Bool {
        get {
            return GlobalStorage.getBool(key: isTokenChartExpandedKey) ?? false
        }
        set {
            GlobalStorage.set(key: isTokenChartExpandedKey, value: newValue, persistInstantly: false)
        }
    }

    // MARK: - Selected currency

    public static let selectedCurrencyKey = "settings.baseCurrency"
    public static func save(selectedCurrency: String?) {
        GlobalStorage.set(key: selectedCurrencyKey, value: selectedCurrency, persistInstantly: true)
    }

    public static func selectedCurrency() -> String {
        return GlobalStorage["selectedCurrencyKey"] as? String ?? "USD"
    }

    private static let selectedExplorerIdsKey = "settings.selectedExplorerIds"
    public static func selectedExplorerId(for chain: ApiChain) -> String? {
        guard let dict = GlobalStorage.getDict(key: selectedExplorerIdsKey) else { return nil }
        return dict[chain.rawValue] as? String
    }

    public static func save(selectedExplorerId: String, for chain: ApiChain) {
        var dict = GlobalStorage.getDict(key: selectedExplorerIdsKey) ?? [:]
        dict[chain.rawValue] = selectedExplorerId
        GlobalStorage.set(key: selectedExplorerIdsKey, value: dict, persistInstantly: true)
    }

    // MARK: - Current Token Time Period

    public static func save(currentTokenPeriod: String) {
        guard let activeAccountId = AccountStore.accountId else {
            return
        }
        GlobalStorage.set(key: "byAccountId.\(activeAccountId).currentTokenPeriod", value: currentTokenPeriod, persistInstantly: false)
    }

    public static func selectedCurrentTokenPeriod() -> String {
        guard let activeAccountId = AccountStore.accountId else {
            return "1D"
        }
        return GlobalStorage.getString(key: "byAccountId.\(activeAccountId).currentTokenPeriod") ?? "1D"
    }

    // MARK: - Account AssetsAndActivity data

    private static var assetsAndActivityDataKey = "settings.byAccountId"
    public static func save(accountId: String, assetsAndActivityData: [String: Any]) {
        let assetsDataKeyPrefix = "\(assetsAndActivityDataKey).\(accountId)"
        assetsAndActivityData.forEach { dictKey, value in
            let storageKey = "\(assetsDataKeyPrefix).\(dictKey)"
            GlobalStorage.set(key: storageKey, value: value, persistInstantly: false)
        }
    }

    public static func assetsAndActivityData(for accountId: String) -> [String: Any]? {
        guard let jsonDictionary = GlobalStorage.getDict(key: "\(assetsAndActivityDataKey).\(accountId)") else {
            return nil
        }
        return jsonDictionary
    }

    // MARK: - Is biometric auth enabled

    private static let isBiometricActivatedKey = "settings.authConfig.kind"
    private enum AuthKind: String {
        case password
        case nativeBiometrics = "native-biometrics"
    }

    public static func save(isBiometricActivated: Bool) {
        let kind: AuthKind = isBiometricActivated ? .nativeBiometrics : .password
        GlobalStorage.set(key: isBiometricActivatedKey, value: kind.rawValue, persistInstantly: true)
    }

    public static func isBiometricActivated() -> Bool {
        GlobalStorage.getString(key: isBiometricActivatedKey) == AuthKind.nativeBiometrics.rawValue
    }

    // MARK: - Sensitive data

    private static let isSensitiveDataHiddenKey = "settings.isSensitiveDataHidden"
    public static var isSensitiveDataHidden: Bool {
        get {
            GlobalStorage[isSensitiveDataHiddenKey] as? Bool ?? false
        }
        set {
            GlobalStorage.update { $0[isSensitiveDataHiddenKey] = newValue }
        }
    }

    // MARK: - Push notifications

    private static let pushNotificationsKey = "pushNotifications"
    public static var pushNotifications: GlobalPushNotifications? {
        get {
            if let any = GlobalStorage[pushNotificationsKey], let value = try? JSONSerialization.decode(GlobalPushNotifications.self, from: any) {
                return value
            }
            return nil
        }
        set {
            do {
                if let newValue {
                    let any = try JSONSerialization.encode(newValue)
                    GlobalStorage.update { $0[pushNotificationsKey] = any }
                }
            } catch {
                assertionFailure("\(error)")
            }
        }
    }
}
