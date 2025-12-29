//
//  MtwCardBackground.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import SwiftUI
import Kingfisher
import WalletCore
import WalletContext

public struct MtwCardBackground: View {
    
    var nft: ApiNft?
    var hideBorder: Bool
    var borderWidthMultiplier: CGFloat
    
    public init(nft: ApiNft?, hideBorder: Bool = false, borderWidthMultiplier: CGFloat = 1) {
        self.nft = nft
        self.hideBorder = hideBorder
        self.borderWidthMultiplier = borderWidthMultiplier
    }
    
    public var body: some View {
        Color.air.groupedBackground
            .overlay {
                ZStack {
                    if let imageUrl = nft?.metadata?.mtwCardBackgroundUrl {
                        KFImage(source: .network(imageUrl))
                            .resizable()
                            .fade(duration: 0.15)
                            .loadDiskFileSynchronously(false)
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.animation(.smooth(duration: 0.15)))
                    } else {
                        Image(uiImage: .homeCard)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.animation(.smooth(duration: 0.15)))
                    }
                }
            }
            .overlay {
                if !hideBorder {
                    MtwCardBorder(nft: nft, borderWidthMultiplier: borderWidthMultiplier)
                }
            }
    }
}

public extension UIImage {
    static let homeCard = UIImage.airBundle("HomeCard")
}
