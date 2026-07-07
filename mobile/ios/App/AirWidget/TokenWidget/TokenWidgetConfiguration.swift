import AppIntents
import WalletCoreTypes

@available(iOS 18.4, *)
struct TokenWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Token"
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$rate_description"))

    @Parameter(title: LocalizedStringResource("Token"), default: TokenEntity(token: .TONCOIN))
    var token: TokenEntity
}
