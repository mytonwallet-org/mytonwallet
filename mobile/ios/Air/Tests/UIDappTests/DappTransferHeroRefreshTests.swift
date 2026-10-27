import Dependencies
import XCTest
@testable import UIDapp
import WalletContext
@testable import WalletCore
import WalletResources

@MainActor
final class DappTransferHeroRefreshTests: XCTestCase {
    func testOpenConfirmationRefreshesForPricesRatesAndCurrency() async throws {
        _ = WalletResourcesBundle.bundle.load()
        try await withDependencies {
            $0.context = .live
            $0.accountStore = .liveValue
            $0[AccountSettingsStore.self] = .liveValue
            $0[AccountConfigStore.self] = .liveValue
            $0.balancesStore = .liveValue
            $0[_TokenStore.self] = .liveValue
            $0.nftStore = .liveValue
            $0.settingsStore = .liveValue
        } operation: {
            try await checkPricingUpdates()
        }
    }

    private func checkPricingUpdates() async throws {
        let originalCurrency = TokenStore.baseCurrency
        let originalRates = TokenStore.currencyRates
        let slug = "dapp-hero-refresh-test"
        let account = MAccount(id: "dapp-hero-refresh-mainnet", title: "Test", type: .mnemonic, byChain: [.ton: .init(address: "recipient")])
        let payload = ApiParsedPayload.tokensTransferNonStandard(.init(queryId: 0, amount: 1_000_000, destination: "recipient", slug: slug))
        let transfer = ApiDappTransfer(toAddress: "contract", amount: 0, payload: payload, isDangerous: false, normalizedAddress: "contract", displayedToAddress: "recipient", networkFee: 0)
        let request = ApiUpdate.DappSendTransactions(promiseId: "test", accountId: account.id, dapp: .sample, operationChain: .ton, transactions: [transfer], emulation: nil, shouldHideTransfers: false)
        let controller = SendDappVC.presentationFixture(request: request, account: account)
        defer {
            WalletCoreData.remove(observer: controller)
            TokenStore.walletCore(event: .baseCurrencyChanged(to: originalCurrency))
            TokenStore.walletCore(event: .updateCurrencyRates(.init(rates: originalRates)))
            TokenStore.walletCore(event: .updateTokens(["kind": "partial", "tokens": [:], "removedSlugs": [slug]]))
        }

        try await TokenStore.setBaseCurrency(currency: .USD)
        TokenStore.walletCore(event: .updateCurrencyRates(.init(rates: ["USD": 1, "EUR": 0.8])))
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.hostingController?.rootView.heroAmount)

        try updatePrice(1, slug: slug)
        try await expectHero(controller, amount: 1_000_000, currency: .USD)
        try updatePrice(2, slug: slug)
        try await expectHero(controller, amount: 2_000_000, currency: .USD)

        try await TokenStore.setBaseCurrency(currency: .EUR)
        try await expectHero(controller, amount: 1_600_000, currency: .EUR)
        TokenStore.walletCore(event: .updateCurrencyRates(.init(rates: ["USD": 1, "EUR": 0.9])))
        try await expectHero(controller, amount: 1_800_000, currency: .EUR)

        try updatePrice(0.5, slug: slug)
        try await expectHero(controller, amount: nil, currency: .EUR)
        try await TokenStore.setBaseCurrency(currency: originalCurrency)
    }

    private func updatePrice(_ price: Double, slug: String) throws {
        let token = ApiToken(slug: slug, name: "Test", symbol: "TEST", decimals: 6, chain: .ton, priceUsd: price)
        let tokens = try JSONSerialization.jsonObject(with: JSONEncoder().encode([slug: token]))
        TokenStore.walletCore(event: .updateTokens(["kind": "partial", "tokens": tokens]))
    }

    private func expectHero(_ controller: SendDappVC, amount: BigInt?, currency: MBaseCurrency) async throws {
        for _ in 0..<100 {
            let hero = controller.hostingController?.rootView.heroAmount
            if hero?.amount == amount, hero == nil || hero?.baseCurrency == currency { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.hostingController?.rootView.heroAmount?.amount, amount)
        if amount != nil {
            XCTAssertEqual(controller.hostingController?.rootView.heroAmount?.baseCurrency, currency)
        }
    }
}
