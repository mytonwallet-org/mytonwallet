import XCTest
import UIKit
@testable import UIAgent

@MainActor
final class AgentChatTitleTests: XCTestCase {
    func testTitleIsSemiboldSeventeenBesideALargerEmoji() throws {
        let view = AgentChatTitleView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
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
        XCTAssertFalse(AgentChatTitleView.shouldAnimateChange(
            previousTitle: nil, title: "New Chat", isVisible: true, reduceMotion: false
        ))
    }

    func testUnchangedTitleDoesNotAnimate() {
        XCTAssertFalse(AgentChatTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Bitcoin news", isVisible: true, reduceMotion: false
        ))
    }

    func testRenameAnimatesWhileVisible() {
        XCTAssertTrue(AgentChatTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: true, reduceMotion: false
        ))
    }

    func testAddingEmojiAnimatesWhileVisible() {
        XCTAssertTrue(AgentChatTitleView.shouldAnimateChange(
            previousTitle: "Large BTC transfer", title: "🐳 Large BTC transfer", isVisible: true, reduceMotion: false
        ))
    }

    func testTitleChangedWhileHiddenDoesNotAnimate() {
        XCTAssertFalse(AgentChatTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: false, reduceMotion: false
        ))
    }

    func testReduceMotionDisablesAnimation() {
        XCTAssertFalse(AgentChatTitleView.shouldAnimateChange(
            previousTitle: "Bitcoin news", title: "Large BTC transfer", isVisible: true, reduceMotion: true
        ))
    }
}
