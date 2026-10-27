import XCTest
import UIKit
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

    func testFirstQuestionWithDateKeepsNaturalOffset() {
        let topInset: CGFloat = 123
        let offset = AgentVC.pinnedOffsetY(
            userMessageFrame: CGRect(x: 0, y: 30, width: 402, height: 110),
            dateHeaderFrame: CGRect(x: 0, y: 16, width: 402, height: 14),
            adjustedContentInsetTop: topInset
        )

        XCTAssertEqual(offset, -topInset)
    }

    func testTallQuestionWithDatePinsDateAtTopContentInset() {
        let topInset: CGFloat = 123
        let dateHeaderFrame = CGRect(x: 0, y: 1_600, width: 402, height: 14)
        let offset = AgentVC.pinnedOffsetY(
            userMessageFrame: CGRect(x: 0, y: dateHeaderFrame.maxY, width: 402, height: 1_200),
            dateHeaderFrame: dateHeaderFrame,
            adjustedContentInsetTop: topInset
        )

        XCTAssertEqual(dateHeaderFrame.minY - offset, topInset + 16)
    }

    func testShortQuestionWithoutDateKeepsTailOffset() {
        let topInset: CGFloat = 123
        let userMessageFrame = CGRect(x: 0, y: 560, width: 402, height: 64)
        let offset = AgentVC.pinnedOffsetY(
            userMessageFrame: userMessageFrame,
            dateHeaderFrame: nil,
            adjustedContentInsetTop: topInset
        )

        XCTAssertEqual(offset, userMessageFrame.maxY - topInset - 100)
    }

    func testTallQuestionWithoutDatePinsTopAtContentInset() {
        let topInset: CGFloat = 123
        let userMessageFrame = CGRect(x: 0, y: 560, width: 402, height: 140)
        let offset = AgentVC.pinnedOffsetY(
            userMessageFrame: userMessageFrame,
            dateHeaderFrame: nil,
            adjustedContentInsetTop: topInset
        )

        XCTAssertEqual(offset, userMessageFrame.minY - topInset - 16)
    }

    private func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }
}
