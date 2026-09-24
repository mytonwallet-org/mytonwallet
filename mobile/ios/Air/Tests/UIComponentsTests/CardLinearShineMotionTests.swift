import Testing
import Foundation
@testable import UIComponents

@Suite("Triggered linear card shine")
struct CardLinearShineMotionTests {
    private func sample(_ motion: inout CardLinearShineMotion, pitch: Double = 0, roll: Double = 0,
                        pitchGain: CGFloat = 1, rollGain: CGFloat = 1,
                        trigger: CGFloat = 15, returning: CGFloat = 15, speed: Double = 0.25,
                        dt: TimeInterval = 1.0 / 60) {
        motion.advance(pitch: pitch * .pi / 180, roll: roll * .pi / 180,
                       pitchSensitivity: pitchGain, rollSensitivity: rollGain,
                       triggerAngle: trigger, returnAngle: returning, angularSpeed: speed, by: dt)
    }

    @Test func subthresholdMovementNeverStartsOrPositionsTheBand() {
        var motion = CardLinearShineMotion()
        for pitch in [0.0, 5, -14.9, 14.9, 0] {
            sample(&motion, pitch: pitch)
            #expect(!motion.isAnimating)
            #expect(motion.position == 1)
        }
    }

    @Test(arguments: [-1.0, 1.0])
    func thresholdPlaysOneCompletePassEvenIfThePhoneStops(_ direction: Double) {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: direction * 15)
        #expect(motion.isAnimating && motion.position == direction)
        sample(&motion, pitch: direction * 15, dt: 0.5)
        #expect(abs(motion.position) < 1e-12)
        sample(&motion, pitch: direction * 15, dt: 0.5)
        #expect(!motion.isAnimating && motion.position == -direction)
        sample(&motion, pitch: direction * 15, dt: 5)
        #expect(!motion.isAnimating && motion.position == -direction)
    }

    @Test func smallReversalsCannotCatchOrReverseTheVisibleBand() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 15)
        var previous = motion.position
        for pitch in [12.0, 16, 14, 15] {
            sample(&motion, pitch: pitch, dt: 0.25)
            #expect(motion.position < previous)
            previous = motion.position
        }
        #expect(!motion.isAnimating && motion.position == -1)
    }

    @Test func defaultThresholdsRequire25DegreesEvenAfterRestingReferenceReset() {
        var motion = CardLinearShineMotion()
        func advance(_ pitch: Double, dt: TimeInterval = 1.0 / 60) {
            motion.advance(pitch: pitch * .pi / 180, pitchSensitivity: 1,
                           angularSpeed: 0.25, by: dt)
        }
        advance(15)
        #expect(!motion.isAnimating)
        advance(24.9)
        #expect(!motion.isAnimating)
        advance(25)
        #expect(motion.isAnimating && motion.position == 1)
        advance(25, dt: 1)
        advance(10)
        #expect(!motion.isAnimating && motion.position == -1)
        advance(0.1)
        #expect(!motion.isAnimating && motion.position == -1)
        advance(0)
        #expect(motion.isAnimating && motion.position == -1)
        advance(0, dt: 1)
        #expect(!motion.isAnimating && motion.position == 1)
    }

    @Test func continuingOneGestureCannotRepeatTheSweep() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 15)
        for step in 1...12 { sample(&motion, pitch: 15 + Double(step) * 5, dt: 0.1) }
        #expect(!motion.isAnimating && motion.position == -1)
        sample(&motion, pitch: 61)
        #expect(!motion.isAnimating)
        sample(&motion, pitch: 60)
        #expect(motion.isAnimating && motion.position == -1)
    }

    @Test func deliberateReturnDuringAPassWaitsUntilItFinishes() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 15)
        sample(&motion, pitch: 0, dt: 0.2)
        #expect(motion.position > 0, "Reversal must not interrupt the forward animation")
        sample(&motion, pitch: 0, dt: 0.8)
        #expect(motion.isAnimating && motion.position == -1)
        sample(&motion, pitch: 0, dt: 1)
        #expect(!motion.isAnimating && motion.position == 1)
        sample(&motion, pitch: 0, dt: 3)
        #expect(!motion.isAnimating)
    }

    @Test func stillnessQuicklyDiscardsPartialMovement() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 14)
        sample(&motion, pitch: 14, dt: 0.5)
        sample(&motion, pitch: 28)
        #expect(!motion.isAnimating)
        sample(&motion, pitch: 29)
        #expect(motion.isAnimating)
    }

    @Test func selectedSensitivitiesApplyToEitherTriggerAxis() {
        var pitch = CardLinearShineMotion(), roll = CardLinearShineMotion()
        sample(&pitch, pitch: 15 / 0.89 - 0.01, pitchGain: 0.89)
        sample(&roll, roll: -(15 / 0.68 - 0.01), rollGain: 0.68)
        #expect(!pitch.isAnimating && !roll.isAnimating)
        sample(&pitch, pitch: 15 / 0.89, pitchGain: 0.89)
        sample(&roll, roll: -15 / 0.68, rollGain: 0.68)
        #expect(pitch.isAnimating && roll.isAnimating)
        #expect(pitch.position == roll.position)
    }

    @Test func disabledAxisCannotTrigger() {
        var motion = CardLinearShineMotion()
        sample(&motion, roll: 90, rollGain: 0)
        #expect(!motion.isAnimating)
        sample(&motion, pitch: 15, roll: 90, rollGain: 0)
        #expect(motion.isAnimating)
    }

    @Test func tapPlaysACompletePassWithoutInterruptingAnExistingPass() {
        var motion = CardLinearShineMotion()
        motion.press()
        sample(&motion, dt: 0.5)
        #expect(abs(motion.position) < 1e-12)
        motion.press()
        #expect(abs(motion.position) < 1e-12)
        sample(&motion, dt: 0.5)
        #expect(!motion.isAnimating && motion.position == -1)
    }

    @Test func suspensionRebasesInputWithoutChangingTheAnimation() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 15)
        sample(&motion, pitch: 15, dt: 0.3)
        let before = motion.position
        motion.rebase(to: 0)
        #expect(motion.position == before)
        sample(&motion, dt: 0.2)
        #expect(abs(motion.position) < 1e-12)
        sample(&motion, dt: 0.5)
        #expect(!motion.isAnimating && motion.position == -1)
        motion.reset()
        #expect(motion.position == 1 && !motion.isAnimating)
    }

    @Test func animationMatchesAt30And60Hz() {
        var slow = CardLinearShineMotion(), fast = CardLinearShineMotion()
        sample(&slow, pitch: 15)
        sample(&fast, pitch: 15)
        for _ in 0..<4 {
            for _ in 0..<9 { sample(&slow, pitch: 15, dt: 1.0 / 30) }
            for _ in 0..<18 { sample(&fast, pitch: 15, dt: 1.0 / 60) }
            #expect(abs(slow.position - fast.position) < 1e-12)
            #expect(slow.isAnimating == fast.isAnimating)
        }
    }

    @Test func fasterTiltsPlayFasterButStoppingCannotCatchTheSweep() {
        var gentle = CardLinearShineMotion(), quick = CardLinearShineMotion()
        sample(&gentle, pitch: 15, speed: 0.25)
        sample(&quick, pitch: 15, speed: 2.5)
        sample(&gentle, pitch: 15, speed: 0, dt: 0.45)
        sample(&quick, pitch: 15, speed: 0, dt: 0.45)
        #expect(gentle.isAnimating)
        #expect(!quick.isAnimating && quick.position == -1)
        sample(&gentle, pitch: 15, speed: 0, dt: 0.55)
        #expect(!gentle.isAnimating && gentle.position == -1)
    }

    @Test func inputMaySpeedUpAnActivePassWithoutChangingItsPositionInstantly() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 15, dt: 0.01)
        sample(&motion, pitch: 15, speed: 0, dt: 0.2)
        let before = motion.position
        sample(&motion, pitch: 16, speed: 2.5, dt: 0.01)
        #expect(motion.position < before && motion.position > before - 0.1)
        sample(&motion, pitch: 16, speed: 0, dt: 0.4)
        #expect(!motion.isAnimating && motion.position == -1)
    }

    @Test func aSmallerReturnThresholdSurvivesRestingReferenceReset() {
        var motion = CardLinearShineMotion()
        sample(&motion, pitch: 8, trigger: 15, returning: 8)
        #expect(!motion.isAnimating)
        sample(&motion, pitch: 15, trigger: 15, returning: 8)
        sample(&motion, pitch: 15, trigger: 15, returning: 8, dt: 1)
        sample(&motion, pitch: 7.1, trigger: 15, returning: 8)
        #expect(!motion.isAnimating)
        sample(&motion, pitch: 7, trigger: 15, returning: 8)
        #expect(motion.isAnimating && motion.position == -1)
    }

    @Test(arguments: [-1.0, 1.0], [-1.0, 1.0])
    func directionalTouchStartsAtEachCorner(x: Double, y: Double) {
        var motion = CardLinearShineMotion()
        motion.beginDirectionalPress(at: CGPoint(x: x, y: y), angle: 61)
        #expect(motion.position == CGFloat(y))
        #expect(motion.linearAngle == (x * y < 0 ? -61 : 61))
        sample(&motion, dt: 0.1)
        motion.endDirectionalPress()
        sample(&motion, dt: 1)
        #expect(!motion.isAnimating && motion.position == CGFloat(-y))
    }

    @Test func heldReleaseQueuesOneReturnWithoutInterruptingTheOutboundPass() {
        var motion = CardLinearShineMotion()
        motion.beginDirectionalPress(at: CGPoint(x: -1, y: -1), angle: 61)
        sample(&motion, dt: 0.5)
        let before = motion.position
        motion.endDirectionalPress()
        #expect(motion.position == before)
        sample(&motion, dt: 0.5)
        #expect(motion.isAnimating && motion.position == 1)
        sample(&motion, dt: 1)
        #expect(!motion.isAnimating && motion.position == -1)
        sample(&motion, dt: 2)
        #expect(!motion.isAnimating)
    }

    @Test func heldDragReturnsTowardsTheFinalFingerCorner() {
        var motion = CardLinearShineMotion()
        motion.beginDirectionalPress(at: CGPoint(x: -1, y: -1), angle: 61)
        sample(&motion, dt: 1)
        motion.moveDirectionalPress(to: CGPoint(x: 1, y: -1))
        motion.endDirectionalPress()
        #expect(motion.isAnimating && motion.linearAngle == -61)
        sample(&motion, dt: 1)
        #expect(!motion.isAnimating && motion.position == -1)
    }

    @Test func cancelledHoldDoesNotReturnOrQueueDeviceInput() {
        var motion = CardLinearShineMotion()
        motion.beginDirectionalPress(at: CGPoint(x: 1, y: 1), angle: 61)
        sample(&motion, pitch: 50, dt: 0.5)
        motion.endDirectionalPress(cancelled: true)
        sample(&motion, pitch: 50, dt: 1)
        #expect(!motion.isAnimating && motion.position == -1)
        sample(&motion, pitch: 50, dt: 1)
        #expect(!motion.isAnimating)
    }

}
