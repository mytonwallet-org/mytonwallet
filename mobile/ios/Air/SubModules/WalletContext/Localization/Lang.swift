//
//  Lang.swift
//  WalletContext
//
//  Created by nikstar on 10.08.2025.
//

import Foundation
import SwiftUI

private enum MessageScopedLocalization {
    @TaskLocal static var languageCode: String?
}

public func lang(_ keyAndDefault: String) -> String {
    NSLocalizedString(
        keyAndDefault,
        bundle: localizedBundle(languageCode: MessageScopedLocalization.languageCode),
        comment: ""
    )
}

public func withMessageLanguage<T>(
    _ languageCode: String?,
    operation: () throws -> T
) rethrows -> T {
    try MessageScopedLocalization.$languageCode.withValue(
        supportedMessageLanguageCode(languageCode),
        operation: operation
    )
}

public func supportedMessageLanguageCode(_ languageCode: String?) -> String? {
    guard let languageCode else { return nil }
    return Language.supportedLanguages.first(where: {
        $0.langCode.caseInsensitiveCompare(languageCode) == .orderedSame
    })?.langCode
}

public func langFormat(_ keyAndDefault: String, _ arguments: CVarArg...) -> String {
    let languageCode = MessageScopedLocalization.languageCode
    let locale = languageCode.map(Locale.init(identifier:)) ?? LocalizationSupport.shared.locale
    return String(format: lang(keyAndDefault), locale: locale, arguments: arguments)
}

private func localizedBundle(languageCode: String?) -> Bundle {
    guard let languageCode,
          let localization = AirBundle.localizations.first(where: {
              $0.caseInsensitiveCompare(languageCode) == .orderedSame
          }),
          let path = AirBundle.path(forResource: localization, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return AirBundle }
    return bundle
}

// `$in_days` is a pure plural ("in N days"). `today`/`tomorrow` are handled separately because
// the CLDR `one` plural category (e.g. ru/uk: 1, 21, 31, 61...) cannot isolate exactly 1 day.
public func langRelativeDays(_ days: Int) -> String {
    switch days {
    case 0: return lang("$relative_today")
    case 1: return lang("$relative_tomorrow")
    default: return L10n.inDays(count: days)
    }
}

public func langMd(_ keyAndDefault: String) -> LocalizedStringKey {
    LocalizedStringKey(lang(keyAndDefault))
}

public func attributedLocalizedString(
    attributes: [NSAttributedString.Key: Any]? = nil,
    argument: NSAttributedString,
    localize: (String) -> String
) -> NSAttributedString {
    let uniquePlaceholder = "_9879&^(8980-09-09-423jdhfshfqqweqwe" // a phrase that never happens in real life
    let s = localize(uniquePlaceholder)
    guard let range = s.range(of: uniquePlaceholder) else {
        return NSAttributedString(string: s, attributes: attributes)
    }
    let result = NSMutableAttributedString(string: String(s[..<range.lowerBound]), attributes: attributes)
    result.append(argument)
    result.append(NSAttributedString(string: String(s[range.upperBound...]), attributes: attributes))
    return result
}

public enum EnumerationJoiner {
    case and
    case or
    
    var localizedValue: String {
        switch self {
        case .and:
            lang("$joining_and")
        case .or:
            lang("$joining_or")
        }
    }
}

public func langJoin(_ items: [String], _ joiner: EnumerationJoiner) -> String {
    let middleJoiner = lang("$joining_comma")
    let lastJoiner = joiner.localizedValue

    var result = ""
    for (i, item) in items.enumerated() {
        if i > 0 {
            result += (i == items.count - 1) ? lastJoiner : middleJoiner
        }
        result += item
    }
    return result
}

public func localizedIntegerString(_ value: Int) -> String {
    value.formatted(
        .number
            .grouping(.never)
            .locale(LocalizationSupport.shared.locale)
    )
}

public func localizedIntegerDigits(in text: String) -> String {
    String(text.map { character in
        guard let digit = character.wholeNumberValue, character.isASCII else {
            return character
        }
        return Character(localizedIntegerString(digit))
    })
}
