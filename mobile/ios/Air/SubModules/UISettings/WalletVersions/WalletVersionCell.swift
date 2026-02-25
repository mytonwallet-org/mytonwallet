//
//  WalletVersionCell.swift
//  UISettings
//

import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct WalletVersionCell: View {

    var title: String
    var subtitle: String
    var value: String?
    var isCurrent: Bool
    var showArrow: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font17h22()
                Text(subtitle)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .offset(y: -1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value, !value.isEmpty {
                Text(value)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            if isCurrent {
                Image.airBundle("AirCheckmark")
                    .foregroundStyle(.tint)
            } else if showArrow {
                Image("RightArrowIcon", bundle: AirBundle)
                    .renderingMode(.template)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
        }
    }
}

extension WalletVersionCell {
    static func makeCurrentVersionRegistration(
        walletVersionsData: MWalletVersionsData?,
        account: MAccount?
    ) -> UICollectionView.CellRegistration<UICollectionViewListCell, Void> {
        UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletVersionCell(
                        title: walletVersionsData?.currentVersion ?? "",
                        subtitle: formatStartEndAddress(account?.getAddress(chain: .ton) ?? ""),
                        value: nil,
                        isCurrent: true,
                        showArrow: false
                    )
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.all, EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 18))
                .minSize(height: 62)
            }
        }
    }

    static func makeOtherVersionRegistration(
        versions: [MWalletVersionsData.Version]
    ) -> UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, versionId in
            guard let version = versions.first(where: { $0.version == versionId }) else { return }
            let value: String
            if let balance = MTokenBalance(tokenSlug: "toncoin", balance: version.balance, isStaking: false).toBaseCurrency {
                let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(balance, TokenStore.baseCurrency)
                value = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
            } else {
                value = ""
            }
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletVersionCell(
                        title: version.version,
                        subtitle: formatStartEndAddress(version.address),
                        value: value,
                        isCurrent: false,
                        showArrow: true
                    )
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.all, EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 18))
                .minSize(height: 62)
            }
        }
    }
}
