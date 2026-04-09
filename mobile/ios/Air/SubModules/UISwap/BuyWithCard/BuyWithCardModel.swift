import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

@Perceptible @MainActor 
final class BuyWithCardModel {
    
    static let allSupportedCurrencies: [MBaseCurrency] = [.USD, .EUR, .RUB]

    static func supportedCurrencies(for chain: ApiChain) -> [MBaseCurrency] {
        allSupportedCurrencies.filter { chain != .tron || $0 != .RUB }
    }

    let chain: ApiChain
    var selectedCurrency: MBaseCurrency

    var supportedCurrencies: [MBaseCurrency] {
        Self.supportedCurrencies(for: chain)
    }
    
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    init(accountContext: AccountContext, chain: ApiChain, selectedCurrency: MBaseCurrency?) {
        self._account = accountContext
        self.chain = chain
        let defaultCurrency: MBaseCurrency = selectedCurrency == .RUB || ConfigStore.shared.config?.countryCode == "RU" ? .RUB : .USD
        self.selectedCurrency = Self.supportedCurrencies(for: chain).contains(defaultCurrency) ? defaultCurrency : .USD
    }
}
