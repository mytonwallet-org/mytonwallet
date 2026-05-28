//
//  TokenQuery.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import AppIntents
import WalletCore
import WidgetKit
import WalletContext

extension SharedStore {
    func displayCurrency() async -> MBaseCurrency {
        await baseCurrency()
    }
}
