import Foundation
import GRDB
import WalletContext

public struct MAccountSettings: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var cardBackgroundNft: ApiNft?
    public var accentColorNft: ApiNft?
    public var accentColorIndex: Int?
    public var isAllowSuspiciousActions: Bool?
    public var portfolioTimeRange: String?
    public var dismissedHomeBannerIds: [String]?

    public init(
        accountId: String,
        cardBackgroundNft: ApiNft?,
        accentColorNft: ApiNft?,
        accentColorIndex: Int?,
        isAllowSuspiciousActions: Bool?,
        portfolioTimeRange: String?,
        dismissedHomeBannerIds: [String]? = nil
    ) {
        self.accountId = accountId
        self.cardBackgroundNft = cardBackgroundNft
        self.accentColorNft = accentColorNft
        self.accentColorIndex = accentColorIndex
        self.isAllowSuspiciousActions = isAllowSuspiciousActions
        self.portfolioTimeRange = portfolioTimeRange
        self.dismissedHomeBannerIds = dismissedHomeBannerIds
    }

    public init(accountId: String, settingsDict: [String: Any]) {
        self.init(
            accountId: accountId,
            cardBackgroundNft: settingsDict["cardBackgroundNft"].flatMap { try? JSONSerialization.decode(ApiNft.self, from: $0) },
            accentColorNft: settingsDict["accentColorNft"].flatMap { try? JSONSerialization.decode(ApiNft.self, from: $0) },
            accentColorIndex: settingsDict["accentColorIndex"] as? Int,
            isAllowSuspiciousActions: settingsDict["isAllowSuspiciousActions"] as? Bool,
            portfolioTimeRange: nil,
            dismissedHomeBannerIds: settingsDict["dismissedHomeBannerIds"] as? [String]
        )
    }

    public static let databaseTableName: String = "account_settings"
}

extension MAccountSettings {
    public var hasData: Bool {
        cardBackgroundNft != nil
            || accentColorNft != nil
            || accentColorIndex != nil
            || isAllowSuspiciousActions != nil
            || portfolioTimeRange != nil
            || dismissedHomeBannerIds?.isEmpty == false
    }
}
