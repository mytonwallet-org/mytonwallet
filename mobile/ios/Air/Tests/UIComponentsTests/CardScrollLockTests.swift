import XCTest
import UIKit
@testable import UIComponents

@MainActor
final class CardScrollLockTests: XCTestCase {
    @TaskLocal private static var cleanupScope = false

    // Keep this synchronous: an async test can hide the old-runtime isolated-deinit crash.
    func testMotionDriverReleasesInsideSynchronousTaskLocalScope() {
        Self.$cleanupScope.withValue(true) {
            weak var released: CardSurfaceMotionDriver?
            autoreleasepool {
                let card = UIView()
                let driver = CardSurfaceMotionDriver(cardView: card, onLight: { _ in })
                released = driver
                driver.input = .drag
                driver.setActive(true)
            }
            XCTAssertNil(released, "The active display link must not keep its driver alive")
        }
    }

    func testPlayKeepsHeaderInsetsAndCardPosition() async throws {
        let host = UIViewController()
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 64, left: 0, bottom: 34, right: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let vertical = UIScrollView(frame: host.view.bounds)
        vertical.contentInsetAdjustmentBehavior = .automatic
        vertical.contentInset.top = 140
        vertical.contentSize = CGSize(width: 402, height: 1800)
        host.view.addSubview(vertical)
        let horizontal = UIScrollView(frame: CGRect(x: 0, y: -140, width: 402, height: 232))
        horizontal.contentInsetAdjustmentBehavior = .never
        horizontal.contentSize = CGSize(width: 1206, height: 232)
        vertical.addSubview(horizontal)
        let card = UIView(frame: CGRect(x: 410, y: 0, width: 386, height: 232))
        horizontal.addSubview(card)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        vertical.contentOffset = CGPoint(x: 0, y: -vertical.adjustedContentInset.top + 24)
        horizontal.contentOffset = CGPoint(x: 402, y: 0)
        window.layoutIfNeeded()

        let insets = vertical.adjustedContentInset
        let verticalOffset = vertical.contentOffset
        let horizontalOffset = horizontal.contentOffset
        let frame = card.convert(card.bounds, to: window)
        XCTAssertGreaterThan(insets.top, vertical.contentInset.top)
        let lock = CardScrollLock()
        defer { lock.unlock() }
        for playing in [true, false, true, false] {
            if playing { lock.lock(above: card) } else { lock.unlock() }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(vertical.adjustedContentInset, insets, "Playing must not change the safe-area inset")
            XCTAssertEqual(vertical.contentOffset, verticalOffset)
            XCTAssertEqual(horizontal.contentOffset, horizontalOffset)
            XCTAssertEqual(card.convert(card.bounds, to: window), frame, "The card must stay under the same point of the finger")
        }
    }
}
