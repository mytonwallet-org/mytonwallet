import UIKit
import WalletContext
import WalletCore

extension ApiCardInfo {
    var mintCountdownDate: Date? {
        guard notMinted == 0, let startsAt else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(startsAt))
            ?? (try? Date.ISO8601FormatStyle().parse(startsAt))
    }
}

struct MintCardTypeInfo: Identifiable, Sendable {
    let type: ApiMtwCardType
    let displayNameKey: String

    var id: ApiMtwCardType { type }

    static let ordered: [Self] = [
        .init(type: .standard, displayNameKey: "Standard Card"),
        .init(type: .silver, displayNameKey: "Silver Card"),
        .init(type: .gold, displayNameKey: "Gold Card"),
        .init(type: .platinum, displayNameKey: "Platinum Card"),
        .init(type: .black, displayNameKey: "Black Card"),
    ]

    static func at(page: Int) -> Self {
        ordered[((page % ordered.count) + ordered.count) % ordered.count]
    }

    var videoURL: URL? {
        URL(string: "\(MTW_CARDS_MINT_BASE_URL)mtw_card_\(type.rawValue).h264.mp4")
    }

    var posterURL: URL? {
        URL(string: "\(MTW_CARDS_MINT_BASE_URL)mtw_card_\(type.rawValue).avif")
    }

    @MainActor
    func accentColor(for traits: UITraitCollection) -> UIColor {
        switch type {
        case .standard:
            UIColor(hex: "0088FF")
        case .silver:
            UIColor(hex: "929395")
        case .gold:
            UIColor(hex: "DF9B23")
        case .platinum:
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.84, green: 0.87, blue: 0.91, alpha: 1)
                : UIColor(hex: "2A2C39")
        case .black:
            .white
        }
    }

    @MainActor var surfaceColor: UIColor {
        type == .black ? .black : .systemGroupedBackground
    }

    var posterBackground: UIColor {
        switch type {
        case .standard:
            UIColor(red: 0.11, green: 0.13, blue: 0.20, alpha: 1)
        case .black:
            UIColor(white: 0.01, alpha: 1)
        default:
            UIColor(white: 0.09, alpha: 1)
        }
    }
}
