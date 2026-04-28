import Foundation

public struct MtwChartDateFormatter: Sendable {
    public let rangeAlwaysShowsYear: Bool
    public let omitsCurrentYearInSingleDate: Bool

    public init(
        rangeAlwaysShowsYear: Bool,
        omitsCurrentYearInSingleDate: Bool
    ) {
        self.rangeAlwaysShowsYear = rangeAlwaysShowsYear
        self.omitsCurrentYearInSingleDate = omitsCurrentYearInSingleDate
    }

    public func singleDateString(
        from date: Date,
        includesTime: Bool,
        referenceDate: Date = Date()
    ) -> String {
        let isCurrentYear = Calendar.current.isDate(date, equalTo: referenceDate, toGranularity: .year)
        let shouldShowYear = !(omitsCurrentYearInSingleDate && isCurrentYear)

        let template: String
        switch (includesTime, shouldShowYear) {
        case (true, true):
            template = "yMMMdjmm"
        case (true, false):
            template = "MMMdjmm"
        case (false, true):
            template = "yMMMd"
        case (false, false):
            template = "MMMd"
        }

        return Self.formatter(localizedTemplate: template).string(from: date)
    }

    public func rangeString(
        from startDate: Date,
        to endDate: Date,
        referenceDate: Date = Date()
    ) -> String {
        let sameDay = Calendar.current.isDate(startDate, inSameDayAs: endDate)
        let useYear = rangeAlwaysShowsYear
            || !Calendar.current.isDate(startDate, equalTo: endDate, toGranularity: .year)

        if sameDay {
            return singleDateString(
                from: startDate,
                includesTime: false,
                referenceDate: useYear ? .distantPast : referenceDate
            )
        }

        let formatter = Self.formatter(localizedTemplate: useYear ? "yMMMd" : "MMMd")
        return "\(formatter.string(from: startDate)) \u{2013} \(formatter.string(from: endDate))"
    }

    public func axisDateString(from date: Date) -> String {
        Self.formatter(localizedTemplate: "MMMd").string(from: date)
    }

    public func axisTimeString(from date: Date) -> String {
        Self.formatter(localizedTemplate: "jmm").string(from: date)
    }

    public static let tokenChart = MtwChartDateFormatter(
        rangeAlwaysShowsYear: false,
        omitsCurrentYearInSingleDate: true
    )

    public static let portfolioChart = MtwChartDateFormatter(
        rangeAlwaysShowsYear: true,
        omitsCurrentYearInSingleDate: true
    )

    private static func formatter(localizedTemplate: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSupport.shared.locale
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate(localizedTemplate)
        return formatter
    }
}
