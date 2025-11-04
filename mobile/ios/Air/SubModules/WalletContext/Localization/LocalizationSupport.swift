//
//  LocalizationSupport.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.08.2025.
//

import Foundation


public final class LocalizationSupport {
    
    public static let shared = LocalizationSupport()
    
    init() {
        let code = self.langCode
        self.locale = Locale(identifier: code)
        self.bundle = Bundle(path: AirBundle.path(forResource: code, ofType: "lproj")!)!
    }
    
    private let key = "selectedLanguageCode"

    public var langCode: String {
        let fetchedValue: String
        if let lang = UserDefaults.appGroup?.string(forKey: key), !lang.isEmpty {
            fetchedValue = lang
        } else if let lang = UserDefaults.standard.string(forKey: key), !lang.isEmpty {
            UserDefaults.appGroup?.set(lang, forKey: key)
            fetchedValue = lang
        } else {
            fetchedValue = "en"
        }
        if Language.supportedLanguages.map(\.langCode).contains(fetchedValue) {
            return fetchedValue
        } else {
            return "en"
        }
    }
    
    public var locale: Locale!
    public var bundle: Bundle!
    
    @MainActor public func setLanguageCode(_ newValue: String) {
        guard newValue != langCode else { return }
        self.locale = Locale(identifier: newValue)
        self.bundle = Bundle(path: AirBundle.path(forResource: newValue, ofType: "lproj")!)!
        UserDefaults.appGroup?.set(newValue, forKey: key)
        UserDefaults.standard.set(newValue, forKey: key)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
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
