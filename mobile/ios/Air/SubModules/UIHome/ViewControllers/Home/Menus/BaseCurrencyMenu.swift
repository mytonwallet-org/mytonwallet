//
//  CurrencyMenu.swift
//  MyTonWalletAir
//
//  Created by nikstar on 12.09.2025.
//

import Dependencies
import ContextMenuKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

@MainActor func makeBaseCurrencyMenuConfig(accountId: String) -> () -> ContextMenuConfiguration {
    return {
        @Dependency(\.balanceDataStore) var balanceDataStore
        let amountUsd = balanceDataStore.balanceTotals(accountId: accountId)?.totalBalanceUsd ?? 0

        let items: [ContextMenuItem] = MBaseCurrency.allCases.map { bc in
            let exchangeRate = TokenStore.getCurrencyRate(bc)
            let amount = BaseCurrencyAmount.fromDouble(amountUsd * exchangeRate, bc)

            return .custom(
                .swiftUI(
                    sizing: .fixed(height: 58.0),
                    interaction: .selectable(handler: {
                        Task {
                            do {
                                try await TokenStore.setBaseCurrency(currency: bc)
                            } catch {
                            }
                        }
                    })
                ) { _ in
                    BaseCurrencyMenuRowView(
                        title: bc.name,
                        subtitle: amount.formatted(.baseCurrencyEquivalent),
                        isSelected: bc == TokenStore.baseCurrency
                    )
                }
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(
                minWidth: 250.0,
                maxWidth: 280.0,
                sourceSpacing: 0.0
            )
        )
    }
}

private struct BaseCurrencyMenuRowView: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8.0) {
            Image(systemName: "checkmark")
                .font(.system(size: 15.0, weight: .semibold))
                .opacity(isSelected ? 1.0 : 0.0)
                .frame(width: 32.0)

            VStack(alignment: .leading, spacing: 2.0) {
                Text(title)
                    .font(.system(size: 17.0))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15.0))
                    .padding(.bottom, 1.0)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.air.primaryLabel)
        .padding(.leading, 20.0)
        .padding(.trailing, 18.0)
        .padding(.vertical, 10.0)
    }
}
