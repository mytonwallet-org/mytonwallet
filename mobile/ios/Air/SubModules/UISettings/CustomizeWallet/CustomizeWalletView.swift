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

struct CustomizeWalletView: View {
    
    let viewModel: CustomizeWalletViewModel
    
    var body: some View {
        InsetList(topPadding: 24, spacing: 16) {
            AccountSelectorView(viewModel: viewModel, onSelect: { accountId in
                withAnimation {
                    viewModel.selectedAccountId = accountId
                }
            })
            SelectCardSection(viewModel: viewModel)
            PaletteSection(viewModel: viewModel.palletteSettingsViewModel)
            if !viewModel.isRestricted {
                GetMoreCardsSection(viewModel: viewModel)
            }
        }
        .backportSafeAreaPadding(.bottom, 32)
        .scrollIndicators(.hidden)
    }
}

struct GetMoreCardsSection: View {

    let viewModel: CustomizeWalletViewModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                InsetButtonCell(action: onUnlockNew) {
                    HStack(spacing: 19) {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                        Text(lang("Get More Cards"))
                    }
                    .foregroundStyle(viewModel.tintColor)
                    .backportGeometryGroup()
                }
            } footer: {
                Text(lang("Browse MyTonWallet Cards available for purchase."))
            }
        }
    }
    
    func onUnlockNew() {
        AppActions.showUpgradeCard()
    }
}
