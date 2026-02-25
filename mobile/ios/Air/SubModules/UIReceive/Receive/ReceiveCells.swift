//
//  ReceiveCells.swift
//  UIReceive
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

struct AddressCell: View {
    let address: String
    let chain: ApiChain

    var body: some View {
        let copy = Text(Image.airBundle("HomeCopy"))
            .baselineOffset(-3)
            .foregroundColor(Color.air.secondaryLabel)
        let addressText = Text(address: address)
        let text = Text("\(addressText) \(copy)")
            .font(.system(size: 17, weight: .regular))
            .lineSpacing(2)
            .multilineTextAlignment(.leading)

        Button {
            AppActions.showToast(animationName: "Copy", message: lang("%chain% Address Copied", arg1: chain.title))
            Haptics.play(.lightTap)
            UIPasteboard.general.string = address
        } label: {
            text
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct BuyCryptoItemCell: View {
    let imageName: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image.airBundle(imageName)
                .frame(width: 30, height: 30)
            Text(title)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)
        }
    }
}

extension AddressCell {
    static func makeRegistration(
        address: String,
        chain: ApiChain
    ) -> UICollectionView.CellRegistration<UICollectionViewListCell, Void> {
        UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                AddressCell(address: address, chain: chain)
            }
            .background {
                Color(WTheme.groupedItem)
            }
            .margins(.horizontal, 16)
            .margins(.vertical, 12)
        }
    }
}

extension BuyCryptoItemCell {
    static func makeRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, ReceiveItem> {
        UICollectionView.CellRegistration<UICollectionViewListCell, ReceiveItem> { cell, _, item in
            let (imageName, title) = item.displayInfo
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    BuyCryptoItemCell(imageName: imageName, title: title)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 0)
                .minSize(height: S.sectionItemHeight)
            }
        }
    }
}

enum ReceiveItem: Hashable {
    case address
    case buyWithCard
    case buyWithCrypto
    case depositLink

    var displayInfo: (imageName: String, title: String) {
        switch self {
        case .address:
            ("", "")
        case .buyWithCard:
            ("CardIcon", lang("Buy with Card"))
        case .buyWithCrypto:
            ("CryptoIcon", lang("Buy with Crypto"))
        case .depositLink:
            ("AssetsAndActivityIcon", lang("Create Deposit Link"))
        }
    }
}
