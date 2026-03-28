import AppIntents

struct TokenWithChartWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Rate with Chart"
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_with_chart_description"))

    @Parameter(title: LocalizedStringResource("Token"), default: .TONCOIN)
    var token: ApiToken
    
    @Parameter(title: LocalizedStringResource("Chart Period"), default: .month)
    var period: PricePeriod
}
