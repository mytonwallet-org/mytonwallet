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
    
    public init(nft: ApiNft?, hideBorder: Bool = false) {
        self.nft = nft
        self.hideBorder = hideBorder
    }
    
    public var body: some View {
        Color.clear
            .background {
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
                MtwCardHighlight(nft: nft)
            }
//            .backportGeometryGroup()
            .overlay {
                if !hideBorder {
                    MtwCardBorder(nft: nft)
                }
            }
    }
}

public extension UIImage {
    static let homeCard = UIImage.airBundle("HomeCard")
}
