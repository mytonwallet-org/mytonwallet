
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TransactionAmountRow: View {
    
    var transfer: ApiDappTransfer
    var chain: ApiChain
    
    private var transferToken: ApiToken { transfer.getToken(chain: chain) }
    private var displayedAmounts: [TokenAmount] { transfer.displayedAmounts(chain: chain, includeNativeFee: false) }
    
    private var totalBaseCurrencyAmount: BaseCurrencyAmount? {
        let baseCurrency = TokenStore.baseCurrency
        var total: BigInt = 0
        var hasVisibleAmount = false

        for amount in displayedAmounts {
            guard let price = amount.type.price else { continue }
            total += convertAmount(
                amount.amount,
                price: price,
                tokenDecimals: amount.decimals,
                baseCurrencyDecimals: baseCurrency.decimals
            )
            hasVisibleAmount = true
        }

        guard hasVisibleAmount else { return nil }
        return BaseCurrencyAmount(total, baseCurrency)
    }
    
    var body: some View {
        InsetCell(verticalPadding: 0) {
            HStack(spacing: 16) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    text
                    subtitle
                }
                Spacer()
            }
            .foregroundStyle(Color.air.primaryLabel)
            .frame(minHeight: 60)
        }
    }
    
    @ViewBuilder
    var icon: some View {
        WUIIconViewToken(
            token: transferToken,
            isWalletView: false,
            showldShowChain: true,
            size: 40,
            chainSize: 16,
            chainBorderWidth: 1.333,
            chainBorderColor: .air.groupedItem,
            chainHorizontalOffset: 2,
            chainVerticalOffset: 1
        )
        .frame(width: 40, height: 40, alignment: .leading)
    }
    
    @ViewBuilder
    var text: some View {
        Text(displayedAmounts
            .map { $0.formatted(.defaultAdaptive, maxDecimals: 4) }
            .joined(separator: " + ")
        )
        .font(.system(size: 16, weight: .medium))
    }
    
    @ViewBuilder
    var subtitle: some View {
        if let totalBaseCurrencyAmount {
            Text(totalBaseCurrencyAmount.formatted(.baseCurrencyEquivalent))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.air.secondaryLabel)
        }
    }
}
