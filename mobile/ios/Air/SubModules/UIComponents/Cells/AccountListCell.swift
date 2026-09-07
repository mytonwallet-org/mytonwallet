//
//  AccountListCell.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
import ContextMenuKit
import WalletCore
import WalletContext
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import Kingfisher

let borderWidth = 1.5
let avatarSize = 40.0

public struct AccountListCell: View {
    
    let accountContext: AccountContext
    var isReordering: Bool
    var showCurrentAccountHighlight: Bool
    var showBalance: Bool
    var addressLineSuffix: String?
    var isDimmed: Bool
    var showsAddress: Bool
    
    @State private var _isReordering = false
    
    public init(accountContext: AccountContext, isReordering: Bool, showCurrentAccountHighlight: Bool, showBalance: Bool = true, addressLineSuffix: String? = nil, isDimmed: Bool = false, showsAddress: Bool = true) {
        self.accountContext = accountContext
        self.isReordering = isReordering
        self.showCurrentAccountHighlight = showCurrentAccountHighlight
        self.showBalance = showBalance
        self.addressLineSuffix = addressLineSuffix
        self.isDimmed = isDimmed
        self.showsAddress = showsAddress
    }
    
    static let topRowHeight: CGFloat = 22
    static let bottomRowHeight: CGFloat = 18
    public static var contentHeight: CGFloat { topRowHeight + bottomRowHeight }

    public var body: some View {
        WithPerceptionTracking {
            HStack(alignment: .center, spacing: showsAddress ? 10 : 13) {
                selectionCircle
                    .scaleEffect(showsAddress ? 1 : 0.9)
                    .frame(width: showsAddress ? avatarSize : 36, height: showsAddress ? avatarSize : 36)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(accountContext.account.displayName)
                                .textStyle(showsAddress ? .calloutEmphasized : .bodyEmphasized)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .foregroundStyle(Color.air.primaryLabel)
                                .layoutPriority(showsAddress ? 1 : 0)
                            CardMiniature(accountContext: accountContext)
                                .layoutPriority(showsAddress ? 0 : 1)
                            if !showsAddress {
                                accountTypeIcons
                                    .layoutPriority(2)
                            }
                        }
                        .frame(height: Self.topRowHeight)
                        if showsAddress {
                            ListAddressLine(addressLine: accountContext.addressLine, suffix: addressLineSuffix)
                                .lineLimit(1)
                                .foregroundStyle(Color.air.secondaryLabel)
                                .frame(height: Self.bottomRowHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if _isReordering {
                        Image(systemName: "line.horizontal.3")
                            .foregroundStyle(.secondary)
                            .opacity(0.5)
                            .transition(.opacity.combined(with: .offset(x: 12)).combined(with: .scale(scale: 0.9)))
                    } else if showBalance {
                        ListBalanceView(viewModel: accountContext, textStyle: showsAddress ? .callout : .body)
                            .fixedSize()
                            .transition(.opacity.combined(with: .offset(x: -16)))
                            .frame(height: 22)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
            }
            .onAppear {
                _isReordering = isReordering
            }
            .onChange(of: isReordering) { isReordering in
                withAnimation(.snappy) {
                    // animation wasn't happening otherwise
                    _isReordering = isReordering
                }
            }
            .opacity(isDimmed ? 0.5 : 1)
        }
    }

    private var accountTypeIcons: some View {
        HStack(spacing: 4) {
            let addressLine = accountContext.addressLine
            if addressLine.isTestnet {
                addressLine.testnetImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            if let leadingIcon = addressLine.leadingIcon {
                Image.airBundle(leadingIcon == .ledger ? "AccountTypeLedger" : "AccountTypeView")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 8)
            }
        }
        .foregroundStyle(Color.air.secondaryLabel)
        .fixedSize()
        .accessibilityHidden(true)
    }
    
    private var selectionCircle: some View {
        AccountIcon(account: accountContext.account)
            .overlay {
                if showCurrentAccountHighlight && accountContext.isCurrent {
                    Circle()
                        .strokeBorder(lineWidth: borderWidth)
                        .blendMode(.destinationOut)
                }
            }
            .background {
                if showCurrentAccountHighlight && accountContext.isCurrent {
                    Circle()
                        .strokeBorder(lineWidth: borderWidth)
                        .foregroundStyle(.tint)
                        .padding(-borderWidth)
                }
            }
            .compositingGroup()
    }
}

private struct ListBalanceView: View {
    
    var viewModel: AccountContext
    var textStyle: WTextStyle
    
    var body: some View {
        WithPerceptionTracking {
            if let balance = viewModel.balance {
                Text(balance.formatted(.baseCurrencyEquivalent, roundHalfUp: true))
                    .lineLimit(1)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .textStyle(textStyle, content: .technical)
                    .sensitiveDataInPlace(cols: cols, rows: 2, cellSize: 8, theme: .adaptive, cornerRadius: 4)
                    .id(viewModel.accountId)
            }
        }
    }
    
    var cols: Int { 6 + (abs(viewModel.accountId.hashValue) % 6) }
}

private struct ListAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    var suffix: String?
    
    var body: some View {
        let style = MtwCardAddressLine.Style.list
        HStack(spacing: 4) {
            MtwCardAddressLine(addressLine: addressLine, style: style, gradient: nil)
            if let suffix {
                Text("·")
                Text(suffix)
            }
        }
        .font(style.font)
    }
}

public extension AccountListCell {
    @MainActor
    static func makeRegistration(
        showBalance: Bool = true,
        normalBackground: Color = .air.groupedItem,
        showCurrentAccountHighlight: Bool = true,
        showsAddress: Bool = true,
        contextMenuConfigurationProvider: (@MainActor (String) -> ContextMenuConfiguration)? = nil
    ) -> UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    AccountListCell(
                        accountContext: accountContext,
                        isReordering: state.isEditing,
                        showCurrentAccountHighlight: showCurrentAccountHighlight,
                        showBalance: showBalance,
                        showsAddress: showsAddress
                    )
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted, isSwiped: state.isSwiped, normalColor: normalBackground)
                        .id(accountContext.account.id) // reset on cell reuse
                }
                .margins(.leading, showsAddress ? 12 : 13)
                .margins(.trailing, showsAddress ? 12 : 16)
                .margins(.vertical, showsAddress ? 10 : 8)
            }

            if let contextMenuConfigurationProvider {
                let interaction = ContextMenuInteraction(
                    triggers: [.longPress],
                    sourcePortal: ContextMenuSourcePortal(
                        mask: .roundedAttachmentRect(cornerRadius: 26)
                    ),
                    pressAnimation: .default(transformMode: .sublayerTransform)
                ) { _ in
                    contextMenuConfigurationProvider(accountId)
                }
                cell.setAccountContextMenuInteraction(interaction)
            } else {
                cell.setAccountContextMenuInteraction(nil)
            }
        }
    }
}
