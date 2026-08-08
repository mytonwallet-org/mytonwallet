import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

@Perceptible @MainActor 
final class BuyWithCardModel {
    
    static func supportedCurrencies(for chain: ApiChain) -> [MBaseCurrency] {
        OnRampCurrencyPolicy.supportedCurrencies(for: chain)
    }

    let chain: ApiChain
    var selectedCurrency: MBaseCurrency

    var supportedCurrencies: [MBaseCurrency] {
        Self.supportedCurrencies(for: chain)
    }
    
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    /// Nil when the policy offers no currency on this chain, which is the only correct answer: a model
    /// holding a currency the server withdrew is what would put it in front of the user.
    init?(accountContext: AccountContext, chain: ApiChain, selectedCurrency: MBaseCurrency?) {
        let prefersRUB = selectedCurrency == .RUB || ConfigStore.shared.config?.countryCode == "RU"
        let preferences: [MBaseCurrency] = prefersRUB ? [.RUB, .USD] : [.USD]
        guard let currency = OnRampCurrencyPolicy.preferredCurrency(for: chain, preferences: preferences) else {
            return nil
        }
        self._account = accountContext
        self.chain = chain
        self.selectedCurrency = currency
    }
}
