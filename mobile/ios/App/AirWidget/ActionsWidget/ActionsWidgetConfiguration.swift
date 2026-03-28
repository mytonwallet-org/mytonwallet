import AppIntents

struct ActionsWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Actions"
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$actions_description"))

    @Parameter(title: LocalizedStringResource("Style"), default: .neutral)
    var style: ActionsStyle
}
