//
//  CardMiniature.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import Kingfisher

struct CardMiniature: View {
    
    let accountContext: AccountContext
    
    private let cardPreviewSize = CGSize(width: 22, height: 14)
    
    var body: some View {
        WithPerceptionTracking {
            if let imageUrl = accountContext.nft?.metadata?.mtwCardBackgroundUrl {
                ZStack {
                    Color.clear
                    KFImage(source: .network(imageUrl))
                        .resizable()
                        .fade(duration: 0.15)
                        .loadDiskFileSynchronously(false)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(.smooth(duration: 0.15)))
                }
                .frame(width: cardPreviewSize.width, height: cardPreviewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    MtwCardMiniPlaceholders()
                        .sourceAtop { MtwCardInverseCenteredGradient(nft: accountContext.nft) }
                        .scaleEffect(0.8)
                }
            }
        }
    }
}
