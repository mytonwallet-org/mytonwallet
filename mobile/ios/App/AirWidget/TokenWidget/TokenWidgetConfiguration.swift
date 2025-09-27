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
    static var title: LocalizedStringResource = "Token"
    static var description: IntentDescription = "Track a token price on your Home Screen."

    @Parameter(title: "Token", default: .TONCOIN)
    var token: ApiToken
}
