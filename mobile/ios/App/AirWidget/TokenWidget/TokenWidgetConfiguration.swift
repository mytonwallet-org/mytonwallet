//
//  AppIntent.swift
//  AirWidget
//
//  Created by nikstar on 23.09.2025.
//

import AppIntents
import WalletCore
import WidgetKit
import WalletContext

struct TokenWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("Token", bundle: LocalizationSupport.shared.bundle)
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_description", bundle: LocalizationSupport.shared.bundle))

    @Parameter(title: LocalizedStringResource("Token", bundle: LocalizationSupport.shared.bundle), default: .TONCOIN)
    var token: ApiToken
}
