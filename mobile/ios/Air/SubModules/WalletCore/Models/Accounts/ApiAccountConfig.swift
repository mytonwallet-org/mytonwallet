import Foundation

public struct ApiCardInfo: Equatable, Hashable, Codable, Sendable {
    public var all: Int
    public var notMinted: Int
    public var price: Double
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

    private enum CodingKeys: String, CodingKey {
        case cardsInfo
        case activePromotion
    }

    public init(cardsInfo: ApiCardsInfo? = nil, activePromotion: ApiPromotion? = nil) {
        self.cardsInfo = cardsInfo
        self.activePromotion = activePromotion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cardsInfo = try? container.decodeIfPresent(ApiCardsInfo.self, forKey: .cardsInfo)
        self.activePromotion = try? container.decodeIfPresent(ApiPromotion.self, forKey: .activePromotion)
    }
}

public struct ApiPromotion: Equatable, Hashable, Codable, Sendable {
    public enum Kind: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
        case cardOverlay
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

    public var id: String
    public var kind: Kind
    public var cardOverlay: CardOverlay
    public var modal: Modal?
}

#if DEBUG
public enum DebugPromotionPreset {
    public static let userDefaultsKey = "debug_showAirPromotionPreset"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    public static let airPromotion = ApiPromotion(
        id: "airPromotion-2026",
        kind: .cardOverlay,
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
            title: "Tired of MyTonWallet Air?",
            titleColor: "#FFFFFF",
            description: "This month, it will become the default interface for all users. The Classic interface can still be chosen in **Settings > Appearance**.",
            descriptionColor: "rgba(255, 255, 255, 0.75)",
            availabilityIndicator: nil,
            actionButton: .init(
                title: "Try MyTonWallet Classic",
                url: "mtw://classic"
            )
        )
    )

    public static let airAccountConfig = ApiAccountConfig(activePromotion: airPromotion)
}
#endif
