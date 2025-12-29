
import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardCenteredGradient: View {
    
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
                    colors: getForegroundGradientColors(cardType: cardType)!,
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: geom.size.width * 0.95 / 2,
                )
            }
        }
    }
}
