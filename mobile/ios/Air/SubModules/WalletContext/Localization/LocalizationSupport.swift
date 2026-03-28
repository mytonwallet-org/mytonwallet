//
//  LocalizationSupport.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.08.2025.
//

import Foundation


public final class LocalizationSupport: Sendable {
    
    public static let shared = LocalizationSupport()
    private static let supportedLanguageCodes = Set(Language.supportedLanguages.map(\.langCode))
    private static let langCodeStorageKey = "settings.langCode"
    private static let langSourceStorageKey = "settings.langSource"
    private static let langSourceSystem = "system"
    private static let langSourceUser = "user"
    private static let nativeLanguageMigrationKey = "settings.langMigrationToUserDefaultsCompleted"
    private static let appleLanguagesStorageKey = "AppleLanguages"
    private static let appleTextDirectionStorageKey = "AppleTextDirection"
    private static let forceRightToLeftStorageKey = "NSForceRightToLeftWritingDirection"
    
    init() {
        applyLanguageCode(self.langCode)
    }
    
    public var langCode: String {
        let storedLangCode = LocalizationSupport.storedLanguageCode()
        let resolved = storedLangCode
            ?? LocalizationSupport.preferredSupportedLanguageCode()
            ?? "en"
        return LocalizationSupport.normalizedSupportedLanguageCode(resolved)
    }
    
    public var isChinese: Bool {
        langCode.hasPrefix("zh")
    }

    public var needsLegacyGlobalStorageMigration: Bool {
        !LocalizationSupport.didCompleteNativeLanguageMigration()
    }
    
    private let _locale: UnfairLock<Locale?> = .init(initialState: nil)
    public var locale: Locale {
        get { _locale.withLock { $0! } }
        set { _locale.withLock { $0 = newValue } }
    }
    private let _bundle: UnfairLock<Bundle?> = .init(initialState: nil)
    public var bundle: Bundle {
        get { _bundle.withLock { $0! } }
        set { _bundle.withLock { $0 = newValue } }
    }

    @MainActor public func setLanguageCode(_ newValue: String) {
        let normalized = LocalizationSupport.normalizedSupportedLanguageCode(newValue)
        let isAlreadySelected = LocalizationSupport.storedLanguageCode() == normalized
        guard !isAlreadySelected else { return }

        LocalizationSupport.persistLanguageCode(normalized)
        applyLanguageCode(normalized)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    @MainActor public func migrateLanguageFromGlobalStorageIfNeeded(global: GlobalStorage) {
        guard !LocalizationSupport.didCompleteNativeLanguageMigration() else { return }
        LocalizationSupport.persistLanguageCode(LocalizationSupport.storedLanguageCode(global: global))
        LocalizationSupport.markNativeLanguageMigrationCompleted()
        applyLanguageCode(langCode)
    }

    @MainActor public func syncLanguageFromGlobalStorage(global: GlobalStorage) {
        LocalizationSupport.persistLanguageCode(LocalizationSupport.storedLanguageCode(global: global))
        LocalizationSupport.markNativeLanguageMigrationCompleted()
        applyLanguageCode(langCode)
    }

    @MainActor public func syncLanguageToGlobalStorage(global: GlobalStorage) {
        let storedLanguageCode = LocalizationSupport.storedLanguageCode()
        global.update {
            $0[LocalizationSupport.langCodeStorageKey] = storedLanguageCode
            $0[LocalizationSupport.langSourceStorageKey] = storedLanguageCode == nil
                ? LocalizationSupport.langSourceSystem
                : LocalizationSupport.langSourceUser
        }
    }

    private static func normalizedSupportedLanguageCode(_ code: String) -> String {
        if supportedLanguageCodes.contains(code) {
            return code
        }
        return "en"
    }

    private func applyLanguageCode(_ code: String) {
        self.locale = Locale(identifier: code)
        self.bundle = Bundle(path: AirBundle.path(forResource: code, ofType: "lproj")!)!
    }

}

private extension LocalizationSupport {
    static var userDefaultsStores: [UserDefaults] {
        var stores = [UserDefaults.standard]
        if let appGroup = UserDefaults.appGroup {
            stores.append(appGroup)
        }
        return stores
    }

    static func storedLanguageCode() -> String? {
        for defaults in userDefaultsStores {
            if let code = defaults.string(forKey: langCodeStorageKey)?.nilIfEmpty {
                return normalizedSupportedLanguageCode(code)
            }
        }
        return nil
    }

    @MainActor static func storedLanguageCode(global: GlobalStorage) -> String? {
        guard
            global.getString(key: langSourceStorageKey) == langSourceUser,
            let code = global.getString(key: langCodeStorageKey)?.nilIfEmpty
        else {
            return nil
        }
        return normalizedSupportedLanguageCode(code)
    }

    static func persistLanguageCode(_ code: String?) {
        for defaults in userDefaultsStores {
            if let code {
                defaults.set(code, forKey: langCodeStorageKey)
                defaults.set([code], forKey: appleLanguagesStorageKey)
            } else {
                defaults.removeObject(forKey: langCodeStorageKey)
                defaults.removeObject(forKey: appleLanguagesStorageKey)
                defaults.removeObject(forKey: appleTextDirectionStorageKey)
                defaults.removeObject(forKey: forceRightToLeftStorageKey)
            }
            defaults.synchronize()
        }
    }

    static func didCompleteNativeLanguageMigration() -> Bool {
        userDefaultsStores.contains { $0.bool(forKey: nativeLanguageMigrationKey) }
    }

    static func markNativeLanguageMigrationCompleted() {
        for defaults in userDefaultsStores {
            defaults.set(true, forKey: nativeLanguageMigrationKey)
            defaults.synchronize()
        }
    }

    static func preferredSupportedLanguageCode() -> String? {
        for identifier in Locale.preferredLanguages {
            if supportedLanguageCodes.contains(identifier) {
                return identifier
            }
            if let normalized = normalizePreferredLanguageIdentifier(identifier), supportedLanguageCodes.contains(normalized) {
                return normalized
            }
        }
        return nil
    }
    
    static func normalizePreferredLanguageIdentifier(_ identifier: String) -> String? {
        let components = Locale.Components(identifier: identifier).languageComponents
        let languageCode = components.languageCode?.identifier.lowercased()
        let regionCode = components.region?.identifier.uppercased()
        
        if languageCode == "zh" {
            let scriptCode = components.script?.identifier.lowercased()
            if scriptCode == "hans" {
                return "zh-Hans"
            }
            if scriptCode == "hant" {
                return "zh-Hant"
            }
            if ["HK", "MO", "TW"].contains(regionCode) {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        
        return languageCode
    }
}

extension Language {
    public static var current: Language {
        Language.supportedLanguages.first(id: LocalizationSupport.shared.langCode) ?? .en
    }
}

extension Locale {
    public static let forNumberFormatters: Locale = makeEn()
}

private func makeEn() -> Locale {
    let en = Locale(identifier: "en_US")
//    en.groupingSeparator = " "
    return en
}


extension Notification.Name {
    public static let languageDidChange = Notification.Name("languageDidChange")
}
