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
    private static var settingsStore: SettingsStore { SettingsStore.liveValue }

    public static func reset() {}

    // Active night mode
    public static var activeNightMode: NightMode {
        get {
            settingsStore.theme
        }
        set {
            settingsStore.setTheme(newValue)
        }
    }

    // Animations activated or not
    @MainActor public static var animations: Bool {
        get {
            !settingsStore.areAnimationsDisabled
        }
        set {
            UIView.setAnimationsEnabled(newValue)
            settingsStore.setAreAnimationsDisabled(!newValue)
        }
    }

    public static var isSeasonalThemingDisabled: Bool {
        get {
            settingsStore.isSeasonalThemingDisabled
        }
        set {
            settingsStore.setIsSeasonalThemingDisabled(newValue)
            WalletCoreData.notify(event: .configChanged)
        }
    }

    // Sounds activated or not
    public static var sounds: Bool {
        get {
            settingsStore.canPlaySounds
        }
        set {
            settingsStore.setCanPlaySounds(newValue)
        }
    }

    // Hide tiny transfers or not
    public static var hideTinyTransfers: Bool {
        get {
            settingsStore.areTinyTransfersHidden
        }
        set {
            settingsStore.setAreTinyTransfersHidden(newValue)
        }
    }

    // Hide tiny transfers or not
    public static var hideNoCostTokens: Bool {
        get {
            settingsStore.areTokensWithNoCostHidden
        }
        set {
            settingsStore.setAreTokensWithNoCostHidden(newValue)
            WalletCoreData.notify(event: .hideNoCostTokensChanged)
        }
    }

    // Is chart view expanded
    public static var isTokenChartExpanded: Bool {
        get {
            settingsStore.isTokenChartExpanded
        }
        set {
            settingsStore.setIsTokenChartExpanded(newValue)
        }
    }

    // MARK: - Selected currency

    public static let selectedCurrencyKey = "settings.baseCurrency"
    public static func save(selectedCurrency: String?) {
        UserDefaults.standard.set(selectedCurrency, forKey: selectedCurrencyKey)
    }

    public static func selectedCurrency() -> String {
        UserDefaults.standard.string(forKey: selectedCurrencyKey) ?? "USD"
    }

    public static func selectedExplorerId(for chain: ApiChain) -> String? {
        settingsStore.selectedExplorerId(for: chain)
    }

    public static func save(selectedExplorerId: String, for chain: ApiChain) {
        settingsStore.setSelectedExplorerId(selectedExplorerId, for: chain)
    }

    // MARK: - Current Token Time Period

    public static func save(currentTokenPeriod: String) {
        settingsStore.setCurrentTokenPeriod(currentTokenPeriod)
    }

    public static func selectedCurrentTokenPeriod() -> String {
        settingsStore.currentTokenPeriod
    }

    public static var homeWalletVisibleTokensLimit: HomeWalletVisibleTokensLimit {
        get {
            settingsStore.homeWalletVisibleTokensLimit
        }
        set {
            guard settingsStore.homeWalletVisibleTokensLimit != newValue else { return }
            settingsStore.setHomeWalletVisibleTokensLimit(newValue)
            WalletCoreData.notify(event: .homeWalletVisibleTokensLimitChanged)
        }
    }

    // MARK: - Is biometric auth enabled

    public static func save(isBiometricActivated: Bool) {
        settingsStore.setIsBiometricActivated(isBiometricActivated)
    }

    public static func isBiometricActivated() -> Bool {
        settingsStore.isBiometricActivated
    }

    public static var autolockOption: MAutolockOption {
        get {
            settingsStore.autolockOption
        }
        set {
            settingsStore.setAutolockOption(newValue)
        }
    }

    // MARK: - Sensitive data

    public static var isSensitiveDataHidden: Bool {
        get {
            settingsStore.isSensitiveDataHidden
        }
        set {
            settingsStore.setIsSensitiveDataHidden(newValue)
        }
    }

    // MARK: - Push notifications

    public static var pushNotifications: GlobalPushNotifications? {
        get {
            settingsStore.pushNotifications
        }
        set {
            settingsStore.setPushNotifications(newValue)
        }
    }
}
