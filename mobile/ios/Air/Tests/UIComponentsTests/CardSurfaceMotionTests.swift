import QuartzCore
import Testing
import UIKit
@testable import UIComponents

@Suite("Card surface motion")
struct CardSurfaceMotionTests {
    @Test(arguments: [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
                      CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)])
    func pressedCornerMovesAwayAndLightUsesSameNormal(_ point: CGPoint) {
        var motion = CardPressMotion()
        motion.depth = 0.5
        motion.press(at: point)
        motion.advance(by: 1)
        let pose = motion.transform(cardWidth: 370)
        let z = point.x * 185 * pose.m13 + point.y * 107 * pose.m23 + pose.m43
        #expect(z < 0)
        #expect(abs(motion.lightTilt.x - pose.m31 / sin(.pi / 15)) < 1e-10)
        #expect(abs(motion.lightTilt.y - pose.m32 / sin(.pi / 15)) < 1e-10)
    }

    @Test func springMatchesAt30And60HzAndReturnsToIdentity() {
        var slow = CardPressMotion()
        var fast = CardPressMotion()
        slow.press(at: CGPoint(x: 0.8, y: -0.6))
        fast.press(at: CGPoint(x: 0.8, y: -0.6))
        for _ in 0..<6 { slow.advance(by: 1.0 / 30) }
        for _ in 0..<12 { fast.advance(by: 1.0 / 60) }
        #expect(abs(slow.value.x - fast.value.x) < 1e-12)
        #expect(abs(slow.value.y - fast.value.y) < 1e-12)
        #expect(abs(slow.value.z - fast.value.z) < 1e-12)
        slow.release()
        for _ in 0..<90 { slow.advance(by: 1.0 / 30) }
        #expect(slow.isSettled)
        #expect(CATransform3DIsIdentity(slow.transform(cardWidth: 370)))
        #expect(slow.lightTilt == .zero)
    }

    @Test @MainActor func touchObserverCannotSuppressButtonsOrScrollGestures() {
        let observer = CardTouchObserver()
        for other in [UITapGestureRecognizer(), UIPanGestureRecognizer(), UILongPressGestureRecognizer()] {
            #expect(!observer.canPrevent(other))
            #expect(!observer.canBePrevented(by: other))
        }
        #expect(!observer.cancelsTouchesInView)
        #expect(!observer.delaysTouchesBegan)
        #expect(!observer.delaysTouchesEnded)
    }

    @Test @MainActor func deactivationClearsPoseAndLight() async throws {
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        var light = CardSurfaceLight()
        let driver = CardSurfaceMotionDriver(cardView: surface) { light = $0 }
        driver.input = .drag
        driver.setActive(true)
        driver.press(at: CGPoint(x: 1, y: -1), began: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!CATransform3DIsIdentity(surface.layer.transform))
        #expect(light.tilt != .zero)
        #expect(light.activity > 0)
        driver.setActive(false)
        #expect(CATransform3DIsIdentity(surface.layer.transform))
        #expect(light == CardSurfaceLight())
        driver.press(at: CGPoint(x: -1, y: 1), began: true)
        #expect(CATransform3DIsIdentity(surface.layer.transform))
    }

    @Test @MainActor func suspensionFreezesPoseAndFadeUntilResume() async throws {
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        var light = CardSurfaceLight()
        let driver = CardSurfaceMotionDriver(cardView: surface) { light = $0 }
        driver.input = .drag
        driver.setActive(true)
        driver.press(at: CGPoint(x: 1, y: -1), began: true)
        try await Task.sleep(for: .milliseconds(150))
        let pose = surface.layer.transform
        let before = light
        #expect(before.activity > 0)
        driver.setSuspended(true)
        driver.press(at: CGPoint(x: -1, y: 1), began: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(CATransform3DEqualToTransform(pose, surface.layer.transform))
        #expect(light == before)
        driver.setSuspended(false)
        #expect(light == before)
        #expect(CATransform3DEqualToTransform(pose, surface.layer.transform))
        try await Task.sleep(for: .milliseconds(150))
        #expect(light.press < before.press)
        #expect(light.activity >= before.activity)
        driver.setSuspended(true)
        driver.setActive(false)
        #expect(light == CardSurfaceLight())
        #expect(CATransform3DIsIdentity(surface.layer.transform))
    }

    @Test @MainActor
    func linearSweepSurvivesSuspensionAndClearsOnReuse() async throws {
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        var light = CardSurfaceLight()
        let driver = CardSurfaceMotionDriver(cardView: surface) { light = $0 }
        driver.shineStyle = .linear
        driver.input = .drag
        driver.setActive(true)
        driver.press(at: .zero, began: true)
        try await Task.sleep(for: .milliseconds(250))
        let before = light
        #expect(abs(try #require(before.linearPosition)) < 0.99)
        driver.setSuspended(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(light == before)
        driver.setSuspended(false)
        #expect(light == before)
        try await Task.sleep(for: .milliseconds(150))
        let delta = try #require(light.linearPosition) - #require(before.linearPosition)
        #expect(delta < 0)
        driver.setActive(false)
        #expect(light == CardSurfaceLight(linearPosition: 1))
    }

    @Test @MainActor func heldTouchCannotParkOrRepeatLinearShine() async throws {
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        var light = CardSurfaceLight()
        let driver = CardSurfaceMotionDriver(cardView: surface) { light = $0 }
        driver.shineStyle = .linear
        driver.input = .drag
        driver.setActive(true)
        driver.press(at: CGPoint(x: 0.8, y: -0.8), began: true)
        try await Task.sleep(for: .milliseconds(1250))
        #expect(light.linearPosition == -1)
        driver.press(at: CGPoint(x: -0.8, y: 0.8))
        try await Task.sleep(for: .milliseconds(150))
        #expect(light.linearPosition == -1)
        driver.setActive(false)
    }
}
