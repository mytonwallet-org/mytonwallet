import Foundation
import Testing
import UIKit
@testable import UIComponents

@Suite("Circular card touch light")
struct CardTouchSpotMotionTests {
    @Test func firstFrameMatchesWebSpringAndTravelGain() {
        var motion = CardTouchSpotMotion()
        motion.press(at: CGPoint(x: 0.8, y: -0.6))
        motion.advance(by: 1.0 / 60)
        #expect(abs(motion.light.position.x - 0.04554) < 1e-12)
        #expect(abs(motion.light.position.y + 0.034155) < 1e-12)
        #expect(abs(motion.light.opacity - 0.0495) < 1e-12)
    }

    @Test func timingMatchesAcrossDisplayRatesAndLimitsCatchUp() {
        var reference = CardTouchSpotMotion()
        reference.press(at: CGPoint(x: -0.6, y: 0.8))
        var slow = reference, fast = reference, delayed = reference
        for _ in 0..<12 { reference.advance(by: 1.0 / 60) }
        for _ in 0..<6 { slow.advance(by: 1.0 / 30) }
        for _ in 0..<24 { fast.advance(by: 1.0 / 120) }
        #expect(slow.light == reference.light)
        #expect(fast.light == reference.light)
        var capped = delayed
        delayed.advance(by: 30)
        capped.advance(by: 0.1)
        #expect(delayed.light == capped.light)
    }

    @Test func releaseUsesWebSpringThenSettlesAtCenter() {
        var motion = CardTouchSpotMotion()
        motion.press(at: CGPoint(x: 0.5, y: -0.5))
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        #expect(motion.isSettled && motion.isFollowing)
        motion.release()
        motion.advance(by: 1.0 / 60)
        #expect(abs(motion.light.position.x - 0.575 * 0.9906) < 1e-12)
        #expect(abs(motion.light.opacity - 0.9906) < 1e-12)
        for _ in 0..<600 { motion.advance(by: 1.0 / 60) }
        #expect(motion.isSettled && !motion.isFollowing)
        #expect(motion.light.position == .zero)
        #expect(motion.light.opacity == 0)
    }

    @Test(arguments: [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
                      CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)])
    func tracksFingerInEveryCornerWithoutEscapingCard(_ point: CGPoint) {
        var motion = CardTouchSpotMotion()
        motion.press(at: point)
        for _ in 0..<180 {
            motion.advance(by: 1.0 / 60)
            #expect(abs(motion.light.position.x) <= 1 && abs(motion.light.position.y) <= 1)
            #expect((0...1).contains(motion.light.opacity))
        }
        #expect(motion.light.position == point)
        motion.press(at: CGPoint(x: -point.x, y: -point.y))
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        #expect(motion.light.position == CGPoint(x: -point.x, y: -point.y))
        motion.reset()
        #expect(motion.light.position == .zero && motion.light.opacity == 0)
    }

    @Test @MainActor func suspensionPreservesSpotAndReuseClearsIt() async throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        var light = CardSurfaceLight()
        let driver = CardSurfaceMotionDriver(cardView: view) { light = $0 }
        driver.input = .drag
        driver.shineStyle = .linear
        driver.linearTouchMode = .circular
        driver.setActive(true)
        defer { driver.setActive(false) }
        driver.press(at: CGPoint(x: 0.7, y: -0.7), began: true)
        try await Task.sleep(for: .milliseconds(250))
        let spot = try #require(light.touchSpot)
        #expect(spot.position.x > 0 && spot.position.y < 0 && spot.opacity > 0)
        #expect(light.linearPosition == 1, "The circular option must not start a band pass")
        driver.setSuspended(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(light.touchSpot == spot)
        driver.setSuspended(false)
        #expect(light.touchSpot == spot)
        try await Task.sleep(for: .milliseconds(400))
        #expect(try #require(light.touchSpot).opacity < spot.opacity)
        driver.setActive(false)
        #expect(light.touchSpot == nil)
        #expect(CATransform3DIsIdentity(view.layer.transform))
    }
}
