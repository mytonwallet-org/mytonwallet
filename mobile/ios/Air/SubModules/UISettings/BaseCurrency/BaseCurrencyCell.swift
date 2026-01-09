//
//  BaseCurrencyCell.swift
//  UISettings
//

import SwiftUI
import UIComponents
import WalletCore

struct BaseCurrencyCell: View {

    var currency: MBaseCurrency
    var isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.symbol)
                    .font17h22()
                Text(currency.name)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .offset(y: -1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Image.airBundle("AirCheckmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}

extension BaseCurrencyCell {
    static func makeRegistration(currentCurrency: MBaseCurrency) -> UICollectionView.CellRegistration<UICollectionViewListCell, MBaseCurrency> {
        UICollectionView.CellRegistration<UICollectionViewListCell, MBaseCurrency> { cell, _, currency in
            let isCurrent = currentCurrency == currency
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    BaseCurrencyCell(currency: currency, isCurrent: isCurrent)
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
