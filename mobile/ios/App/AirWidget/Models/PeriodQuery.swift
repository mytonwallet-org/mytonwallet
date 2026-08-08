import AppIntents

public enum PricePeriod: String, CaseIterable, Equatable, Hashable, Codable, Sendable, AppEnum {
    
    case day = "1D"
    case week = "7D"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "ALL"
    
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Chart Period"))
    
    public static var caseDisplayRepresentations: [PricePeriod : DisplayRepresentation] {
        [
            .all: DisplayRepresentation(title: LocalizedStringResource("$period_all")),
            .year: DisplayRepresentation(title: LocalizedStringResource("$period_year")),
            .threeMonths: DisplayRepresentation(title: LocalizedStringResource("$period_3months")),
            .month: DisplayRepresentation(title: LocalizedStringResource("$period_month")),
            .week: DisplayRepresentation(title: LocalizedStringResource("$period_week")),
            .day: DisplayRepresentation(title: LocalizedStringResource("$period_day")),
        ]
    }
}
