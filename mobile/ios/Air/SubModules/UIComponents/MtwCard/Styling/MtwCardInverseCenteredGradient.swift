
import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardInverseCenteredGradient: View {
    
    var nft: ApiNft?
    
    public init(nft: ApiNft?) {
        self.nft = nft
    }
    
    public var body: some View {
        GeometryReader { geom in
            let cardType = nft?.metadata?.mtwCardType
            switch cardType {
            case nil:
                Color.white
            case .standard:
                nft?.metadata?.mtwCardTextType == .dark ? Color(UIColor(hex: "2F3241")) : Color.white
            case .silver, .gold, .platinum, .black:
                RadialGradient(
                    colors: getInverseForegroundGradientColors(cardType: cardType)!,
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: geom.size.width * 0.95 / 2,
                )
            }
        }
    }
}

public struct MtwCardInverseCenteredGradientStyle: ShapeStyle {
    
    var nft: ApiNft?
    
    public init(nft: ApiNft?) {
        self.nft = nft
    }
    
    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let cardType = nft?.metadata?.mtwCardType
        switch cardType {
        case nil:
            return AnyShapeStyle(Color.white)
        case .standard:
            return AnyShapeStyle(nft?.metadata?.mtwCardTextType == .dark ? Color(UIColor(hex: "2F3241")) : Color.white)
        case .silver, .gold, .platinum, .black:
            let colors = getInverseForegroundGradientColors(cardType: cardType)!
            assert(colors.count == 2)
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: colors[1], location: -0.1),
                    .init(color: colors[0], location: 0.5),
                    .init(color: colors[1], location: 1.1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}
