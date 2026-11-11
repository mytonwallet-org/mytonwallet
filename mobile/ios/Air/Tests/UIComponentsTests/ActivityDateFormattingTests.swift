import Foundation
import Testing
@testable import UIComponents

@Suite("Activity Date Formatting")
struct ActivityDateFormattingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let locale = Locale(identifier: "en_US_POSIX")

    private var persianCalendar: Calendar {
        var calendar = Calendar(identifier: .persian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func `Farsi activity headers and timestamps use Jalali dates`() {
        let now = date(2026, 3, 22)
        let activityDate = date(2026, 3, 21)
        let locale = Locale(identifier: "fa")

        #expect(ActivityDateFormatting.headerText(
            for: activityDate, relativeTo: now, calendar: persianCalendar, locale: locale
        ) == "۱ فروردین")
        #expect(ActivityDateFormatting.timestampText(
            for: activityDate, mode: .dateWhenOlderThanTwelveHours,
            relativeTo: now, calendar: persianCalendar, locale: locale
        ) == "۱ فروردین")
    }

    @Test
    func `previous Jalali year is included across Nowruz`() {
        let locale = Locale(identifier: "fa")
        let now = date(2026, 3, 21)

        #expect(ActivityDateFormatting.dateText(
            for: date(2026, 3, 20), relativeTo: now, calendar: persianCalendar, locale: locale
        ) == "۲۹ اسفند ۱۴۰۴")
        #expect(ActivityDateFormatting.shortDateText(
            for: date(2026, 3, 20), relativeTo: now, calendar: persianCalendar, locale: locale
        ) == "۲۹ اسفند ۱۴۰۴")
    }

    @Test
    func `Gregorian new year does not add a year within the same Jalali year`() {
        #expect(ActivityDateFormatting.dateText(
            for: date(2025, 12, 31), relativeTo: date(2026, 1, 2),
            calendar: persianCalendar, locale: Locale(identifier: "fa")
        ) == "۱۰ دی")
    }

    @Test
    func `Jalali leap day is formatted correctly`() {
        #expect(ActivityDateFormatting.dateText(
            for: date(2025, 3, 20), relativeTo: date(2026, 3, 21),
            calendar: persianCalendar, locale: Locale(identifier: "fa")
        ) == "۳۰ اسفند ۱۴۰۳")
    }

    @Test
    func `today always uses time even after twelve hours`() {
        let now = date(2026, 8, 30, 23)
        let activityDate = date(2026, 8, 30, 1)

        #expect(!ActivityDateFormatting.shouldShowDate(
            for: activityDate,
            relativeTo: now,
            calendar: calendar
        ))
    }

    @Test
    func `previous day keeps time through twelve hour boundary`() {
        let now = date(2026, 8, 30, 10)

        #expect(!ActivityDateFormatting.shouldShowDate(
            for: date(2026, 8, 29, 22),
            relativeTo: now,
            calendar: calendar
        ))
        #expect(ActivityDateFormatting.shouldShowDate(
            for: date(2026, 8, 29, 21, 59),
            relativeTo: now,
            calendar: calendar
        ))
    }

    @Test
    func `date omits current year and includes a different year`() {
        let now = date(2026, 8, 30, 10)

        #expect(ActivityDateFormatting.dateText(
            for: date(2026, 8, 29),
            relativeTo: now,
            calendar: calendar,
            locale: locale
        ) == "August 29")
        #expect(ActivityDateFormatting.dateText(
            for: date(2025, 12, 31),
            relativeTo: now,
            calendar: calendar,
            locale: locale
        ) == "December 31, 2025")
    }

    @Test
    func `activity timestamp uses abbreviated system date`() {
        let now = date(2026, 8, 30, 10)

        #expect(ActivityDateFormatting.timestampText(
            for: date(2026, 8, 29),
            mode: .dateWhenOlderThanTwelveHours,
            relativeTo: now,
            calendar: calendar,
            locale: locale
        ) == "Aug 29")
        #expect(ActivityDateFormatting.timestampText(
            for: date(2025, 12, 31),
            mode: .dateWhenOlderThanTwelveHours,
            relativeTo: now,
            calendar: calendar,
            locale: locale
        ) == "Dec 31, 2025")
    }

    @Test
    func `next timestamp change waits for both midnight and twelve hours`() {
        let early = date(2026, 8, 29, 10)
        let late = date(2026, 8, 29, 22)
        let now = date(2026, 8, 29, 23)
        #expect(ActivityDateFormatting.getNextTimestampUpdate(
            for: early, mode: .dateWhenOlderThanTwelveHours, relativeTo: now, calendar: calendar
        ) == date(2026, 8, 30))
        let transition = date(2026, 8, 30, 10).addingTimeInterval(1)
        #expect(ActivityDateFormatting.getNextTimestampUpdate(
            for: late, mode: .dateWhenOlderThanTwelveHours, relativeTo: now, calendar: calendar
        ) == transition)
        #expect(ActivityDateFormatting.shouldShowDate(for: late, relativeTo: transition, calendar: calendar))
        #expect(ActivityDateFormatting.getNextTimestampUpdate(
            for: late, mode: .dateWhenOlderThanTwelveHours, relativeTo: transition, calendar: calendar
        ) == nil)
        #expect(ActivityDateFormatting.getNextTimestampUpdate(
            for: late, mode: .timeOnly, relativeTo: now, calendar: calendar
        ) == nil)
    }

    @Test(arguments: [3, 11])
    func `midnight scheduling follows daylight saving changes`(month: Int) throws {
        var calendar = calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = month == 3 ? 8 : 1
        let timestamp = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 1)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day + 1)))
        #expect(ActivityDateFormatting.getNextTimestampUpdate(
            for: timestamp, mode: .dateWhenOlderThanTwelveHours, relativeTo: timestamp, calendar: calendar
        ) == nextDay)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
