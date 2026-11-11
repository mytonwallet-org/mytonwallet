import XCTest
import UIKit
@testable import UIComponents

@MainActor
final class AgentEdgeGlowViewTests: XCTestCase {
    /// The thinking glow stops in the background and goes on once the app is active again: still glowing while the
    /// Agent thinks, and gone when it stopped thinking meanwhile, rather than frozen on the screen's edge
    func testGlowGoesOnOrEndsWhenTheAppIsActiveAgain() async throws {
        let center = NotificationCenter.default
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer {
            window.isHidden = true
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        let glow = AgentEdgeGlowView(frame: window.bounds)
        window.addSubview(glow)
        glow.setGlowing(true)
        try XCTSkipUnless(glow.isAnimating, "The glow draws with Metal")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(glow.isAnimating, "No frames in the background")
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(glow.isAnimating, "Still thinking, it goes on")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        // The answer ends while the app is in the background
        glow.setGlowing(false)
        XCTAssertFalse(glow.isAnimating)
        XCTAssertFalse(glow.subviews.isEmpty, "Its fade waits for the app")
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<100 where !glow.subviews.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(glow.subviews.isEmpty, "No longer thinking, it is gone")
        XCTAssertFalse(glow.isAnimating)
    }

    /// A glow that ended while the app was in the background long enough for its fade to run out is gone the moment the
    /// app is active again, rather than its last frame staying on the screen's edge
    func testGlowEndedLongAgoInTheBackgroundIsGoneOnceActive() async throws {
        let center = NotificationCenter.default
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer {
            window.isHidden = true
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        let glow = AgentEdgeGlowView(frame: window.bounds)
        window.addSubview(glow)
        glow.setGlowing(true)
        try XCTSkipUnless(glow.isAnimating, "The glow draws with Metal")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        glow.setGlowing(false)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(glow.isShown, "Its fade waits for the app")
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(glow.isShown, "Gone at once")
        XCTAssertTrue(glow.subviews.isEmpty)
        XCTAssertFalse(glow.isAnimating)
    }

    /// Ended without animation, the glow goes at once
    func testGlowEndedWithoutAnimationGoesAtOnce() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let glow = AgentEdgeGlowView(frame: window.bounds)
        window.addSubview(glow)
        glow.setGlowing(true)
        try XCTSkipUnless(glow.isShown, "The glow draws with Metal")
        glow.setGlowing(false, animated: false)
        XCTAssertFalse(glow.isGlowing)
        XCTAssertFalse(glow.isShown)
        XCTAssertTrue(glow.subviews.isEmpty)
    }
}
