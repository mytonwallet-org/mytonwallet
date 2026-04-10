//
//  Lang.swift
//  WalletContext
//
//  Created by nikstar on 10.08.2025.
//

import Foundation
import SwiftUI

public func lang(_ keyAndDefault: String) -> String {
    NSLocalizedString(keyAndDefault, bundle: LocalizationSupport.shared.bundle, comment: "")
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg) -> String {
    return String(format: lang(keyAndDefault), arg1)
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg, arg2: any CVarArg) -> String {
    return String(format: lang(keyAndDefault), arg1, arg2)
}
public func lang(_ keyAndDefault: String, arg1: any CVarArg, arg2: any CVarArg, arg3: any CVarArg) -> String {
    return String(format: lang(keyAndDefault), arg1, arg2, arg3)
}

public func langMd(_ keyAndDefault: String) -> LocalizedStringKey {
    LocalizedStringKey(lang(keyAndDefault))
}
public func langMd(_ keyAndDefault: String, arg1: any CVarArg) -> LocalizedStringKey {
    LocalizedStringKey(String(format: lang(keyAndDefault), arg1))
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
