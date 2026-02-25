import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

@Perceptible
final class BuyWithCardModel {
    
    let supportedCurrencies: [MBaseCurrency] = [.USD, .EUR, .RUB]
    let chain: ApiChain
    var selectedCurrency: MBaseCurrency
    
    @PerceptionIgnored
    @AccountContext(source: .current) var account: MAccount
    
    init(chain: ApiChain, selectedCurrency: MBaseCurrency?) {
        self.chain = chain
        self.selectedCurrency = selectedCurrency == .RUB || ConfigStore.shared.config?.countryCode == "RU" ? .RUB : .USD
    }
}
