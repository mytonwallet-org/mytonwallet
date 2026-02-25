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
    var accountContext: AccountContext
    var layout: HomeCardLayoutMetrics
    var minimumHomeCardFontScale: CGFloat = 1
    
    var progress: CGFloat { headerViewModel.collapseProgress }
    
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                _CenterContent(
                    headerViewModel: headerViewModel,
                    accountContext: accountContext,
                    layout: layout,
                    minimumHomeCardFontScale: minimumHomeCardFontScale
                )
                    .scaleEffect(balanceScale)
                    .backportGeometryGroup()
                    .offset(y: -bottomPadding)
                    .id(accountContext.accountId)
                _AddressLine(accountContext: accountContext)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                SeasonalOverlay(seasonalTheme: headerViewModel.seasonalTheme)
            }
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
    let accountContext: AccountContext
    let layout: HomeCardLayoutMetrics
    let minimumHomeCardFontScale: CGFloat
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 5) {
                _BalanceView(accountContext: accountContext, layout: layout, minimumHomeCardFontScale: minimumHomeCardFontScale)
                    .padding(.leading, 1)
                    .padding(.horizontal, 32)
                
                _BalanceChange(accountContext: accountContext)
            }
            .offset(y: -5)
        }
    }
}

private struct _BalanceView: View {

    let accountContext: AccountContext
    let layout: HomeCardLayoutMetrics
    let minimumHomeCardFontScale: CGFloat

    var body: some View {
        WithPerceptionTracking {
            _BalanceViewContent(
                accountId: accountContext.accountId,
                balance: accountContext.balance,
                nft: accountContext.nft,
                isCurrent: accountContext.isCurrent,
                cardWidth: layout.itemWidth,
                minimumHomeCardFontScale: minimumHomeCardFontScale
            )
        }
    }
}

private struct _BalanceViewContent: View, Equatable {

    var accountId: String
    var balance: BaseCurrencyAmount?
    var nft: ApiNft?
    var isCurrent: Bool
    var cardWidth: CGFloat
    var minimumHomeCardFontScale: CGFloat
    
    @State private var menuContext = MenuContext()

    var body: some View {
        MtwCardBalanceView(balance: balance, isNumericTranstionEnabled: isCurrent, style: .homeCard(cardWidth: cardWidth, minimumScale: minimumHomeCardFontScale), secondaryOpacity: nft?.metadata?.mtwCardType?.isPremium == true ? 1 : 0.75)
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
        lhs.balance == rhs.balance &&
        lhs.nft == rhs.nft &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.cardWidth == rhs.cardWidth &&
        lhs.minimumHomeCardFontScale == rhs.minimumHomeCardFontScale
    }
}

private struct _BalanceChange: View {

    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            _BalanceChangeContent(balance: accountContext.balance, balance24h: accountContext.balance24h, balanceChange: accountContext.balanceChange, nft: accountContext.nft)
        }
    }
}

private struct _BalanceChangeContent: View, Equatable {
    let text: String?
    let nft: ApiNft?
    
    init(balance: BaseCurrencyAmount?, balance24h: BaseCurrencyAmount?, balanceChange: Double?, nft: ApiNft?) {
        self.text = Self.makeText(balance: balance, balance24h: balance24h, balanceChange: balanceChange)
        self.nft = nft
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.nft == rhs.nft
    }

    var body: some View {
        ZStack {
            if let text {
                if text.isEmpty {
                    emptyView()
                } else {
                    mainView(text)
                }
            } else {
                placeholderView()
            }
        }
        .foregroundStyle(getSecondaryForegrundColor(nft: nft))
        .backportGeometryGroup()
    }
    
    private static func makeText(
        balance: BaseCurrencyAmount?,
        balance24h: BaseCurrencyAmount?,
        balanceChange: Double?
    ) -> String? {
        guard let balance
        else { return nil }
        
        guard let balance24h, balance.amount > 0, balance24h.amount > 0
        else { return "" }
        
        let change = BaseCurrencyAmount(balance.amount - balance24h.amount, balance.baseCurrency)
        let string = change.formatted(.baseCurrencyEquivalent, showMinus: false)
        let percentString =
            if let balanceChange { "\(formatPercent(balanceChange)) · " }
            else { "" }
        
        return "\(percentString)\(string)"
    }
    
    private func mainView(_ text: String) -> some View {
        Button {
            if let url = URL(string: "https://portfolio.mytonwallet.io") {
                AppActions.openInBrowser(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.compactDisplay(size: 17, weight: .medium))
            .opacity(0.8)
            .padding(.horizontal, 8)
            .background {
                ZStack {
                    BackgroundBlur(radius: 12)
                    Capsule().opacity(0.10)
                }
                .clipShape(.capsule)
                .frame(height: 26)
            }
        }
        .buttonStyle(.plain)
        .sensitiveData(
            alignment: .center,
            cols: 10,
            rows: 2,
            cellSize: 13,
            theme: .light,
            cornerRadius: 13
        )
    }
    
    private func placeholderView() -> some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .clipShape(.capsule)
            .frame(idealWidth: 76, maxWidth: 76, minHeight: 26, maxHeight: 26)
    }
    
    private func emptyView() -> some View {
        Color.clear
            .frame(width: 76, height: 26)
    }
}

private struct _AddressLine: View {

    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            let account = accountContext.account
            _AddressLineContent(
                accountId: account.id,
                isTemporary: account.isTemporary == true,
                addressLine: account.addressLine,
                nft: accountContext.nft
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
        .animation(.smooth.delay(0.18), value: isTemporary)
    }
}
