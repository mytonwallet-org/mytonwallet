import Foundation
import WalletContext

public struct ApiCardInfo: Equatable, Hashable, Codable, Sendable {
    public var all: Int
    public var notMinted: Int
    public var price: Double
    /// Mint start time as an ISO 8601 UTC date-time string.
    public var startsAt: String? = nil
}

public struct ApiCardsInfo: Equatable, Hashable, Codable, Sendable {
    public var byType: [ApiMtwCardType: ApiCardInfo]

    public init(byType: [ApiMtwCardType: ApiCardInfo] = [:]) {
        self.byType = byType
    }

    public subscript(_ type: ApiMtwCardType) -> ApiCardInfo? {
        byType[type]
    }

    public init(from decoder: Decoder) throws {
        let rawValues = try [String: ApiCardInfo](from: decoder)
        self.byType = rawValues.reduce(into: [:]) { result, item in
            guard let type = ApiMtwCardType(rawValue: item.key) else { return }
            result[type] = item.value
        }
    }

    public func encode(to encoder: Encoder) throws {
        let rawValues = byType.reduce(into: [String: ApiCardInfo]()) { result, item in
            result[item.key.rawValue] = item.value
        }
        try rawValues.encode(to: encoder)
    }
}

public struct ApiAccountConfig: Equatable, Hashable, Codable, Sendable {
    public var cardsInfo: ApiCardsInfo?
    public var activePromotion: ApiPromotion?
    public var isMfaEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case cardsInfo
        case activePromotion
        case isMfaEnabled
    }

    public init(cardsInfo: ApiCardsInfo? = nil, activePromotion: ApiPromotion? = nil, isMfaEnabled: Bool? = nil) {
        self.cardsInfo = cardsInfo
        self.activePromotion = activePromotion
        self.isMfaEnabled = isMfaEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cardsInfo = try? container.decodeIfPresent(ApiCardsInfo.self, forKey: .cardsInfo)
        self.activePromotion = try? container.decodeIfPresent(ApiPromotion.self, forKey: .activePromotion)
        self.isMfaEnabled = try? container.decodeIfPresent(Bool.self, forKey: .isMfaEnabled)
    }
}

public struct ApiPromotion: Equatable, Hashable, Codable, Sendable {
    public enum Kind: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
        case cardOverlay
        case infoBanner
    }

    public struct CardOverlay: Equatable, Hashable, Codable, Sendable {
        public enum OnClickAction: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
            case openPromotionModal
            case openMintCardModal
        }

        public struct MascotIcon: Equatable, Hashable, Codable, Sendable {
            public var url: String
            public var top: CGFloat
            public var right: CGFloat
            public var height: CGFloat
            public var width: CGFloat
            public var rotation: CGFloat
        }

        public var mascotIcon: MascotIcon?
        public var onClickAction: OnClickAction
    }

    public struct Modal: Equatable, Hashable, Codable, Sendable {
        public struct ActionButton: Equatable, Hashable, Codable, Sendable {
            public var title: String
            public var url: String
        }

        public var backgroundImageUrl: String
        public var backgroundFallback: String
        public var heroImageUrl: String?
        public var title: String
        public var titleColor: String?
        public var description: String
        public var descriptionColor: String?
        public var availabilityIndicator: String?
        public var actionButton: ActionButton?
    }

    public struct InfoBanner: Equatable, Hashable, Codable, Sendable {
        public struct ActionButton: Equatable, Hashable, Codable, Sendable {
            public enum OnClickAction: String, Equatable, Hashable, Codable, Sendable {
                case openEarn
            }

            public var title: String
            public var onClickAction: OnClickAction

            public init(title: String, onClickAction: OnClickAction) {
                self.title = title
                self.onClickAction = onClickAction
            }
        }

        public var title: String
        /// Inline Markdown, including emphasis.
        public var description: String
        public var actionButton: ActionButton

        public init(title: String, description: String, actionButton: ActionButton) {
            self.title = title
            self.description = description
            self.actionButton = actionButton
        }
    }

    public let id: String
    public let kind: Kind
    public let cardOverlay: CardOverlay?
    public let modal: Modal?
    public let infoBanner: InfoBanner?

    public init(id: String, cardOverlay: CardOverlay, modal: Modal? = nil) {
        self.id = id
        self.kind = .cardOverlay
        self.cardOverlay = cardOverlay
        self.modal = modal
        self.infoBanner = nil
    }

    public init(id: String, infoBanner: InfoBanner) {
        self.id = id
        self.kind = .infoBanner
        self.cardOverlay = nil
        self.modal = nil
        self.infoBanner = infoBanner
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cardOverlay:
            self.init(
                id: id,
                cardOverlay: try container.decode(CardOverlay.self, forKey: .cardOverlay),
                modal: try container.decodeIfPresent(Modal.self, forKey: .modal)
            )
        case .infoBanner:
            self.init(id: id, infoBanner: try container.decode(InfoBanner.self, forKey: .infoBanner))
        }
    }
}

public enum DebugPromotionPreset {
    public static let userDefaultsKey = "debug_showAirPromotionPreset"
    public static let cardMintingUserDefaultsKey = "debug_showCardMintingPromotionPreset"

    public static var isEnabled: Bool {
        airPromotionIsEnabled || cardMintingPromotionIsEnabled
    }

    private static let cachedAirPromotion = CachedUserDefault<Bool>(key: userDefaultsKey)
    private static let cachedCardMintingPromotion = CachedUserDefault<Bool>(key: cardMintingUserDefaultsKey)

    public static var airPromotionIsEnabled: Bool {
        #if DEBUG
        IS_DEBUG_OR_TESTFLIGHT && cachedAirPromotion.value
        #else
        false
        #endif
    }

    public static var cardMintingPromotionIsEnabled: Bool {
        IS_DEBUG_OR_TESTFLIGHT && cachedCardMintingPromotion.value
    }

    public static var activePromotion: ApiPromotion? {
        if cardMintingPromotionIsEnabled {
            return cardMintingPromotion
        }
        if airPromotionIsEnabled {
            return airPromotion
        }
        return nil
    }

    public static var cardsInfoOverride: ApiCardsInfo? {
        cardMintingPromotionIsEnabled ? cardMintingCardsInfo : nil
    }

    public static let airPromotion = ApiPromotion(
        id: "securityCheckup-2026",
        cardOverlay: .init(
            mascotIcon: .init(
                url: "https://static.mytonwallet.org/icons/promotion-air-mascot.webp",
                top: 31,
                right: 9,
                height: 107.1,
                width: 71.4,
                rotation: -2
            ),
            onClickAction: .openPromotionModal
        ),
        modal: .init(
            backgroundImageUrl: "https://static.mytonwallet.org/icons/promotion-air-bg.webp",
            backgroundFallback: "linear-gradient(135deg, #71AAEF 0%, #3F79CF 33.85%, #2E74B5 70.83%, #2160A1 100%)",
            heroImageUrl: "https://static.mytonwallet.org/icons/promotion-air-hero.webp",
            title: "Keep Your Wallet Protected",
            titleColor: "#FFFFFF",
            description: "Review your recovery phrase backup and keep biometric confirmation enabled for faster, safer approvals.",
            descriptionColor: "rgba(255, 255, 255, 0.75)",
            availabilityIndicator: nil,
            actionButton: .init(
                title: "Open Security Guide",
                url: "https://help.mytonwallet.io"
            )
        )
    )

    public static let airAccountConfig = ApiAccountConfig(activePromotion: airPromotion)

    public static let cardMintingPromotion = ApiPromotion(
        id: "cardMinting-2026",
        cardOverlay: .init(
            mascotIcon: .init(
                url: "https://static.mytonwallet.org/cards/v2/cards/1806.webp",
                top: 17,
                right: 5,
                height: 86,
                width: 86,
                rotation: -7
            ),
            onClickAction: .openMintCardModal
        ),
        modal: nil
    )

    public static let cardMintingCardsInfo = ApiCardsInfo(byType: [
        .standard: ApiCardInfo(all: 10_000, notMinted: 6_428, price: 50),
        .silver: ApiCardInfo(all: 5_000, notMinted: 2_341, price: 100),
        .gold: ApiCardInfo(all: 2_500, notMinted: 874, price: 250),
        .platinum: ApiCardInfo(all: 1_000, notMinted: 216, price: 500),
        .black: ApiCardInfo(all: 250, notMinted: 18, price: 1_000),
    ])
}

public enum DebugMfaEnabledOverride {
    public static let userDefaultsKey = "debug_forceMfaEnabled"
    private static let cachedValue = CachedUserDefault<Bool>(key: userDefaultsKey)

    public static var isEnabled: Bool {
        cachedValue.value
    }
}
