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
    private static let legacyLangCodeStorageKey = "settings.langCode"
    private static let legacySelectedLanguageCodeKey = "selectedLanguageCode"
    private static let legacyNativeLanguageMigrationKey = "settings.langMigrationToUserDefaultsCompleted"
    private static let appleLanguagesStorageKey = "AppleLanguages"
    private static let appleTextDirectionStorageKey = "AppleTextDirection"
    private static let forceRightToLeftStorageKey = "NSForceRightToLeftWritingDirection"
    
    init() {
        Self.clearLegacyLanguageOverrides()
    }
    
    public var langCode: String {
        LocalizationSupport.preferredSupportedLanguageCode() ?? Language.en.langCode
    }
    
    public var isChinese: Bool {
        langCode.hasPrefix("zh")
    }

    public var isRightToLeft: Bool {
        Language.current.isRtl
    }

    public var locale: Locale {
        Locale(identifier: langCode == Language.ar.langCode ? "ar@numbers=arab" : langCode)
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

    static func clearLegacyLanguageOverrides() {
        for defaults in userDefaultsStores {
            let legacyLanguageCode = defaults.string(forKey: legacyLangCodeStorageKey)
                ?? defaults.string(forKey: legacySelectedLanguageCodeKey)
            let appleLanguages = defaults.array(forKey: appleLanguagesStorageKey) as? [String]
            if let legacyLanguageCode, appleLanguages?.first == legacyLanguageCode {
                defaults.removeObject(forKey: appleLanguagesStorageKey)
            }
            defaults.removeObject(forKey: legacyLangCodeStorageKey)
            defaults.removeObject(forKey: legacySelectedLanguageCodeKey)
            defaults.removeObject(forKey: legacyNativeLanguageMigrationKey)
            defaults.removeObject(forKey: appleTextDirectionStorageKey)
            defaults.removeObject(forKey: forceRightToLeftStorageKey)
            defaults.synchronize()
        }
    }

    static func preferredSupportedLanguageCode() -> String? {
        for identifier in AirBundle.preferredLocalizations {
            if let normalized = normalizePreferredLanguageIdentifier(identifier),
               supportedLanguageCodes.contains(normalized) {
                return normalized
            }
        }

        let preferredLocalizations = Bundle.preferredLocalizations(
            from: Language.supportedLanguages.map(\.langCode)
        )
        for identifier in preferredLocalizations {
            if let normalized = normalizePreferredLanguageIdentifier(identifier),
               supportedLanguageCodes.contains(normalized) {
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
