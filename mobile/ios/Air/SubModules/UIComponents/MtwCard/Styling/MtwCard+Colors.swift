
import SwiftUI
import WalletCore
import WalletContext

public func getForegroundGradientColors(cardType: ApiMtwCardType?) -> [Color]? {
    switch cardType {
    case .black:
        [
            Color(UIColor(hex: "CECECF")),
            Color(UIColor(hex: "444546")),
        ]
    case .platinum:
        [
            Color(UIColor(hex: "FFFFFF")),
            Color(UIColor(hex: "77777F")),
        ]
    case .gold:
        [
            Color(UIColor(hex: "4C3403")),
            Color(UIColor(hex: "B07D1D")),
        ]
    case .silver:
        [
            Color(UIColor(hex: "272727")),
            Color(UIColor(hex: "989898")),
        ]
    case .standard, nil:
        nil
    }
}

public func getInverseForegroundGradientColors(cardType: ApiMtwCardType?) -> [Color]? {
    if let colors = getForegroundGradientColors(cardType: cardType) {
        return colors.reversed()
    }
    return nil
}

public func getSecondaryForegrundColor(nft: ApiNft?) -> Color {
    switch nft?.metadata?.mtwCardType {
    case .black: Color(UIColor(hex: "#ABACAD"))
    case .platinum: Color(UIColor(hex: "#DEDEE0"))
    case .gold: Color(UIColor(hex: "#65460A"))
    case .silver: Color(UIColor(hex: "#444444"))
    case .standard: nft?.metadata?.mtwCardTextType == .dark ? Color(UIColor(hex: "#2F3241")) : .white
    case nil: Color.white
    }
}

public func getCardBorderColors(nft: ApiNft?) -> [Color]? {
    if nft?.metadata?.mtwCardBorderShineType == .radioactive {
        return [
            Color(UIColor(hex: "5CE850")).opacity(0.95),
            Color(UIColor(hex: "5CE850")).opacity(0.95),
        ]
    }
    return switch nft?.metadata?.mtwCardType {
    case .black:
        [
            Color(UIColor {
                if  $0.userInterfaceStyle != .dark {
                    UIColor.white.withAlphaComponent(0.12)
                } else {
                    UIColor.white.withAlphaComponent(0.06)
                }
            }),
            Color(UIColor {
                if  $0.userInterfaceStyle != .dark {
                    UIColor.white.withAlphaComponent(0.24)
                } else {
                    UIColor.white.withAlphaComponent(0.12)
                }
            }),
        ]
    case .platinum:
        [
            Color(UIColor(hex: "77777F")).opacity(0.4),
            Color(UIColor(hex: "FFFFFF")).opacity(0.4),
        ]
    case .gold:
        [
            Color(UIColor(hex: "4C3403")).opacity(0.4),
            Color(UIColor(hex: "B07D1D")).opacity(0.4),
        ]
    case .silver:
        [
            Color(UIColor(hex: "272727")).opacity(0.4),
            Color(UIColor(hex: "989898")).opacity(0.4),
        ]
    case .standard:
        [
            Color(UIColor(hex: "8C94B0")).opacity(0.5),
            Color(UIColor(hex: "BABCC2")).opacity(0.85),
        ]
    case nil:
        nil
    }    
}
