//
//  Lang.swift
//  WalletContext
//
//  Created by nikstar on 10.08.2025.
//

import Foundation
import SwiftUI

public func lang(_ keyAndDefault: String) -> String {
    NSLocalizedString(keyAndDefault, bundle: AirBundle, comment: "")
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg) -> String {
    formatLocalizedString(lang(keyAndDefault), arguments: [arg1])
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg, arg2: any CVarArg) -> String {
    formatLocalizedString(lang(keyAndDefault), arguments: [arg1, arg2])
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg, arg2: any CVarArg, arg3: any CVarArg) -> String {
    formatLocalizedString(lang(keyAndDefault), arguments: [arg1, arg2, arg3])
}

// `$in_days` is a pure plural ("in N days"). `today`/`tomorrow` are handled separately because
// the CLDR `one` plural category (e.g. ru/uk: 1, 21, 31, 61...) cannot isolate exactly 1 day.
public func langRelativeDays(_ days: Int) -> String {
    switch days {
    case 0: return lang("$relative_today")
    case 1: return lang("$relative_tomorrow")
    default: return lang("$in_days", arg1: days)
    }
}

public func langMd(_ keyAndDefault: String) -> LocalizedStringKey {
    LocalizedStringKey(lang(keyAndDefault))
}
public func langMd(_ keyAndDefault: String, arg1: any CVarArg) -> LocalizedStringKey {
    LocalizedStringKey(formatLocalizedString(lang(keyAndDefault), arguments: [arg1]))
}

public func attributedLang(_ keyAndDefault: String, attributes: [NSAttributedString.Key : Any]? = nil, arg1: NSAttributedString) -> NSAttributedString {
    let uniquePlaceholder = "_9879&^(8980-09-09-423jdhfshfqqweqwe" // a phrase that never happens in real life
    let s = lang(keyAndDefault, arg1: uniquePlaceholder)
    guard let range = s.range(of: uniquePlaceholder) else {
        return NSAttributedString(string: s, attributes: attributes)
    }
    let result = NSMutableAttributedString(string: String(s[..<range.lowerBound]), attributes: attributes)
    result.append(arg1)
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
    formatLocalizedString("%d", arguments: [value])
}

public func localizedIntegerDigits(in text: String) -> String {
    String(text.map { character in
        guard let digit = character.wholeNumberValue, character.isASCII else {
            return character
        }
        return Character(localizedIntegerString(digit))
    })
}

public func formatLocalizedString(_ format: String, arguments: [any CVarArg]) -> String {
    if arguments.contains(where: isIntegerFormatArgument) {
        return String(format: format, locale: LocalizationSupport.shared.locale, arguments: arguments)
    }
    return String(format: format, arguments: arguments)
}

private func isIntegerFormatArgument(_ argument: any CVarArg) -> Bool {
    switch argument {
    case is Int, is Int8, is Int16, is Int32, is Int64:
        true
    case is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
        true
    default:
        false
    }
}
