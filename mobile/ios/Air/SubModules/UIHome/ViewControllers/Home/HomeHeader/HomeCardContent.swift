//
//  HomeCard.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

struct HomeCardContent: View {
    
    var headerViewModel: HomeHeaderViewModel
    var accountViewModel: AccountViewModel
    
    var progress: CGFloat { headerViewModel.collapseProgress }
    
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                _CenterContent(headerViewModel: headerViewModel, viewModel: accountViewModel)
                    .scaleEffect(balanceScale)
                    .backportGeometryGroup()
                    .offset(y: -bottomPadding)
                    .id(accountViewModel.accountId)
                _AddressLine(viewModel: accountViewModel)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(headerViewModel.isCardHidden ? 0 : 1)
        }
    }
    
    var targetBottomPadding: CGFloat {
        -16 + (IOS_26_MODE_ENABLED ? -3 : -14)
    }

    var balanceScale: CGFloat { interpolate(from: 1, to: 17.0/40.0, progress: progress) }
    var bottomPadding: CGFloat { interpolate(from: 0, to: targetBottomPadding, progress: progress) }
}

private struct _CenterContent: View {
    
    let headerViewModel: HomeHeaderViewModel
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 5) {
                _BalanceView(viewModel: viewModel)
                    .padding(.leading, 1)
                    .padding(.horizontal, 32)
                
                _BalanceChange(viewModel: viewModel)
            }
            .offset(y: -5)
        }
    }
}

private struct _BalanceView: View {

    let viewModel: AccountViewModel

    var body: some View {
        WithPerceptionTracking {
            _BalanceViewContent(
                accountId: viewModel.accountId,
                balance: viewModel.balance,
                nft: viewModel.nft,
                isCurrent: viewModel.isCurrent
            )
        }
    }
}

private struct _BalanceViewContent: View, Equatable {

    var accountId: String
    var balance: BaseCurrencyAmount?
    var nft: ApiNft?
    var isCurrent: Bool
    
    @State private var menuContext = MenuContext()

    var body: some View {
        MtwCardBalanceView(balance: balance, isNumericTranstionEnabled: isCurrent, style: .homeCard, secondaryOpacity: nft?.metadata?.mtwCardType?.isPremium == true ? 1 : 0.75)
            .padding(40)
            .sourceAtop {
                MtwCardBalanceGradient(nft: nft)
            }
            .padding(-40)
            .menuSource(isEnabled: true, menuContext: menuContext)
            .task(id: accountId) {
                    menuContext.minWidth = 250
                    menuContext.verticalOffset = -8
                    menuContext.makeConfig = makeBaseCurrencyMenuConfig(accountId: accountId)
            }
            .backportGeometryGroup()
    }
    
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.balance == rhs.balance && lhs.nft == rhs.nft && lhs.isCurrent == rhs.isCurrent
    }
}

private struct _BalanceChange: View {

    let viewModel: AccountViewModel

    var body: some View {
        WithPerceptionTracking {
            _BalanceChangeContent(balance: viewModel.balance, balance24h: viewModel.balance24h, balanceChange: viewModel.balanceChange, nft: viewModel.nft)
        }
    }
}

private struct _BalanceChangeContent: View {

    let balance: BaseCurrencyAmount?
    let balance24h: BaseCurrencyAmount?
    let balanceChange: Double?
    let nft: ApiNft?

    var body: some View {
        HStack {
            if let text {
                Text(text)
                        .font(.compactMedium(size: 17))
                        .opacity(0.8)
                        .padding(.horizontal, 8)
                        .background {
                            Capsule()
                                .opacity(0.10)
                            .frame(height: 26)
                    }
                    .sensitiveData(alignment: .center, cols: 10, rows: 2, cellSize: 13, theme: .light, cornerRadius: 13)
            } else {
                Color.clear
                    .frame(width: 76, height: 26)
            }
        }
        .foregroundStyle(getSecondaryForegrundColor(nft: nft))
        .backportGeometryGroup()
    }
    
    var text: String? {
        if let balance, let balance24h {
            if balance.amount == 0 && balance24h.amount == 0 {
                return nil
            } else {
                let change = BaseCurrencyAmount(balance.amount - balance24h.amount, balance.baseCurrency)
                let string = change.formatted(.baseCurrencyEquivalent, showMinus: false)
                let percentString = if let balanceChange {
                    "\(formatPercent(balanceChange)) · "
                } else {
                    ""
                }
                return "\(percentString)\(string)"
            }
        } else {
            return nil
        }
    }
}

private struct _AddressLine: View {

    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            let account = viewModel.account
            _AddressLineContent(
                accountId: account.id,
                isTemporary: account.isTemporary == true,
                addressLine: account.addressLine,
                nft: viewModel.nft
            )
        }
    }
}

private struct _AddressLineContent: View {

    var accountId: String
    var isTemporary: Bool
    var addressLine: MAccount.AddressLine
    var nft: ApiNft?
    
    @State private var menuContext = MenuContext()
    
    var body: some View {
        HStack(spacing: 8) {
            if isTemporary {
                AddViewButton(accountId: accountId, foregroundStyle: getSecondaryForegrundColor(nft: nft))
                    .padding(.vertical, -6)
            }
            MtwCardAddressLine(addressLine: addressLine, style: .homeCard, gradient: MtwCardCenteredGradient(nft: nft))
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .menuSource(isEnabled: true, isHoldAndDragGestureEnabled: false, menuContext: menuContext)
                .task(id: accountId) {
                    menuContext.verticalOffset = -8
                    menuContext.minWidth = 280
                    menuContext.makeConfig = makeAddressesMenuConfig(accountId: accountId)
                }
                .padding(.trailing, -8)
                .backportGeometryGroup()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 9)
    }
}
