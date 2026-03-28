import Foundation
import GRDB
import WalletContext

public struct MAccountSettings: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var cardBackgroundNft: ApiNft?
    public var accentColorNft: ApiNft?
    public var accentColorIndex: Int?
    public var isAllowSuspiciousActions: Bool?

    public init(
        accountId: String,
        cardBackgroundNft: ApiNft?,
        accentColorNft: ApiNft?,
        accentColorIndex: Int?,
        isAllowSuspiciousActions: Bool?
    ) {
        self.accountId = accountId
        self.cardBackgroundNft = cardBackgroundNft
        self.accentColorNft = accentColorNft
        self.accentColorIndex = accentColorIndex
        self.isAllowSuspiciousActions = isAllowSuspiciousActions
    }

    public init(accountId: String, settingsDict: [String: Any]) {
        self.init(
            accountId: accountId,
            cardBackgroundNft: settingsDict["cardBackgroundNft"].flatMap { try? JSONSerialization.decode(ApiNft.self, from: $0) },
            accentColorNft: settingsDict["accentColorNft"].flatMap { try? JSONSerialization.decode(ApiNft.self, from: $0) },
            accentColorIndex: settingsDict["accentColorIndex"] as? Int,
            isAllowSuspiciousActions: settingsDict["isAllowSuspiciousActions"] as? Bool
        )
    }

    public static let databaseTableName: String = "account_settings"
}

extension MAccountSettings {
    public var hasData: Bool {
        cardBackgroundNft != nil || accentColorNft != nil || accentColorIndex != nil || isAllowSuspiciousActions != nil
    }
}
