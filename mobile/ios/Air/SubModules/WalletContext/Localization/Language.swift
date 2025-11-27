//
//  Language.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.08.2025.
//


public struct Language: Equatable, Identifiable {
    public let langCode: String
    public let name: String
    public let nativeName: String
    public let isRtl: Bool
    
    public var id: String { langCode }
    
    public static let en = Language(
        langCode: "en",
        name: "English",
        nativeName: "English",
        isRtl: false
    )

    public static let es = Language(
        langCode: "es",
        name: "Spanish",
        nativeName: "Español",
        isRtl: false
    )

    public static let ru = Language(
        langCode: "ru",
        name: "Russian",
        nativeName: "Русский",
        isRtl: false
    )

    public static let zhHans = Language(
        langCode: "zh-Hans",
        name: "Chinese (Simplified)",
        nativeName: "简体",
        isRtl: false
    )

    public static let zhHant = Language(
        langCode: "zh-Hant",
        name: "Chinese (Traditional)",
        nativeName: "繁體",
        isRtl: false
    )

    public static let tr = Language(
        langCode: "tr",
        name: "Turkish",
        nativeName: "Türkçe",
        isRtl: false
    )

    public static let de = Language(
        langCode: "de",
        name: "German",
        nativeName: "Deutsch",
        isRtl: false
    )

    public static let th = Language(
        langCode: "th",
        name: "Thai",
        nativeName: "ไทย",
        isRtl: false
    )

    public static let uk = Language(
        langCode: "uk",
        name: "Ukrainian",
        nativeName: "Українська",
        isRtl: false
    )

    public static let pl = Language(
        langCode: "pl",
        name: "Polish",
        nativeName: "Polski",
        isRtl: false
    )

    public static let ar = Language(
        langCode: "ar",
        name: "Arabic",
        nativeName: "العربية",
        isRtl: true
    )

    public static let fa = Language(
        langCode: "fa",
        name: "Persian",
        nativeName: "فارسی",
        isRtl: true
    )
    
    public static let allCases: [Language] = [
        .en,
        .es,
        .ru,
        .zhHans,
        .zhHant,
        .tr,
        .de,
        .th,
        .uk,
        .pl,
        .ar,
        .fa
    ]
    
    public static let supportedLanguages: [Language] = [
        .en,
        .es,
        .ru,
        .zhHans,
        .zhHant,
        .tr,
        .de,
        .th,
        .uk,
        .pl,
    ]
}
