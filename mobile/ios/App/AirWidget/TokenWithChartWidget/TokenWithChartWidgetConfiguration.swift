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

struct TokenWithChartWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Rate with Chart"
    static var description: IntentDescription = "Track a token price on your Home Screen."

    @Parameter(title: "Token", default: .TONCOIN)
    var token: ApiToken
    
    @Parameter(title: "Chart Period", default: .month)
    var period: PricePeriod
//    
//    @Parameter(title: "Style", default: .vivid)
//    var style: ChartStyle
}
