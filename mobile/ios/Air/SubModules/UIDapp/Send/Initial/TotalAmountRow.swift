
import Foundation
import SwiftUI
import WalletCore
import WalletContext
import UIComponents

public struct TotalAmountRow: View {
    
    var info: MDappSendTransactions.CombinedInfo
    
    var amountInBaseCurrency: BaseCurrencyAmount {
        let baseCurrency = TokenStore.baseCurrency ?? .USD
        var total: BigInt = 0
        for (tokenSlug, amount) in info.tokenTotals {
            if let token = TokenStore.tokens[tokenSlug] {
                total += convertAmount(amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimals)
            }
        }
        return BaseCurrencyAmount(total, baseCurrency)
    }
    
    var tokenAmounts: [TokenAmount] {
        var amounts: [TokenAmount] = []
        for (tokenSlug, amount) in info.tokenTotals {
            if let token = TokenStore.tokens[tokenSlug] {
                amounts.append(TokenAmount(amount, token))
            }
        }
        return amounts
    }
    
    public var body: some View {
        InsetCell {
            text
                .padding(.vertical, 3)
        }
    }
    
    @ViewBuilder
    var text: some View {
        let bc = Text(
            amountInBaseCurrency.formatAttributed(
                format: .init(),
                integerFont: .systemFont(ofSize: 24, weight: .semibold),
                fractionFont: .systemFont(ofSize: 20, weight: .semibold),
                symbolFont: .systemFont(ofSize: 20, weight: .semibold),
                integerColor: WTheme.primaryLabel,
                fractionColor: WTheme.primaryLabel,
                symbolColor: WTheme.secondaryLabel,
                forceSymbolColor: true,
            )
        )
        if !tokenAmounts.isEmpty {
            let _tokens = tokenAmounts
                .map { tokenAmount in
                    tokenAmount.formatted()
                }
                .joined(separator: " + ")
            let tokens = Text(_tokens)
            Text("\(bc) (\(tokens))")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(WTheme.secondaryLabel))
        } else {
            bc
        }
    }
}
