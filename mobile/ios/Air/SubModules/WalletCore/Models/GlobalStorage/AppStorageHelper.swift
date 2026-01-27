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


public struct AppStorageHelper {

    public static func reset() {
    }

    public static func remove(accountId: String) {
        GlobalStorage.remove(keys: [
            "accounts.byId.\(accountId)",
            "byAccountId.\(accountId)",
            "settings.byAccountId.\(accountId)"
        ], persistInstantly: true)
    }
    public static func deleteAllWallets() {
        GlobalStorage.setEmptyObjects(keys: [
            "accounts.byId",
            "byAccountId",
            "settings.byAccountId"
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
    public static func save(accountId: String, assetsAndActivityData: [String: Any]?) {
        let key = "\(assetsAndActivityDataKey).\(accountId)"
        if let assetsAndActivityData {
            GlobalStorage.set(key: "\(key).alwaysShownSlugs",
                                       value: assetsAndActivityData["alwaysShownSlugs"],
                                       persistInstantly: false)
            GlobalStorage.set(key: "\(key).alwaysHiddenSlugs",
                                       value: assetsAndActivityData["alwaysHiddenSlugs"],
                                       persistInstantly: false)
            GlobalStorage.set(key: "\(key).deletedSlugs",
                                       value: assetsAndActivityData["deletedSlugs"],
                                       persistInstantly: false)
            GlobalStorage.set(key: "\(key).importedSlugs",
                                       value: assetsAndActivityData["importedSlugs"],
                                        persistInstantly: false)
        } else {
            GlobalStorage.setEmptyObject(key: "\(key).alwaysShownSlugs", persistInstantly: false)
            GlobalStorage.setEmptyObject(key: "\(key).alwaysHiddenSlugs", persistInstantly: false)
            GlobalStorage.setEmptyObject(key: "\(key).deletedSlugs", persistInstantly: false)
            GlobalStorage.set(key: "\(key).importedSlugs",
                                       value: ["toncoin", TON_USDT_SLUG, "trx", TRON_USDT_SLUG],
                                       persistInstantly: false)

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
