import XCTest
import UIKit
@testable import UIAgent
@testable import UIComponents
import WalletContext
import WalletResources

@MainActor
final class AgentChatTitleTests: XCTestCase {
    func testDigestDiscussionTitleUsesTheLocalizedDayAndIncludesPastYears() throws {
        _ = WalletResourcesBundle.bundle.load()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14)))
        let cases = [
            ("en", "2026-11-11T18:00:00Z", "News for November 11"),
            ("ru", "2026-11-11T18:00:00Z", "Новости 11 ноября"),
            ("en", "2025-11-11T18:00:00Z", "News for November 11, 2025"),
            ("ru", "2025-11-11T18:00:00Z", "Новости 11 ноября 2025")
        ]
        for (language, windowEnd, expected) in cases {
            let title = withMessageLanguage(language) {
                AgentV2Model.formatDigestDiscussionTitle(
                    windowEnd: windowEnd, relativeTo: now, calendar: calendar, locale: Locale(identifier: language)
                )
            }
            XCTAssertEqual(title, expected)
        }
    }

    func testTitleIsSemiboldSeventeenBesideALargerEmoji() throws {
        let view = NavigationTitleView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        view.setTitle("Portfolio review", icon: "💼", animated: false)
        let labels = view.subviews.compactMap { $0 as? UILabel }
        let title = try XCTUnwrap(labels.first { $0.text == "Portfolio review" })
        let icon = try XCTUnwrap(labels.first { $0.text == "💼" })

        XCTAssertEqual(title.font, UIFont.systemFont(ofSize: 17, weight: .semibold))
        XCTAssertEqual(icon.font.pointSize, 22)
        XCTAssertFalse(icon.isHidden)
        XCTAssertEqual(view.accessibilityLabel, "💼 Portfolio review")

        view.setTitle("Portfolio review", icon: nil, animated: false)
        XCTAssertTrue(icon.isHidden)
        XCTAssertEqual(view.accessibilityLabel, "Portfolio review")
    }

    func testFirstTitleDoesNotAnimate() {
        XCTAssertFalse(NavigationTitleView.shouldAnimateChange(
            previousTitle: nil, title: "New Chat", isVisible: true, reduceMotion: false
        ))
    }

    func testUnchangedTitleDoesNotAnimate() {
        XCTAssertFalse(NavigationTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Bitcoin news", isVisible: true, reduceMotion: false
        ))
    }

    func testRenameAnimatesWhileVisible() {
        XCTAssertTrue(NavigationTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: true, reduceMotion: false
        ))
    }

    func testAddingEmojiAnimatesWhileVisible() {
        XCTAssertTrue(NavigationTitleView.shouldAnimateChange(
            previousTitle: "Large BTC transfer", title: "🐳 Large BTC transfer", isVisible: true, reduceMotion: false
        ))
    }

    func testTitleChangedWhileHiddenDoesNotAnimate() {
        XCTAssertFalse(NavigationTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: false, reduceMotion: false
        ))
    }

    func testReduceMotionDisablesAnimation() {
        XCTAssertFalse(NavigationTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: true, reduceMotion: true
        ))
    }
}
