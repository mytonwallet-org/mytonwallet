import XCTest
@testable import UIAgent

@MainActor
final class AgentDateHeaderTests: XCTestCase {
    func testTimeKeepsDayPeriodOnTwelveHourClock() {
        let english = Locale(identifier: "en")
        let morning = BaseAgentModel.formattedTime(today(hour: 1, minute: 47), locale: english, hourCycle: .oneToTwelve)
        let afternoon = BaseAgentModel.formattedTime(today(hour: 13, minute: 47), locale: english, hourCycle: .oneToTwelve)
        XCTAssertNotEqual(morning, afternoon)
        XCTAssertTrue(afternoon.contains("PM"), afternoon)
    }

    func testTimeFollowsTwentyFourHourClockInAnyLanguage() {
        for identifier in ["en", "ru"] {
            let time = BaseAgentModel.formattedTime(
                today(hour: 13, minute: 47),
                locale: Locale(identifier: identifier),
                hourCycle: .zeroToTwentyThree
            )
            XCTAssertEqual(time, "13:47", identifier)
        }
    }

    private func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }
}
