import AppIntents
import WalletCoreTypes

@available(iOS 18.4, *)
struct TokenWithChartWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Rate with Chart"
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_with_chart_description"))

    @Parameter(title: LocalizedStringResource("Token"), default: TokenEntity(token: .TONCOIN))
    var token: TokenEntity
    
    @Parameter(title: LocalizedStringResource("Chart Period"), default: .month)
    var period: PricePeriod
}
