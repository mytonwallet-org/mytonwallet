#if DEBUG
// Pre-migration SwiftUI reference for the Home Card Content Lab.
//
//  HomeCard.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import Foundation
import UIKit
import ContextMenuKit
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
    @AppStorage(WalletCardSettings.topLineUserDefaultsKey)
    private var cardTopLineRawValue = WalletCardTopLine.defaultValue.rawValue
    
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

                Group {
                    if showsWalletName {
                        _WalletTitleLine(accountContext: accountContext)
                    } else {
                        _AddressLine(accountContext: accountContext)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                SeasonalOverlay(seasonalTheme: headerViewModel.seasonalTheme)
            }
            .overlay(alignment: .topTrailing) {
                HomeCardPromotionHitArea(
                    promotion: accountContext.activePromotion,
                    cardSize: CGSize(width: layout.itemWidth, height: layout.itemHeight)
                )
            }
            .opacity(headerViewModel.cardOpacity)
        }
    }
    
    var targetBottomPadding: CGFloat {
        -16 + (IOS_26_MODE_ENABLED ? -3 : -14)
    }

    var balanceScale: CGFloat { interpolate(from: 1, to: 17.0/40.0, progress: progress) }
    var bottomPadding: CGFloat { interpolate(from: 0, to: targetBottomPadding, progress: progress) }

    private var showsWalletName: Bool {
        guard headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs else { return false }
        let topLine = WalletCardTopLine(rawValue: cardTopLineRawValue) ?? .defaultValue
        return topLine == .walletName
    }
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
                
                _BalanceChange(
                    accountContext: accountContext,
                    style: .card
                )
            }
            .offset(y: -5)
        }
    }
}

private struct _BalanceView: View {

    let accountContext: AccountContext
    let layout: HomeCardLayoutMetrics
    let minimumHomeCardFontScale: CGFloat
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden

    var body: some View {
        WithPerceptionTracking {
            _BalanceViewContent(
                accountId: accountContext.accountId,
                balance: accountContext.balance,
                nft: accountContext.nft,
                isCurrent: accountContext.isCurrent,
                cardWidth: layout.itemWidth,
                minimumHomeCardFontScale: minimumHomeCardFontScale,
                isSensitiveDataHidden: isSensitiveDataHidden
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
    var isSensitiveDataHidden: Bool
    
    var body: some View {
        let style = MtwCardBalanceView.Style.homeCard(
            cardWidth: cardWidth,
            minimumScale: minimumHomeCardFontScale
        )
        MtwCardBalanceView(
            balance: balance,
            isNumericTranstionEnabled: isCurrent,
            style: style,
            secondaryOpacity: nft?.metadata?.mtwCardType?.isPremium == true ? 1 : 0.75,
            onSensitiveDataReveal: {
                AppActions.setSensitiveDataIsHidden(false)
            }
        )
            .padding(40)
            .sourceAtop {
                MtwCardBalanceGradient(nft: nft)
            }
            .padding(-40)
            .overlay {
                HomeCardBalanceRevealHint(
                    style: style,
                    isVisible: isSensitiveDataHidden
                )
            }
            .homeCardBalanceInteractions(
                accountId: accountId,
                isSensitiveDataHidden: isSensitiveDataHidden
            )
            .backportGeometryGroup()
    }
}

struct HomeCardBalanceRevealHint: View {
    let style: MtwCardBalanceView.Style
    let isVisible: Bool

    var body: some View {
        let size = style.sensitiveDataCellSize * 1.5
        Image.airBundle("HomeHide")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color(style.sensitiveDataTheme.color))
            .opacity(isVisible ? 0.5 : 0)
            .animation(.default, value: isVisible)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

extension View {
    func homeCardBalanceInteractions(
        accountId: String,
        isSensitiveDataHidden: Bool
    ) -> some View {
        gesture(
            TapGesture().onEnded {
                AppActions.setSensitiveDataIsHidden(true)
            },
            isEnabled: !isSensitiveDataHidden
        )
        .contextMenuSource(
            isEnabled: !isSensitiveDataHidden,
            triggers: .longPress,
            configuration: makeBaseCurrencyMenuConfig(accountId: accountId)
        )
    }
}

struct _BalanceChange: View {

    enum Style {
        case card
        case plainBackground
    }

    let accountContext: AccountContext
    var style: Style = .card

    var body: some View {
        WithPerceptionTracking {
            _BalanceChangeContent(
                balance: accountContext.balance,
                balance24h: accountContext.balance24h,
                balanceChange: accountContext.balanceChange,
                nft: accountContext.nft,
                style: style,
                onTap: {
                    AppActions.showPortfolio(accountContext: accountContext)
                }
            )
        }
    }
}

private struct _BalanceChangeContent: View, Equatable {
    let text: String?
    let nft: ApiNft?
    let isPositive: Bool
    let style: _BalanceChange.Style
    let onTap: () -> Void
    
    init(
        balance: BaseCurrencyAmount?,
        balance24h: BaseCurrencyAmount?,
        balanceChange: Double?,
        nft: ApiNft?,
        style: _BalanceChange.Style,
        onTap: @escaping () -> Void
    ) {
        self.text = Self.makeText(balance: balance, balance24h: balance24h, balanceChange: balanceChange)
        self.nft = nft
        self.style = style
        self.onTap = onTap
        if let balance, let balance24h, balance.amount > 0, balance24h.amount > 0 {
            self.isPositive = balance.amount > balance24h.amount
        } else {
            self.isPositive = false
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.nft == rhs.nft && lhs.isPositive == rhs.isPositive && lhs.style == rhs.style
    }

    var body: some View {
        ZStack {
            if let text, !text.isEmpty {
                mainView(text)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if text == nil {
                placeholderView()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .backportGeometryGroup()
        .animation(.easeOut(duration: 0.25), value: text?.isEmpty)
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
        let (textColor, bgColor) = colors
        return Button(action: onTap) {
            HStack(spacing: 4) {
                Text(text)
                    .environment(\.layoutDirection, .leftToRight)
                    .offset(y: -0.5) // Optically center the compact font in the pill.
                Image(systemName: "chevron.forward")
                    .textStyle(.caption2Strong, content: .technical)
            }
            .font(.compactDisplay(size: 17, weight: .medium))
            .foregroundStyle(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .background {
                ZStack {
                    BackgroundBlur(radius: 12)
                    Capsule().fill(bgColor)
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
            theme: sensitiveDataTheme,
            cornerRadius: 13
        )
    }

    private var sensitiveDataTheme: ShyMask.Theme {
        switch style {
        case .card:
            .color(UIColor(getSecondaryForegroundColor(nft: nft)))
        case .plainBackground:
            .adaptive
        }
    }

    private var colors: (foreground: Color, background: Color) {
        switch style {
        case .card:
            let usesPositiveColor = isPositive && nft == nil
            let baseColor = usesPositiveColor ? Color.air.positiveBalance : getSecondaryForegroundColor(nft: nft)
            return (
                usesPositiveColor ? baseColor : baseColor.opacity(0.8),
                baseColor.opacity(usesPositiveColor ? 0.16 : 0.10)
            )
        case .plainBackground:
            let baseColor = isPositive ? Color(UIColor(hex: "#34C759")) : Color.air.secondaryLabel
            return (baseColor, baseColor.opacity(0.10))
        }
    }
    
    private func placeholderView() -> some View {
        Capsule()
            .fill((style == .card ? Color.white : Color(uiColor: .label)).opacity(0.06))
            .frame(width: 76, height: 26)
            .accessibilityHidden(true)
    }
}

private struct _WalletTitleLine: View {

    let accountContext: AccountContext
    var snapshot: MtwCardContentData? = nil

    @Namespace private var ns

    var body: some View {
        WithPerceptionTracking {
            let account = snapshot?.account ?? accountContext.account
            let addressLine = snapshot?.addressLine ?? accountContext.addressLine
            let nft = snapshot == nil ? accountContext.nft : snapshot?.nft
            let isTemporary = account.isTemporary == true
            let increasedBadgeOpacity = nft?.metadata?.mtwCardType?.isPremium == true

            HStack(spacing: 8) {
                if isTemporary {
                    AddViewButton(
                        accountId: account.id,
                        foregroundStyle: getSecondaryForegroundColor(nft: nft)
                    )
                    .padding(.vertical, -6)
                }

                HStack(spacing: MtwCardAddressLine.Style.homeCard.accountTypeIconSpacing) {
                    if addressLine.isTestnet {
                        addressLine.testnetImage
                            .sourceAtop {
                                MtwCardCenteredGradient(nft: nft)
                                    .matchedGeometryEffect(id: "walletTitle", in: ns, isSource: false)
                            }
                    }

                    Group {
                        if let leadingIcon = addressLine.leadingIcon {
                            switch leadingIcon {
                            case .ledger:
                                AccountTypeBadge(.hardware, increasedOpacity: increasedBadgeOpacity)
                            case .view:
                                AccountTypeBadge(.view, increasedOpacity: increasedBadgeOpacity)
                            }
                        }
                    }
                    .sourceAtop {
                        MtwCardCenteredGradient(nft: nft)
                            .matchedGeometryEffect(id: "walletTitle", in: ns, isSource: false)
                    }
                    .background {
                        if addressLine.leadingIcon == .view {
                            BackgroundBlur(radius: 12)
                                .clipShape(.rect(cornerRadius: viewBadgeCornerRadius))
                                .padding(.vertical, -viewBadgeVerticalPadding)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(account.displayName)
                            .lineLimit(1)

                        Image.airBundle("QRIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    .opacity(MtwCardAddressLine.Style.homeCard.textOpacity)
                    .sourceAtop {
                        MtwCardCenteredGradient(nft: nft)
                            .matchedGeometryEffect(id: "walletTitle", in: ns, isSource: false)
                    }
                }
                .textStyle(.bodyStrong)
                .background {
                    Color.clear.matchedGeometryEffect(id: "walletTitle", in: ns, isSource: true)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .contextMenuSource(
                    triggers: [.tap],
                    configuration: makeAddressesMenuConfig(accountContext: accountContext)
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(account.displayName)
                .accessibilityHint(lang("Open addresses"))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 6)
            .animation(.smooth.delay(0.18), value: isTemporary)
        }
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
                addressLine: accountContext.addressLine,
                accountContext: accountContext,
                nft: accountContext.nft
            )
        }
    }
}

private struct _AddressLineContent: View {

    var accountId: String
    var isTemporary: Bool
    var addressLine: MAccount.AddressLine
    var accountContext: AccountContext
    var nft: ApiNft?
    
    var body: some View {
        HStack(spacing: 8) {
            if isTemporary {
                AddViewButton(accountId: accountId, foregroundStyle: getSecondaryForegroundColor(nft: nft))
                    .padding(.vertical, -6)
            }
            MtwCardAddressLine(addressLine: addressLine, style: .homeCard, gradient: MtwCardCenteredGradient(nft: nft))
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .contextMenuSource(
                    triggers: [.tap],
                    configuration: makeAddressesMenuConfig(accountContext: accountContext)
                )
                .padding(.trailing, -8)
                .backportGeometryGroup()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 9)
        .animation(.smooth.delay(0.18), value: isTemporary)
    }
}

@Perceptible @MainActor
public final class HomeCardContentReferenceModel {
    public var data: MtwCardContentData
    public var collapsed = false
    public var progress: CGFloat = 0
    public var topTabs = false
    public var cardWidth: CGFloat = 358
    public var minimumFontScale: CGFloat = 1
    public var sensitiveDataHidden = false
    public var isRTL = false
    public var freezesAnimations = false
    let context: AccountContext

    public init(data: MtwCardContentData) {
        self.data = data
        context = AccountContext(source: .constant(data.account))
    }

    public func makeView() -> UIView {
        let view = HostingView { [self] in
            WithPerceptionTracking {
                HomeCardContentReference(model: self)
                    .environment(\.layoutDirection, self.isRTL ? .rightToLeft : .leftToRight)
                    .transaction { if self.freezesAnimations { $0.animation = nil; $0.disablesAnimations = true } }
            }
        }
        view.translatesAutoresizingMaskIntoConstraints = true
        view.isUserInteractionEnabled = false
        return view
    }
}

private struct HomeCardContentReference: View {
    let model: HomeCardContentReferenceModel

    var body: some View {
        WithPerceptionTracking {
            let data = model.data
            if model.collapsed {
                let style: MtwCardBalanceView.Style = model.topTabs ? .homeNavigationBarCollapsed : .homeCollaped
                VStack(spacing: model.topTabs ? 6 : interpolate(from: 5, to: -2, progress: model.progress)) {
                    MtwCardBalanceView(balance: data.balance, style: style)
                        .modifier(HomeCardReferencePrivacy(hidden: model.sensitiveDataHidden && data.balance != nil, cellSize: style.sensitiveDataCellSize, theme: style.sensitiveDataTheme))
                        .overlay { HomeCardBalanceRevealHint(style: style, isVisible: model.sensitiveDataHidden) }
                        .scaleEffect(model.topTabs ? 1 : interpolate(from: 1, to: 17.0 / 40, progress: model.progress), anchor: .bottom)
                    if model.topTabs {
                        change(style: .plainBackground)
                    } else {
                        HStack(spacing: 4) {
                            if data.account.isView {
                                Image.airBundle("inline_view").imageScale(.small)
                            }
                            Text(data.account.displayName).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .textStyle(.body)
                        .scaleEffect(interpolate(from: 1, to: 13.0 / 17, progress: model.progress), anchor: .top)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, model.topTabs ? 24 : interpolate(from: 12, to: 16 + (IOS_26_MODE_ENABLED ? -3 : -14), progress: model.progress))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                ZStack {
                    VStack(spacing: 5) {
                        expandedBalance(data)
                            .padding(.leading, 1)
                            .padding(.horizontal, 32)
                        change(style: .card)
                    }
                    .offset(y: -5)
                    .scaleEffect(interpolate(from: 1, to: 17.0 / 40, progress: model.progress))
                    .backportGeometryGroup()
                    .offset(y: -interpolate(from: 0, to: -16 + (IOS_26_MODE_ENABLED ? -3 : -14), progress: model.progress))
                    Group {
                        if data.showsWalletName {
                            _WalletTitleLine(accountContext: model.context, snapshot: data)
                        } else {
                            _AddressLineContent(accountId: data.account.id, isTemporary: data.account.isTemporary == true,
                                                addressLine: data.addressLine, accountContext: model.context, nft: data.nft)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { SeasonalOverlay(seasonalTheme: data.seasonalTheme) }
            }
        }
    }

    @ViewBuilder
    private func expandedBalance(_ data: MtwCardContentData) -> some View {
        if model.sensitiveDataHidden, data.balance != nil {
            let style = MtwCardBalanceView.Style.homeCard(cardWidth: model.cardWidth, minimumScale: model.minimumFontScale)
            MtwCardBalanceView(balance: data.balance, style: style)
                .modifier(HomeCardReferencePrivacy(hidden: true, cellSize: style.sensitiveDataCellSize, theme: style.sensitiveDataTheme))
                .sourceAtop { MtwCardBalanceGradient(nft: data.nft).padding(-40) }
                .overlay { HomeCardBalanceRevealHint(style: style, isVisible: true) }
        } else {
            _BalanceViewContent(accountId: data.account.id, balance: data.balance, nft: data.nft, isCurrent: false,
                                cardWidth: model.cardWidth, minimumHomeCardFontScale: model.minimumFontScale,
                                isSensitiveDataHidden: false)
        }
    }

    private func change(style: _BalanceChange.Style) -> some View {
        _BalanceChangeContent(balance: model.data.balance, balance24h: model.data.previousBalance,
                              balanceChange: model.data.balanceChange, nft: model.data.nft, style: style, onTap: {})
            .modifier(HomeCardReferencePrivacy(hidden: model.sensitiveDataHidden && MtwCardChangeView.text(balance: model.data.balance, previous: model.data.previousBalance, percent: model.data.balanceChange)?.isEmpty == false,
                                               cols: 10, rows: 2, cellSize: 13,
                                               theme: style == .card ? .color(UIColor(getSecondaryForegroundColor(nft: model.data.nft))) : .adaptive,
                                               radius: 13))
    }
}

private struct HomeCardReferencePrivacy: ViewModifier {
    var hidden: Bool
    var cols = 14
    var rows = 3
    var cellSize: CGFloat
    var theme: ShyMask.Theme
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content.opacity(hidden ? 0 : 1).overlay {
            if hidden {
                WUIShyMask(cols: cols, rows: rows, cellSize: cellSize, theme: theme)
                    .fixedSize().clipShape(.rect(cornerRadius: radius))
            }
        }
    }
}
#endif
