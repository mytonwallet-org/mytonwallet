//
//  AccountListCell.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
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
    
    @State private var _isReordering = false
    
    public init(accountContext: AccountContext, isReordering: Bool, showCurrentAccountHighlight: Bool, showBalance: Bool = true) {
        self.accountContext = accountContext
        self.isReordering = isReordering
        self.showCurrentAccountHighlight = showCurrentAccountHighlight
        self.showBalance = showBalance
    }
    
    public var body: some View {
        WithPerceptionTracking {
            HStack(alignment: .center, spacing: 10) {
                selectionCircle
                    .frame(width: avatarSize, height: avatarSize)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(accountContext.account.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                                .allowsTightening(true)
                                .foregroundStyle(Color.air.primaryLabel)
                                .layoutPriority(1)
                            CardMiniature(accountContext: accountContext)
                        }
                        .frame(height: 22)
                        ListAddressLine(addressLine: accountContext.account.addressLine)
                            .lineLimit(1)
                            .foregroundStyle(Color.air.secondaryLabel)
                            .frame(height: 18)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if _isReordering {
                        Image(systemName: "line.horizontal.3")
                            .foregroundStyle(.secondary)
                            .opacity(0.5)
                            .transition(.opacity.combined(with: .offset(x: 12)).combined(with: .scale(scale: 0.9)))
                    } else if showBalance {
                        ListBalanceView(viewModel: accountContext)
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
        }
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
                        .foregroundStyle(Color.air.tint)
                        .padding(-borderWidth)
                }
            }
            .compositingGroup()
    }
}

private struct ListBalanceView: View {
    
    var viewModel: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            if let balance = viewModel.balance {
                Text(balance.formatted(.baseCurrencyEquivalent, roundUp: true))
                    .lineLimit(1)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .font(.system(size: 16, weight: .regular))
                    .sensitiveDataInPlace(cols: cols, rows: 2, cellSize: 8, theme: .adaptive, cornerRadius: 4)
            }
        }
    }
    
    var cols: Int { 6 + (abs(viewModel.accountId.hashValue) % 6) }
}

private struct ListAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    
    var body: some View {
        MtwCardAddressLine(addressLine: addressLine, style: .list, gradient: nil)
    }
}

public extension AccountListCell {
    static func makeRegistration(showBalance: Bool = true, normalBackground: Color = .air.groupedItem, showCurrentAccountHighlight: Bool = true) -> UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    AccountListCell(
                        accountContext: accountContext,
                        isReordering: state.isEditing,
                        showCurrentAccountHighlight: showCurrentAccountHighlight,
                        showBalance: showBalance
                    )
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted, isSwiped: state.isSwiped, normalColor: normalBackground)
                        .id(accountContext.account.id) // reset on cell reuse
                }
                .margins(.horizontal, 12)
                .margins(.vertical, 10)
            }
        }
    }
}
