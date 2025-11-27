//
//  WalletSettingsListCell.swift
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

struct WalletSettingsListCell: View {
    
    let viewModel: WalletSettingsItemViewModel
    var isReordering: Bool
    
    @State private var _isReordering = false
    
    private let avatarSize: CGFloat = 40
    
    var body: some View {
        WithPerceptionTracking {
            HStack(alignment: .center, spacing: 12) {
                selectionCircle
                    .frame(width: avatarSize, height: avatarSize)
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(viewModel.account.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                                .allowsTightening(true)
                                .foregroundStyle(Color.air.primaryLabel)
                                .layoutPriority(1)
                            CardMiniature(viewModel: viewModel.cardProvider)
                        }
                         ListAddressLine(addressLine: viewModel.account.addressLine)
                            .lineLimit(1)
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if _isReordering {
                        Image(systemName: "line.horizontal.3")
                            .foregroundStyle(.secondary)
                            .opacity(0.5)
                            .transition(.opacity.combined(with: .offset(x: 12)).combined(with: .scale(scale: 0.9)))
                    } else {
                        ListBalanceView(viewModel: viewModel)
                            .fixedSize()
                            .transition(.opacity.combined(with: .offset(x: -16)))
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
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
        AccountIcon(account: viewModel.account)
            .overlay {
                if viewModel.isCurrent {
                    Circle()
                        .strokeBorder(lineWidth: borderWidth)
                        .blendMode(.destinationOut)
                }
            }
            .background {
                if viewModel.isCurrent {
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
    
    var viewModel: WalletSettingsItemViewModel
    @State private var cols = (6...12).randomElement()!
    
    var body: some View {
        WithPerceptionTracking {
            if let balance = viewModel.balance {
                Text(balance.formatted(roundUp: true))
                    .lineLimit(1)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .font(.system(size: 16, weight: .regular))
                    .sensitiveDataInPlace(cols: cols, rows: 2, cellSize: 8, theme: .adaptive, cornerRadius: 4)
            }
        }
    }
}

extension WalletSettingsListCell {
    static func makeRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, accountId in
            let viewModel = WalletSettingsItemViewModel(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletSettingsListCell(viewModel: viewModel, isReordering: state.isEditing)
                }
                .background {
                    CellBaclgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 12)
                .margins(.vertical, 10)
            }
        }
    }
}

private struct ListAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    
    var body: some View {
        MtwCardAddressLine(addressLine: addressLine, style: .list)
    }
}
