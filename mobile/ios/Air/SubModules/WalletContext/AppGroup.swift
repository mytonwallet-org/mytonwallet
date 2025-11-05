//
//  AppGroup.swift
//  WalletCore
//
//  Created by nikstar on 23.09.2025.
//

import Foundation

public let APP_GROUP_ID = "group.org.mytonwallet.app"
/// Optional when building without extensions. Can be force-unwrapped when accessed from widgets.
public let appGroupContainerUrl: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)

public extension UserDefaults {
    static let appGroup: UserDefaults? = UserDefaults(suiteName: APP_GROUP_ID)
}
