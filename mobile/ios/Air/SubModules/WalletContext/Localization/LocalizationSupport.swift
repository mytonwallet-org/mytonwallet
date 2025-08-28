//
//  LocalizationSupport.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.08.2025.
//

import Foundation

let DEFAULT_TO_LOCALE = false

public final class LocalizationSupport {
    
    public static let shared = LocalizationSupport()
    
    init() {
        let code = self.langCode
        self.locale = Locale(identifier: code)
        self.bundle = Bundle(path: AirBundle.path(forResource: code, ofType: "lproj")!)!
    }
    
    private let key = "selectedLanguageCode"

    public var langCode: String {
        
        if let lang = UserDefaults.standard.string(forKey: key) {
            if Language.supportedLanguages.map(\.langCode).contains(lang) {
                return lang
            } else {
                return "en"
            }
        }
        return DEFAULT_TO_LOCALE ? Locale.current.language.languageCode?.identifier ?? "en" : "en"
    }
    
    public var locale: Locale!
    public var bundle: Bundle!
    
    @MainActor public func setLanguageCode(_ newValue: String) {
        guard newValue != langCode else { return }
        self.locale = Locale(identifier: newValue)
        self.bundle = Bundle(path: AirBundle.path(forResource: newValue, ofType: "lproj")!)!
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
