
import Foundation
import SwiftUI
import WalletCore
import WalletContext
import UIComponents

public struct TotalAmountRow: View {
    
    var info: ApiUpdate.DappSendTransactions.CombinedInfo
    
    var amountInBaseCurrency: BaseCurrencyAmount {
        let baseCurrency = TokenStore.baseCurrency
        var total: BigInt = 0
        for tokenSlug in info.tokenOrder {
            guard let amount = info.tokenTotals[tokenSlug] else { continue }
            if let token = TokenStore.getToken(slug: tokenSlug) {
                total += convertAmount(amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimals)
            }
        }
        return BaseCurrencyAmount(total, baseCurrency)
    }
    
    var amountTerms: [String] {
        var terms: [String] = []

        if info.nftsCount > 0 {
            let nftLabel = info.nftsCount == 1 ? "1 NFT" : "\(info.nftsCount) NFTs"
            terms.append(nftLabel)
        }

        for tokenSlug in info.tokenOrder {
            guard let amount = info.tokenTotals[tokenSlug] else { continue }
            if let token = TokenStore.getToken(slug: tokenSlug) {
                terms.append(TokenAmount(amount, token).formatted(.defaultAdaptive))
            } else {
                terms.append(AnyDecimalAmount(amount, decimals: 9, symbol: "[Unknown]", forceCurrencyToRight: true).formatted(.defaultAdaptive))
            }
        }

        return terms
    }

    var summaryText: String {
        let amounts = amountTerms.joined(separator: " + ")

        if info.tokenTotals.isEmpty {
            return amounts
        }

        let baseCurrencyEquivalent = amountInBaseCurrency.formatted(.baseCurrencyEquivalent)
        if amounts.isEmpty {
            return baseCurrencyEquivalent
        }

        return "\(amounts) (\(baseCurrencyEquivalent))"
    }
    
    public var body: some View {
        InsetCell {
            Text(summaryText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
        }
    }
}
