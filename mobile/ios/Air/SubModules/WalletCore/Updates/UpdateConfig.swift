//
//  UpdateConfig.swift
//  WalletCore
//
//  Created by nikstar on 11.08.2025.
//

import Foundation

extension ApiUpdate {
    
    public struct UpdateConfig: Equatable, Hashable, Codable, Sendable {
        public var type = "updateConfig"
        public var isLimited: Bool?
        public var isCopyStorageEnabled: Bool?
        public var supportAccountsCount: Int?
        public var countryCode: String?
        public var isAppUpdateRequired: Bool?
        public var switchToClassic: Bool?
    }
}
