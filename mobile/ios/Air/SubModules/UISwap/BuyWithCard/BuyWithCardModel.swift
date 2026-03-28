import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

@Perceptible @MainActor 
final class BuyWithCardModel {
    
    let supportedCurrencies: [MBaseCurrency] = [.USD, .EUR, .RUB]
    let chain: ApiChain
    var selectedCurrency: MBaseCurrency
    
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    init(accountContext: AccountContext, chain: ApiChain, selectedCurrency: MBaseCurrency?) {
        self._account = accountContext
        self.chain = chain
        self.selectedCurrency = selectedCurrency == .RUB || ConfigStore.shared.config?.countryCode == "RU" ? .RUB : .USD
    }
}
