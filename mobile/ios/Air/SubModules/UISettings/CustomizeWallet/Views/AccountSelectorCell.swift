//
//  WalletSettingsGridCell.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import SwiftUI
import Perception
import UIComponents
import WalletCore
import WalletContext

struct AccountSelectorCell: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCard(aspectRatio: LARGE_CARD_RATIO)
                .background {
                    CardBackground(viewModel: viewModel)
                }
                .overlay {
                    _BalanceView(viewModel: viewModel)
                }
                .overlay(alignment: .top) {
                    AccountTitle(viewModel: viewModel)
                        .padding(.top, 16)
                    
                }
                .overlay(alignment: .bottom) {
                    GridAddressLine(viewModel: viewModel)
                        .padding(16)
                }
                .clipShape(.rect(cornerRadius: 26))
                .containerShape(.rect(cornerRadius: 26))
        }
    }
}

private struct CardBackground: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: viewModel.nft)
                .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
        }
    }
}

private struct AccountTitle: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        Text(viewModel.account.displayName)
            .font(.compactMedium(size: 17))
            .lineLimit(1)
            .allowsTightening(true)
            .padding(.vertical, 20)
            .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
            .padding(.vertical, -20)
            .padding(.horizontal, 10)
    }
}

private struct _BalanceView: View {
    
    var viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: viewModel.balance, style: .customizeWalletCard)
                .sourceAtop(MtwCardForegroundStyle(nft: viewModel.nft))
        }
    }
}

private struct GridAddressLine: View {
    
    var viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardAddressLine(addressLine: viewModel.account.addressLine, style: .customizeWalletCard)
                .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
        }
    }
}
