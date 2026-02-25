//
//  WalletSettingsVC.swift
//  UISettings
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

struct SelectCardSection: View {

    let viewModel: CustomizeWalletViewModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection(backgroundColor: .clear,  horizontalPadding: 16) {
                HStack {
                    if viewModel.selectedAccountInfo.availableCards.count > 0 {
                        VStack(spacing: 14) {
                            Text(lang("Select the card stored in this wallet:"))
                                .foregroundStyle(Color.air.secondaryLabel)
                                .font(.system(size: 14, weight: .regular))
                            CardSelectionView(viewModel: viewModel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding([.bottom, .horizontal], 12)
                    } else {
                        SelectCardEmptyView(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    }
                }
                .background {
                    CustomizeWalletBubble()
                        .foregroundStyle(Color.air.groupedItem)
                }
                .padding(.top, 16)
            } header: {} footer: {
                if viewModel.selectedAccountInfo.availableCards.count > 0 {
                    Text("This card will be installed for this wallet and will be displayed on the home screen and in the wallets list.")
                        .transition(.opacity.combined(with: .offset(y: -10)))
                        .padding(.bottom, -8)
                }
            }
        }
    }
}

struct CustomizeWalletBubble: View {
    var body: some View {
        HStack(spacing: 0) {
            let image = Image.airBundle("CustomizeWalletHalfBubble")
                .resizable(
                    capInsets: EdgeInsets(top: 66, leading: 50, bottom: 50, trailing: 50)
                )
            image
            image.scaleEffect(x: -1)
        }
        .padding(.top, -16) // bubble tail
    }
}

struct SelectCardEmptyView: View {
    
    let viewModel: CustomizeWalletViewModel
    @State private var playTrigger = 0
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 16) {
                WUIAnimatedSticker("duck_no-data", size: 100, loop: false, playTrigger: playTrigger)
                Text(lang("You don’t have any cards to customize yet"))
                    .font(.system(size: 14, weight: .semibold))
                Text(lang("MyTonWallet Cards can be installed for wallets and displayed on the home screen an in the wallet list."))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .contentShape(.rect)
            .onTapGesture {
                AppActions.showUpgradeCard()
            }
        }
    }
}

struct CardSelectionView: View {
    let viewModel: CustomizeWalletViewModel

    @State private var containerWidth: CGFloat = 0

    private let gridSpacing: CGFloat = 8
    private let gridMaximumCardWidth: CGFloat = 150

    var body: some View {
        WithPerceptionTracking {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(viewModel.selectedAccountInfo.availableCards) { (nft: ApiNft?) in
                    CardView(viewModel: viewModel, nft: nft)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                containerWidth = $0
            }
        }
    }

    private var gridColumns: [GridItem] {
        let columnCount = max(3, Int(ceil((containerWidth + gridSpacing) / (gridMaximumCardWidth + gridSpacing))))
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: gridMaximumCardWidth), spacing: gridSpacing),
            count: columnCount
        )
    }
}

private struct CardView: View {
    let viewModel: CustomizeWalletViewModel
    let nft: ApiNft?
    
    var body: some View {
        WithPerceptionTracking {
            MtwCard(aspectRatio: MEDIUM_CARD_RATIO)
                .overlay {
                    MtwCardBalanceView(balance: viewModel.balance, style: .grid)
                        .padding(10)
                        .sourceAtop {
                            MtwCardBalanceGradient(nft: nft)
                        }
                        .padding(-10)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                        .transition(.opacity)
                        .id(viewModel.selectedAccountId)
                }
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.white.opacity(0.75))
                        .frame(height: 5)
                        .sourceAtop {
                            MtwCardInverseCenteredGradient(nft: nft)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)
                }
                .background {
                    MtwCardBackground(nft: nft, borderWidthMultiplier: 0.5)
                }
                .clipShape(.containerRelative)
                .containerShape(.rect(cornerRadius: 12))
                .onTapGesture {
                    viewModel.selectCard(nft)
                }
        }
    }
}

extension Optional: @retroactive Identifiable where Wrapped: Identifiable {
    public var id: Optional<Wrapped.ID> {
        self.flatMap(\.id)
    }
}
