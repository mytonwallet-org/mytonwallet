//
//  UpdateConfig.swift
//  WalletCore
//
//  Created by nikstar on 11.08.2025.
//

import Foundation

extension ApiUpdate {
    
    public struct UpdateConfig: Equatable, Hashable, Codable, Sendable {
        public enum SeasonalTheme: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
            case newYear = "newYear"
            case valentine = "valentine"
        }

        public enum PreferredAgent: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
            case local
            case online
            case hybrid
        }

        public var type = "updateConfig"
        public var isLimited: Bool?
        public var isCopyStorageEnabled: Bool?
        public var supportAccountsCount: Int?
        public var countryCode: String?
        public var isAppUpdateRequired: Bool?
        public var seasonalTheme: SeasonalTheme?
        public var switchToClassic: Bool?
        public var knowledgeBaseVersion: String?
        public var preferredAgent: PreferredAgent?

        private enum CodingKeys: String, CodingKey {
            case type
            case isLimited
            case isCopyStorageEnabled
            case supportAccountsCount
            case countryCode
            case isAppUpdateRequired
            case seasonalTheme
            case switchToClassic
            case knowledgeBaseVersion
            case preferredAgent
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? "updateConfig"
            isLimited = try container.decodeIfPresent(Bool.self, forKey: .isLimited)
            isCopyStorageEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCopyStorageEnabled)
            supportAccountsCount = try container.decodeIfPresent(Int.self, forKey: .supportAccountsCount)
            countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
            isAppUpdateRequired = try container.decodeIfPresent(Bool.self, forKey: .isAppUpdateRequired)
            switchToClassic = try container.decodeIfPresent(Bool.self, forKey: .switchToClassic)
            seasonalTheme = try? container.decodeIfPresent(SeasonalTheme.self, forKey: .seasonalTheme)
            knowledgeBaseVersion = try? container.decodeIfPresent(String.self, forKey: .knowledgeBaseVersion)
            preferredAgent = try? container.decodeIfPresent(PreferredAgent.self, forKey: .preferredAgent)
        }
    }
}
