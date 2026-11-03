import XCTest
import UIKit
@testable import UIAgent
import WalletContext

@MainActor
final class AgentScrollToBottomButtonTests: XCTestCase {
    /// Figma's "Scrolled Up" frame, scaled to the microphone circle: an 18 × 9 pt chevron stroked at 2 pt in #1A1A1A,
    /// 2 pt below the button's center, with the chevron drawn at 80%
    func testChevronMatchesTheScrolledUpDesign() throws {
        let size = AgentScrollToBottomButton.size
        let button = AgentScrollToBottomButton(frame: CGRect(x: 0, y: 0, width: size, height: size))
        button.layoutIfNeeded()
        let chevron = button.chevronView
        let imageSize = AgentScrollToBottomButton.chevronImageSize
        let scale = size / 40 * 0.8

        XCTAssertEqual(button.intrinsicContentSize, CGSize(width: size, height: size))
        // The renderer rounds the image's canvas up to whole pixels; the chevron is drawn at the same points inside it
        let image = try XCTUnwrap(chevron.image)
        XCTAssertEqual(image.size.width, ceil(imageSize.width * image.scale) / image.scale, accuracy: 0.001)
        XCTAssertEqual(image.size.height, ceil(imageSize.height * image.scale) / image.scale, accuracy: 0.001)
        XCTAssertEqual(imageSize.width, 20 * scale, accuracy: 0.001)
        XCTAssertEqual(imageSize.height, 11 * scale, accuracy: 0.001)
        XCTAssertEqual(chevron.bounds.size, imageSize)
        XCTAssertEqual(chevron.center.x, size / 2, accuracy: 0.001)
        XCTAssertEqual(chevron.center.y, size / 2 + AgentScrollToBottomButton.chevronOffset, accuracy: 0.001)
        XCTAssertEqual(AgentScrollToBottomButton.chevronOffset, 2 * scale, accuracy: 0.001)
        let lightColor = chevron.tintColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertEqual(lightColor, UIColor(hex: "#1A1A1A"))
    }

    /// Like Telegram's chat navigation button, it scales between 0.2 and 1 as it hides and shows
    func testVisibilityScalesTheButtonAsTelegram() {
        let size = AgentScrollToBottomButton.size
        let button = AgentScrollToBottomButton(frame: CGRect(x: 0, y: 0, width: size, height: size))
        XCTAssertTrue(button.isHidden)
        XCTAssertFalse(button.isButtonVisible)
        button.setButtonVisible(true, animated: false)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertEqual(button.chevronView.alpha, 1)
        button.setButtonVisible(false, animated: false)
        XCTAssertTrue(button.isHidden)
        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertEqual(button.chevronView.alpha, 0)
    }
}
