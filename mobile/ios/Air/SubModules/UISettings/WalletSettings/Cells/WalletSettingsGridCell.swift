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
    
    let viewModel: WalletSettingsItemViewModel
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 7) {
                MtwCard(aspectRatio: SMALL_CARD_RATIO)
                    .background {
                        MtwCardBackground(nft: viewModel.cardProvider.nft, hideBorder: true)
                    }
                    .overlay {
                        _BalanceView(viewModel: viewModel)
                    }
                    .overlay(alignment: .bottom) {
                        GridAddressLine(addressLine: viewModel.account.addressLine)
                            .foregroundStyle(.white)
                            .padding(8)
                        
                    }
                    .clipShape(.containerRelative)
                    .mtwCardSelection(isSelected: viewModel.isCurrent, cornerRadius: 12, lineWidth: borderWidth)
                    .containerShape(.rect(cornerRadius: 12))
                    
                Text(viewModel.account.displayName)
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
    
    var viewModel: WalletSettingsItemViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: viewModel.balance, style: .grid)
                .frame(height: 24, alignment: .center)
                .padding(.leading, 6)
                .padding(.trailing, 5)
                .padding(.bottom, 6)
                .sourceAtop(MtwCardForegroundStyle(nft: viewModel.cardProvider.nft))
        }
    }
}

private struct GridAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    
    var body: some View {
        MtwCardAddressLine(addressLine: addressLine, style: .card)
    }
}
