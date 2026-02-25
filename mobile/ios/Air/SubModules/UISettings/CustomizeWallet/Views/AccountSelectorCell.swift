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
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCard(aspectRatio: LARGE_CARD_RATIO)
                .background {
                    CardBackground(accountContext: accountContext)
                }
                .overlay {
                    _BalanceView(accountContext: accountContext)
                        .offset(y: -4)
                        .padding(.horizontal, 16)
                }
                .overlay(alignment: .top) {
                    AccountTitle(accountContext: accountContext)
                        .padding(.top, 16.333)
                        .padding(.horizontal, 20)
                }
                .overlay(alignment: .bottom) {
                    GridAddressLine(accountContext: accountContext)
                        .padding(.bottom, 17)
                        .padding(.horizontal, 16)
                }
                .clipShape(.rect(cornerRadius: 26))
                .containerShape(.rect(cornerRadius: 26))
        }
    }
}

private struct CardBackground: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: accountContext.nft)
        }
    }
}

private struct AccountTitle: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            Text(accountContext.account.displayName)
                .font(.compactDisplay(size: 17, weight: .medium))
                .lineLimit(1)
                .allowsTightening(true)
                .foregroundStyle(MtwCardInverseCenteredGradientStyle(nft: accountContext.nft))
        }
    }
}

private struct _BalanceView: View {
    
    var accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: accountContext.balance, style: .customizeWalletCard)
                .padding(10)
                .sourceAtop {
                    MtwCardBalanceGradient(nft: accountContext.nft)
                }
                .padding(-10)
        }
    }
}

private struct GridAddressLine: View {
    
    var accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardAddressLine(addressLine: accountContext.account.addressLine, style: .customizeWalletCard, gradient: MtwCardCenteredGradient(nft: accountContext.nft))
        }
    }
}
