//
//  CurrencyMenu.swift
//  MyTonWalletAir
//
//  Created by nikstar on 12.09.2025.
//

import Dependencies
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

func makeBaseCurrencyMenuConfig(accountId: String) -> () -> MenuConfig {
    return {
        @Dependency(\.balanceStore) var balanceStore
        let amountUsd = balanceStore.accountBalanceData[accountId]?.totalBalanceUsd ?? 0

        let items: [MenuItem] = MBaseCurrency.allCases.map { bc in
            MenuItem.customView(
                id: "0-" + bc.rawValue,
                view: {
                    AnyView(
                        SelectableMenuItem(id: "0-" + bc.rawValue, action: {
                            Task {
                                do {
                                    try await TokenStore.setBaseCurrency(currency: bc)
                                } catch {
                                }
                            }
                        }, content: {
                            let exchangeRate = TokenStore.getCurrencyRate(bc)
                            let a = amountUsd * exchangeRate
                            let amount = BaseCurrencyAmount.fromDouble(a, bc)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bc.name)
                                        .font(.system(size: 17))
                                        .lineLimit(1)
                                    Text(amount.formatted(.baseCurrencyEquivalent))
                                        .font(.system(size: 15))
                                        .padding(.bottom, 1)
                                        .foregroundStyle(Color(WTheme.secondaryLabel))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if bc == TokenStore.baseCurrency {
                                    Image.airBundle("BaseCurrencyCheckmark")
                                }
                            }
                            .foregroundStyle(Color(WTheme.primaryLabel))
                            .padding(EdgeInsets(top: -3, leading: 0, bottom: -3, trailing: 0))
                        })
                    )
                },
                height: 58
            )
        }
        return MenuConfig(menuItems: items)
    }
}
