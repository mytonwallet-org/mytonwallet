//
//  AppStorageHelper.swift
//  WalletContext
//
//  Created by Sina on 6/30/24.
//

import Foundation
import NativeEnclave
import UIKit
import WalletContext
import WalletCoreTypes

public enum AppStorageHelper {
    private static var settingsStore: SettingsStore { SettingsStore.liveValue }
    private static let landscapeModeKey = "settings.isLandscapeModeEnabled"

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

    public static var hideUnverifiedNfts: Bool {
        get {
            settingsStore.areUnverifiedNftsHidden
        }
        set {
            guard settingsStore.areUnverifiedNftsHidden != newValue else { return }
            settingsStore.setAreUnverifiedNftsHidden(newValue)
            WalletCoreData.notify(event: .hideUnverifiedNftsChanged)
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

    public static var useLocalizedTokenNames: Bool {
        get {
            settingsStore.useLocalizedTokenNames
        }
        set {
            guard settingsStore.useLocalizedTokenNames != newValue else { return }
            settingsStore.setUseLocalizedTokenNames(newValue)
            WalletCoreData.notify(event: .tokensChanged)
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

    public static var isTokenInfoExpanded: Bool {
        get {
            settingsStore.isTokenInfoExpanded
        }
        set {
            settingsStore.setIsTokenInfoExpanded(newValue)
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

    // MARK: - Auth types & biometrics

    private static let authTypesKey = "authTypes"
    private static let legacyBiometricKindKey = "settings.authConfig.kind"

    public static func save(isBiometricActivated: Bool) {
        settingsStore.setIsBiometricActivated(isBiometricActivated)
    }

    public static func isLegacyBiometricActivated() -> Bool {
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

    public static func needsEnclaveMigration() -> Bool {
        AuthSupportLegacy.needsMigration()
    }

    public static func isEnclaveBiometricActivated() -> Bool {
        EnclaveManager.configuredAuthTypes().contains(.biometric)
    }

    public static func isAnyBiometricActivated() -> Bool {
        isEnclaveBiometricActivated() || isLegacyBiometricActivated()
    }

    public static func isBiometricActivated() -> Bool {
        isAnyBiometricActivated()
    }

    public static func removeLegacyBiometricActivation() {
        settingsStore.setIsBiometricActivated(false)
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

    // MARK: - Wallet settings
    
    public static var walletSettingsListLayout: String {
        get {
            settingsStore.walletSettingsListLayout ?? ""
        }
        set {
            settingsStore.setWalletSettingsListLayout(newValue)
        }
    }

    public static var walletSettingsCurrentFilter: String {
        get {
            settingsStore.walletSettingsCurrentFilter ?? ""
        }
        set {
            settingsStore.setWalletSettingsCurrentFilter(newValue)
        }
    }

    public static var walletSettingsFilterOrder: [String] {
        get {
            settingsStore.walletSettingsFilterOrder
        }
        set {
            settingsStore.setWalletSettingsFilterOrder(newValue)
        }
    }

    public static var appTabOrder: [String] {
        get {
            settingsStore.appTabOrder
        }
        set {
            settingsStore.setAppTabOrder(newValue)
        }
    }

    // MARK: - Orientation

    public static var isLandscapeModeEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: landscapeModeKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: landscapeModeKey)
        }
    }
}
