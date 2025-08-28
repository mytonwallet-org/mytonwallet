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
