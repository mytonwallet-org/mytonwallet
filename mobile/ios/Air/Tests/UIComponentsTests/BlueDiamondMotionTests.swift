import Testing
@testable import UIComponents

@Suite("Blue diamond interaction")
struct BlueDiamondMotionTests {
    @Test @MainActor func loadsBundledModelsAndMetalPipelines() throws {
        _ = try #require(BlueDiamondScene.shared)
    }

    @Test func waitsBeforeRotatingAndHoldingStopsIdleMotion() {
        var motion = BlueDiamondMotion()
        motion.update(time: 0.4)
        #expect(motion.yaw == 0)
        motion.update(time: 2)
        #expect(motion.yaw > 0)
        let held = motion.yaw
        motion.press()
        motion.update(time: 4)
        #expect(motion.yaw == held)
    }

    @Test func holdingEnlargesSmoothlyAndReleaseRestoresSize() {
        var motion = BlueDiamondMotion()
        motion.update(time: 0)
        motion.press()
        motion.update(time: 1.0 / 60)
        #expect(motion.scale > 1 && motion.scale < 1.25)
        for frame in 2...30 { motion.update(time: Float(frame) / 60) }
        #expect(abs(motion.scale - 1.25) < 0.001)
        motion.release(time: 0.5)
        motion.update(time: 31.0 / 60)
        #expect(motion.scale > 1 && motion.scale < 1.25)
        for frame in 32...60 { motion.update(time: Float(frame) / 60) }
        #expect(abs(motion.scale - 1) < 0.001)
    }

    @Test func suspendingWhileHeldOrShrinkingRestoresSizeWithoutAnotherFrame() {
        for released in [false, true] {
            var motion = BlueDiamondMotion()
            motion.update(time: 0)
            motion.press()
            motion.update(time: 0.1)
            if released { motion.release(time: 0.1) }
            #expect(motion.scale > 1)
            motion.cancelInteraction(time: 0.1)
            #expect(motion.scale == 1)
            motion.update(time: 10)
            #expect(motion.scale == 1)
        }
    }

    @Test func pressingAgainWhileShrinkingContinuesFromCurrentSize() {
        var motion = BlueDiamondMotion()
        motion.update(time: 0)
        motion.press()
        motion.update(time: 0.1)
        motion.release(time: 0.1)
        motion.update(time: 0.15)
        let shrinkingScale = motion.scale
        motion.press()
        #expect(motion.scale == shrinkingScale)
        motion.update(time: 0.2)
        #expect(motion.scale > shrinkingScale && motion.scale < 1.25)
    }

    @Test func dragSettlesAndIdleRotationResumes() {
        var motion = BlueDiamondMotion()
        motion.press()
        motion.drag(dx: 100, dy: 60)
        #expect(motion.yaw > 0 && motion.pitch > 0)
        motion.release(time: 1)
        motion.update(time: 1.7)
        #expect(abs(motion.yaw) < 0.0001 && abs(motion.pitch) < 0.0001)
        motion.update(time: 2)
        #expect(motion.yaw > 0)
    }

    @Test func tapTiltsTowardsTheTouchThenReturnsToIdle() {
        var motion = BlueDiamondMotion()
        motion.press()
        motion.release(time: 1, tap: SIMD2(-1, 0.5), tapStrength: 50)
        motion.update(time: 1.23)
        #expect(motion.yaw < 0 && motion.pitch > 0)
        motion.update(time: 1.9)
        #expect(abs(motion.yaw) < 0.0001 && abs(motion.pitch) < 0.0001)
        motion.update(time: 2.1)
        #expect(motion.yaw > 0)
    }

    @Test func interruptedReleaseCanBeDraggedAgainWithoutJumping() {
        var motion = BlueDiamondMotion()
        motion.press()
        motion.drag(dx: 300, dy: -100)
        motion.release(time: 1)
        motion.update(time: 1.1)
        let yaw = motion.yaw, pitch = motion.pitch
        motion.press()
        motion.update(time: 2)
        #expect(motion.yaw == yaw && motion.pitch == pitch)
        motion.drag(dx: -20, dy: 10)
        #expect(motion.yaw < yaw && motion.pitch > pitch)
    }
}
