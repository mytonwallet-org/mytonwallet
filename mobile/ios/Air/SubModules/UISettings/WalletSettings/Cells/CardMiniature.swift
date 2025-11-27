//
//  CardMiniature.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import Kingfisher

struct CardMiniature: View {
    
    let viewModel: AccountCurrentMtwCardProvider
    
    private let cardPreviewSize = CGSize(width: 22, height: 14)
    
    var body: some View {
        WithPerceptionTracking {
            if let imageUrl = viewModel.imageUrl {
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
                        .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
                        .scaleEffect(0.8)
                }
            }
        }
    }
}

@Perceptible
final class AccountCurrentMtwCardProvider {
    
    let accountId: String
    var imageUrl: URL?
    
    init(accountId: String) {
        self.accountId = accountId
        if let nft, let url = nft.metadata?.mtwCardBackgroundUrl {
            imageUrl = url
        } else  {
            imageUrl = nil
        }
    }
    
    var nft: ApiNft? {
        if let data = GlobalStorage["settings.byAccountId.\(accountId).cardBackgroundNft"], let nft = try? JSONSerialization.decode(ApiNft.self, from: data) {
            return nft
        }
        return nil
    }
}

