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
    static var title: LocalizedStringResource = LocalizedStringResource("Rate with Chart", bundle: LocalizationSupport.shared.bundle)
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_with_chart_description", bundle: LocalizationSupport.shared.bundle))

    @Parameter(title: LocalizedStringResource("Token", bundle: LocalizationSupport.shared.bundle), default: .TONCOIN)
    var token: ApiToken
    
    @Parameter(title: LocalizedStringResource("Chart Period", bundle: LocalizationSupport.shared.bundle), default: .month)
    var period: PricePeriod
    
//    @Parameter(title: LocalizedStringResource("Style", bundle: LocalizationSupport.shared.bundle), default: .vivid)
//    var style: ChartStyle
}
