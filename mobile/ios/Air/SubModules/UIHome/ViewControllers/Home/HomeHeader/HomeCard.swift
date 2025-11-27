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

struct HomeCard: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    let viewModel: AccountViewModel
    var ns: Namespace.ID
    
    @Namespace private var localNs
    
    var body: some View {
        WithPerceptionTracking {
            MtwCard(aspectRatio: 1/CARD_RATIO)
                .background {
                    _Background(homeHeaderViewModel: homeHeaderViewModel, viewModel: viewModel, ns: ns, localNs: localNs)
                }
                .overlay {
                    _CardContent(homeHeaderViewModel: homeHeaderViewModel, viewModel: viewModel, ns: ns, localNs: localNs)
                }
                .containerShape(.rect(cornerRadius: 26))
        }
    }
}

private struct _CardContent: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    let viewModel: AccountViewModel
    var ns: Namespace.ID
    var localNs: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                _CenterContent(homeHeaderViewModel: homeHeaderViewModel, viewModel: viewModel, ns: ns)
                    .scaleEffect(isCollapsed ? 40/56 : 1)
                    .offset(x: isCollapsed ? 12 : 0, y: isCollapsed ? 62 : 0)
                _AddressLine(viewModel: viewModel)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                Rectangle()
                    .matchedGeometryEffect(
                        id: "\(viewModel.account.id)-mask",
                        in: localNs,
                        properties: .position,
                        anchor: .bottom,
                        isSource: false
                    )
            }
        }
    }
    
    var isCollapsed: Bool {
        homeHeaderViewModel.isCollapsed && viewModel.isCurrent
    }
}

private struct _Background: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    let viewModel: AccountViewModel
    var ns: Namespace.ID
    var localNs: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            _StaticBackground(viewModel: viewModel)
                .matchedGeometryEffect(
                    id: "\(viewModel.account.id)-mask",
                    in: localNs,
                    properties: .position,
                    anchor: .bottom,
                    isSource: isCollapsed
                )

                .scaleEffect(isCollapsed ? 34/(homeHeaderViewModel.width - 32) : 1, anchor: .bottom)
                .overlay(alignment: .bottom) {
                    MtwCardMiniPlaceholders()
                        .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
                        .drawingGroup()
                        .padding(.bottom, 3)
                        .frame(maxHeight: isCollapsed ? nil : .infinity)
                        .opacity(isCollapsed ? 1 : 0)
                }
                .offset(y: isCollapsed ? -116 : 0)
                .scaleEffect(isHidden ? 0.9 : 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    var isCollapsed: Bool {
        homeHeaderViewModel.isCollapsed && viewModel.isCurrent
    }
    
    var isHidden: Bool {
        homeHeaderViewModel.isCollapsed && !viewModel.isCurrent
    }
}

private struct _StaticBackground: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: viewModel.nft, hideBorder: false)
                .aspectRatio(1/CARD_RATIO, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 26))
                .containerShape(.rect(cornerRadius: 26))
                .drawingGroup()
        }
    }
}

private struct _CenterContent: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    let viewModel: AccountViewModel
    var ns: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 5) {
                BalanceView(viewModel: viewModel)
//                    .matchedGeometryEffect(
//                        id: "\(viewModel.accountId)-balance",
//                        in: ns,
//                        properties: .size,
//                        anchor: .center,
//                        isSource: !isCollapsed
//                    )
                    .padding(.leading, 1)
                    .padding(.horizontal, 32)
                
                BalanceChange(viewModel: viewModel)
            }
            .offset(y: -5)
            .backportGeometryGroup()
        }
    }
    
    var isCollapsed: Bool {
        homeHeaderViewModel.isCollapsed && viewModel.isCurrent
    }
}

private struct BalanceView: View {

    let viewModel: AccountViewModel
    @State private var menuContext = MenuContext()

    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: viewModel.balance, isNumericTranstionEnabled: viewModel.isCurrent, style: .homeCard)
                .padding(40)
                .sourceAtop(MtwCardForegroundStyle(nft: viewModel.nft))
                .padding(-40)
                .menuSource(isEnabled: true, menuContext: menuContext)
                .task {
                    menuContext.minWidth = 250
                    menuContext.verticalOffset = -8
                    menuContext.makeConfig = makeBaseCurrencyMenuConfig
                }
                .backportGeometryGroup()
        }
    }
}

private struct BalanceChange: View {

    let viewModel: AccountViewModel

    var body: some View {
        WithPerceptionTracking {
            HStack {
                if let text {
                    Text(text)
                        .font(.compactMedium(size: 17))
                        .opacity(0.75)
                        .padding(.horizontal, 8)
                        .background {
                            Capsule()
                                .opacity(0.16)
                                .frame(height: 26)
                        }
                        .sensitiveData(alignment: .center, cols: 10, rows: 2, cellSize: 13, theme: .light, cornerRadius: 13)
                        .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
                } else {
                    Color.clear
                        .frame(width: 76, height: 26)
                }
            }
            .backportGeometryGroup()
        }
    }
    
    var text: String? {
        if let balance = viewModel.balance, let balance24h = viewModel.balance24h {
            if balance.amount == 0 && balance24h.amount == 0 {
                return nil
            } else {
                let change = BaseCurrencyAmount(balance.amount - balance24h.amount, balance.baseCurrency)
                let string = change.formatted(showPlus: false, showMinus: false)
                let percentString = balance24h.amount == 0 ? "" : "\(balance.doubleValue - balance24h.doubleValue >= 0 ? "+" : "")\(((balance.doubleValue - balance24h.doubleValue) / balance24h.doubleValue * 10000).rounded() / 100)% · "
                return "\(percentString)\(string)"
            }
        } else {
            return nil
        }
    }
}

private struct _AddressLine: View {

    let viewModel: AccountViewModel
    @State private var menuContext = MenuContext()
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardAddressLine(addressLine: viewModel.account.addressLine, style: .homeCard)
                .foregroundStyle(MtwCardForegroundStyle(nft: viewModel.nft))
                .padding(.horizontal, 40)
                .padding(.vertical, 8)
                .menuSource(isEnabled: true, isHoldAndDragGestureEnabled: false, menuContext: menuContext)
                .task {
                    menuContext.verticalOffset = -8
                    menuContext.minWidth = 280
                    menuContext.makeConfig = makeAddressesMenuConfig
                }
                .padding(.bottom, 9)
                .backportGeometryGroup()
                .drawingGroup()
        }
    }
}


@available(iOS 26, *)
#Preview {
    @Previewable @Namespace var ns
    @Previewable let hh = HomeHeaderViewModel()
    @Previewable let vm = AccountViewModel(accountId: "1-mainnet")
    let _ = UIFont.registerAirFonts()
    HomeCard(homeHeaderViewModel: hh, viewModel: vm, ns: ns)
        .padding(16)
}
