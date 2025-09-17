//
//  CurrencyMenu.swift
//  MyTonWalletAir
//
//  Created by nikstar on 12.09.2025.
//

import SwiftUI
import Popovers
import UIComponents
import WalletContext
import WalletCore

struct CurrencyMenu: View {
    
    @EnvironmentObject private var menuContext: MenuContext
    
    var body: some View {
        ScrollableMenuContent {
            DividedVStack {
                let amountBc = BalanceStore.currentAccountBalanceData?.totalBalance ?? 0
                let exchangeRate1 = TokenStore.getCurrencyRate(TokenStore.baseCurrency ?? .USD)
                let amountUsd = amountBc / exchangeRate1
                
                ForEach(MBaseCurrency.allCases) { bc in
                    let exchangeRate = TokenStore.getCurrencyRate(bc)
                    let a = amountUsd * exchangeRate
                    let amount = BaseCurrencyAmount.fromDouble(a, bc)
                    
                    SelectableMenuItem(id: bc.rawValue, action: {
                        Task {
                            do {
                                try await TokenStore.setBaseCurrency(currency: bc)
                            } catch {
                            }
                        }
                        menuContext.dismiss()
                        
                    }, content: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bc.name)
                                    .font(.system(size: 17))
                                Text(amount.formatted())
                                    .font(.system(size: 15))
                                    .padding(.bottom, 1)
                                    .foregroundStyle(Color(WTheme.secondaryLabel))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if bc == TokenStore.baseCurrency {
                                Image.airBundle("BaseCurrencyCheckmark")
                            }
                        }
                        .foregroundStyle(Color(WTheme.primaryLabel))
                        .padding(EdgeInsets(top: -3, leading: 0, bottom: -3, trailing: 0))
                    })
                }
            }
        }
    }
}
