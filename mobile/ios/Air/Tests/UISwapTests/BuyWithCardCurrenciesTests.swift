import Foundation
import Testing
@testable import UISwap
@testable import WalletCore

@Suite("Buy With Card Currencies", .serialized)
struct BuyWithCardCurrenciesTests {

    @Test @MainActor
    func `model currencies follow the policy narrowing`() throws {
        ConfigStore.shared.config = try JSONDecoder().decode(
            ApiUpdate.UpdateConfig.self,
            from: Data(#"{"allowedOnOffRampCurrencies": ["usd"]}"#.utf8)
        )
        #expect(BuyWithCardModel.supportedCurrencies(for: .ton) == [.USD])

        ConfigStore.shared.config = nil
        #expect(BuyWithCardModel.supportedCurrencies(for: .ton) == [.USD, .EUR])
    }
}
