import AppIntents

struct TokenWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Token"
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_description"))

    @Parameter(title: LocalizedStringResource("Token"), default: .TONCOIN)
    var token: ApiToken
}
