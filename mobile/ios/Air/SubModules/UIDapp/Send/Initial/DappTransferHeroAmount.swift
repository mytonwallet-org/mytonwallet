import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct DappTransferHeroAmount: View {
    var amount: BaseCurrencyAmount

    var body: some View {
        AmountText(
            amount: amount,
            format: .init(preset: .baseCurrencyEquivalent, roundHalfUp: false, zeroCountSubscriptMinCount: 6),
            integerFont: .compactRounded(ofSize: 34, weight: .bold),
            fractionFont: .compactRounded(ofSize: 28, weight: .bold),
            symbolFont: .compactRounded(ofSize: 31, weight: .bold),
            integerColor: .label,
            fractionColor: .air.secondaryLabel,
            symbolColor: .air.secondaryLabel,
            forceSymbolColor: true
        )
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .heroSensitiveData()
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

func dappTransferHeroAmount(
    _ info: ApiUpdate.DappSendTransactions.CombinedInfo,
    tokensBySlug: [String: ApiToken],
    baseCurrency: MBaseCurrency,
    currencyRate: Double
) -> BaseCurrencyAmount? {
    let locale = Locale(identifier: "en_US_POSIX")
    var totalUsd = Decimal.zero
    for slug in info.tokenOrder {
        // pTON repeats the Toncoin already included in the attached native amount.
        guard slug != "ton-eqcm3b12qk",
              let amount = info.tokenTotals[slug],
              let token = tokensBySlug[slug],
              let priceUsd = token.priceUsd else { continue }
        guard priceUsd.isFinite,
              let price = Decimal(string: String(priceUsd), locale: locale),
              let tokenAmount = Decimal(string: bigIntToDoubleString(amount, decimals: token.decimals), locale: locale) else { return nil }
        totalUsd += tokenAmount * price
    }

    guard !totalUsd.isNaN, totalUsd > Decimal(0.5),
          currencyRate > 0, currencyRate.isFinite,
          let rate = Decimal(string: String(currencyRate), locale: locale) else { return nil }
    let total = totalUsd * rate
    guard !total.isNaN else { return nil }
    return BaseCurrencyAmount(normalizedAmountValue(NSDecimalNumber(decimal: total).stringValue, digits: baseCurrency.decimals), baseCurrency)
}
