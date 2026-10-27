import Foundation
import Testing
@testable import WalletContext

@Suite("Localized Calendar")
struct LocalizedCalendarTests {
    @Test
    func `Farsi uses Jalali with the device time zone`() {
        var systemCalendar = Calendar(identifier: .gregorian)
        systemCalendar.timeZone = TimeZone(identifier: "Asia/Tehran")!
        let calendar = LocalizationSupport.calendar(for: "fa", systemCalendar: systemCalendar)

        #expect(calendar.identifier == .persian)
        #expect(calendar.timeZone == systemCalendar.timeZone)

        let beforeMidnight = Date(timeIntervalSince1970: 1_774_038_599) // March 20, 2026 at 20:29:59 UTC
        let afterMidnight = beforeMidnight.addingTimeInterval(1)
        #expect(calendar.component(.year, from: beforeMidnight) == 1404)
        #expect(calendar.component(.year, from: afterMidnight) == 1405)
        #expect(calendar.component(.month, from: afterMidnight) == 1)
        #expect(calendar.component(.day, from: afterMidnight) == 1)
    }

    @Test(arguments: ["en", "ar", "th", "ru"])
    func `other languages keep the device calendar`(language: String) {
        var systemCalendar = Calendar(identifier: .buddhist)
        systemCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(LocalizationSupport.calendar(for: language, systemCalendar: systemCalendar) == systemCalendar)
    }
}
