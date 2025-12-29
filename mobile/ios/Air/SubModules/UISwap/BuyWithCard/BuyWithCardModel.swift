//
//  BuyWithCardVC.swift
//  UISwap
//
//  Created by Sina on 5/14/24.
//

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
    
    init(chain: ApiChain, selectedCurrency: MBaseCurrency?) {
        self.chain = chain
        self.selectedCurrency = selectedCurrency == .RUB || ConfigStore.shared.config?.countryCode == "RU" ? .RUB : .USD
    }
}

