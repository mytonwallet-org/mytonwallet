import Testing
import Foundation
@testable import UIComponents

@Suite("Card reflection activity")
struct CardLightActivityTests {
    @Test func restingSensorNoiseNeverLightsTheCard() {
        var activity = CardLightActivity()
        for _ in 0..<300 { activity.advance(angularSpeed: 0.075, touch: 0, by: 1.0 / 30) }
        #expect(activity.value == 0)
        #expect(activity.isSettled)
    }

    @Test func motionFadesAwayWhenThePhoneStopsAtAnyAngle() {
        var activity = CardLightActivity()
        for _ in 0..<15 { activity.advance(angularSpeed: 0.6, touch: 0, by: 1.0 / 30) }
        let moving = activity.value
        #expect(moving > 0.9)
        activity.advance(angularSpeed: 0, touch: 0, by: 1)
        #expect(activity.value == moving)
        activity.advance(angularSpeed: 0, touch: 0, by: 1)
        #expect(abs(activity.value - moving * 0.5) < 1e-12)
        activity.advance(angularSpeed: 0, touch: 0, by: 1)
        #expect(activity.isSettled)
    }

    @Test func centerPressLightsUpWithoutChangingTheLightDirection() {
        var press = CardPressMotion()
        var activity = CardLightActivity()
        press.press(at: .zero)
        for _ in 0..<12 {
            press.advance(by: 1.0 / 60)
            activity.advance(angularSpeed: 0, touch: press.value.z, by: 1.0 / 60)
        }
        #expect(press.lightTilt == .zero)
        #expect(activity.value > 0.7)
        press.release()
        for _ in 0..<300 {
            press.advance(by: 1.0 / 60)
            activity.advance(angularSpeed: 0, touch: press.value.z, by: 1.0 / 60)
        }
        #expect(activity.isSettled)
    }

    @Test func responseMatchesAt30And60Hz() {
        var slow = CardLightActivity(), fast = CardLightActivity()
        for speed in [0.25, 0, 0, 0, 0, 0, 0, 0.6, 0, 0, 0, 0, 0, 0, 0] {
            for _ in 0..<15 { slow.advance(angularSpeed: speed, touch: 0, by: 1.0 / 30) }
            for _ in 0..<30 { fast.advance(angularSpeed: speed, touch: 0, by: 1.0 / 60) }
            #expect(abs(slow.value - fast.value) < 1e-12)
        }
        slow.reset()
        #expect(slow.isSettled)
    }

    @Test func renewedInputRestartsHoldWithoutAJumpOrFlash() {
        var activity = CardLightActivity()
        activity.advance(angularSpeed: 0.6, touch: 0, by: 0.5)
        activity.advance(angularSpeed: 0, touch: 0, by: 2)
        let fading = activity.value
        // A gentle new motion preserves the currently visible brightness.
        activity.advance(angularSpeed: 0.1, touch: 0, by: 1.0 / 60)
        #expect(activity.value == fading)
        activity.advance(angularSpeed: 0, touch: 0, by: 1)
        #expect(activity.value == fading)
        activity.advance(angularSpeed: 0, touch: 0, by: 2)
        #expect(activity.isSettled)
        activity.reset()
        activity.advance(angularSpeed: 0, touch: 0, by: 1)
        #expect(activity.isSettled)
    }

    @Test func smallTiltsCannotMoveOrWakeEitherWalletFinish() {
        for degrees in [0.0, 1, 2, 3.9, 4] {
            let response = CardDeviceTilt.response(to: CGPoint(x: degrees * .pi / 180, y: 0), angularSpeed: 1, sensitivity: 3)
            #expect(response.tilt == .zero)
            #expect(response.angularSpeed == 0)
        }
    }

    @Test func tiltThresholdIsRadialAndEntersSmoothly() {
        let justOver = CardDeviceTilt.response(to: CGPoint(x: 4.01 * .pi / 180, y: 0), angularSpeed: 1, sensitivity: 1.5)
        #expect(justOver.tilt.x > 0 && justOver.tilt.x < 0.00001)
        #expect(justOver.angularSpeed > 0 && justOver.angularSpeed < 0.0001)
        let angle = 10.0 * .pi / 180
        let horizontal = CardDeviceTilt.response(to: CGPoint(x: angle, y: 0), angularSpeed: 0.6, sensitivity: 1.5)
        let diagonal = CardDeviceTilt.response(to: CGPoint(x: angle / sqrt(2), y: -angle / sqrt(2)), angularSpeed: 0.6, sensitivity: 1.5)
        #expect(abs(hypot(diagonal.tilt.x, diagonal.tilt.y) - horizontal.tilt.x) < 1e-12)
        #expect(diagonal.tilt.y < 0)
        #expect(horizontal.angularSpeed == diagonal.angularSpeed)
        #expect(horizontal.angularSpeed == 0.6)
    }

}
