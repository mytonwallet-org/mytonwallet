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
                        .offset(y: -4)
                        .padding(.horizontal, 16)
                }
                .overlay(alignment: .top) {
                    AccountTitle(viewModel: viewModel)
                        .padding(.top, 16.333)
                        .padding(.horizontal, 20)   
                }
                .overlay(alignment: .bottom) {
                    GridAddressLine(viewModel: viewModel)
                        .padding(.bottom, 17)
                        .padding(.horizontal, 16)
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
        }
    }
}

private struct AccountTitle: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            Text(viewModel.account.displayName)
                .font(.compactMedium(size: 17))
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .sourceAtop {
                    MtwCardInverseCenteredGradient(nft: viewModel.nft)
                }
                .padding(.vertical, -20)
        }
    }
}

private struct _BalanceView: View {
    
    var viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: viewModel.balance, style: .customizeWalletCard)
                .padding(10)
                .sourceAtop {
                    MtwCardBalanceGradient(nft: viewModel.nft)
                }
                .padding(-10)
        }
    }
}

private struct GridAddressLine: View {
    
    var viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardAddressLine(addressLine: viewModel.account.addressLine, style: .customizeWalletCard, gradient: MtwCardCenteredGradient(nft: viewModel.nft))
        }
    }
}
