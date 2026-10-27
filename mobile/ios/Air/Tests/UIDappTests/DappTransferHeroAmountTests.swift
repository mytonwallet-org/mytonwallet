import Testing
@testable import UIDapp
import WalletContext
@testable import WalletCore

@Suite("Dapp transfer hero amount")
struct DappTransferHeroAmountTests {
    private let nativeToken = ApiToken(slug: TONCOIN_SLUG, name: "Toncoin", symbol: "TON", decimals: 9, chain: .ton, priceUsd: 1)

    @Test(arguments: [499_999_999, 500_000_000, 500_000_001])
    func thresholdUsesUnroundedUsdTotalIncludingFees(total: Int) {
        let request = request([transfer(amount: BigInt(total) - 10_000_000, fee: 10_000_000)])
        let amount = dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [nativeToken.slug: nativeToken], baseCurrency: .EUR, currencyRate: 0.1)
        #expect((amount != nil) == (total > 500_000_000))
    }

    @Test
    func sumsAllTransfersAndFeesBeforeConvertingCurrency() throws {
        let token = ApiToken(slug: "usdt", name: "Tether", symbol: "USD₮", decimals: 6, chain: .ton, priceUsd: 1)
        let payload = ApiParsedPayload.tokensTransferNonStandard(.init(queryId: 0, amount: 3_000_000, destination: "recipient", slug: token.slug))
        let request = request([
            transfer(amount: 1_000_000_000, fee: 10_000_000),
            transfer(amount: 50_000_000, fee: 10_000_000, payload: payload),
        ])
        let amount = try #require(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [nativeToken.slug: nativeToken, token.slug: token], baseCurrency: .EUR, currencyRate: 0.5))
        #expect(amount.baseCurrency == .EUR)
        #expect(amount.amount == 2_035_000)
    }

    @Test
    func decimalConversionPreservesCentsForTheHero() throws {
        var token = nativeToken
        token.priceUsd = 5
        let request = request([
            transfer(amount: 10_140_000_000, fee: 10_000_000),
            transfer(amount: 50_000_000, fee: 10_000_000),
        ])
        let amount = try #require(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [token.slug: token], baseCurrency: .USD, currencyRate: 1))
        #expect(amount.amount == 51_050_000)
    }

    @Test(arguments: [
        (560_000_000, 5.0, 1.0, 2_850_000, "$2.85"),
        (1_120_000_000, 5.0, 1.0, 5_650_000, "$5.65"),
        (560_000_000, 1.0, 5.0, 2_850_000, "$2.85"),
    ])
    func pricingAndCurrencyConversionPreserveCents(values: (Int, Double, Double, Int, String)) throws {
        let (sent, price, rate, expected, formatted) = values
        var token = nativeToken
        token.priceUsd = price
        let request = request([transfer(amount: BigInt(sent), fee: 10_000_000)])
        let amount = try #require(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [token.slug: token], baseCurrency: .USD, currencyRate: rate))
        #expect(amount.amount == BigInt(expected))
        #expect(amount.formatted(.baseCurrencyEquivalent, roundHalfUp: false) == formatted)
    }

    @Test
    func decimalAccumulationPreservesCentsAcrossTokens() throws {
        let token = ApiToken(slug: "usdt", name: "Tether", symbol: "USD₮", decimals: 6, chain: .ton, priceUsd: 1)
        let payload = ApiParsedPayload.tokensTransferNonStandard(.init(queryId: 0, amount: 50_000, destination: "recipient", slug: token.slug))
        let request = request([transfer(amount: 2_790_000_000, fee: 10_000_000, payload: payload)])
        let amount = try #require(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [nativeToken.slug: nativeToken, token.slug: token], baseCurrency: .USD, currencyRate: 1))
        #expect(amount.amount == 2_850_000)
        #expect(amount.formatted(.baseCurrencyEquivalent, roundHalfUp: false) == "$2.85")
    }

    @Test
    func wrappedTonDoesNotDuplicateTheAttachedNativeAmount() throws {
        let wrapped = ApiToken(slug: "ton-eqcm3b12qk", name: "Wrapped Toncoin", symbol: "pTON", decimals: 9, chain: .ton, priceUsd: 1)
        let payload = ApiParsedPayload.tokensTransferNonStandard(.init(queryId: 0, amount: 1_000_000_000, destination: "recipient", slug: wrapped.slug))
        let request = request([transfer(amount: 1_000_000_000, fee: 10_000_000, payload: payload)])
        let amount = try #require(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [nativeToken.slug: nativeToken, wrapped.slug: wrapped], baseCurrency: .USD, currencyRate: 1))
        #expect(amount.formatted(nil, maxDecimals: 2) == "$1.01")
    }

    @Test
    func unpricedAssetsDoNotInflateTheTotal() {
        let token = ApiToken(slug: "unknown", name: "Unknown", symbol: "???", decimals: 6, chain: .ton)
        let payload = ApiParsedPayload.tokensTransferNonStandard(.init(queryId: 0, amount: 1_000_000_000, destination: "recipient", slug: token.slug))
        let request = request([transfer(amount: 50_000_000, fee: 10_000_000, payload: payload)])
        #expect(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [nativeToken.slug: nativeToken, token.slug: token], baseCurrency: .USD, currencyRate: 1) == nil)
        #expect(dappTransferHeroAmount(request.combinedInfo, tokensBySlug: [:], baseCurrency: .USD, currencyRate: 1) == nil)
    }

    private func request(_ transactions: [ApiDappTransfer]) -> ApiUpdate.DappSendTransactions {
        .init(promiseId: "test", accountId: "test", dapp: .sample, operationChain: .ton, transactions: transactions, emulation: nil, shouldHideTransfers: false)
    }

    private func transfer(amount: BigInt, fee: BigInt, payload: ApiParsedPayload? = nil) -> ApiDappTransfer {
        .init(toAddress: "contract", amount: amount, payload: payload, isDangerous: false, normalizedAddress: "contract", displayedToAddress: "recipient", networkFee: fee)
    }
}
