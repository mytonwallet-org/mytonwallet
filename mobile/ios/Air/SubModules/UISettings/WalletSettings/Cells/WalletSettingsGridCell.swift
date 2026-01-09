//
//  WalletSettingsGridCell.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.11.2025.
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

let borderWidth = 1.5

struct WalletSettingsGridCell: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 7) {
                MtwCard(aspectRatio: SMALL_CARD_RATIO)
                    .background {
                        MtwCardBackground(nft: accountContext.nft, hideBorder: true)
                    }
                    .overlay {
                        _BalanceView(accountContext: accountContext)
                    }
                    .overlay(alignment: .bottom) {
                        GridAddressLine(addressLine: accountContext.account.addressLine, nft: accountContext.nft)
                            .foregroundStyle(.white)
                            .padding(8)
                        
                    }
                    .clipShape(.containerRelative)
                    .mtwCardSelection(isSelected: accountContext.isCurrent, cornerRadius: 12, lineWidth: borderWidth)
                    .containerShape(.rect(cornerRadius: 12))
                    
                Text(accountContext.account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .padding(.horizontal, -2)
                    .padding(.bottom, 7)
                
            }
        }
    }
}

private struct _BalanceView: View {
    
    var accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: accountContext.balance, style: .grid)
                .frame(height: 24, alignment: .center)
                .padding(.leading, 6)
                .padding(.trailing, 5)
                .padding(.bottom, 6)
                .sourceAtop {
                    MtwCardBalanceGradient(nft: accountContext.nft)
                }
        }
    }
}

private struct GridAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    var nft: ApiNft?
    
    var body: some View {
        MtwCardAddressLine(addressLine: addressLine, style: .card, gradient: MtwCardCenteredGradient(nft: nft))
    }
}
