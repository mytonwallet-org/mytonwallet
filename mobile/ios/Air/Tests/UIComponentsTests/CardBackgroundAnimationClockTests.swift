import Testing
@testable import UIComponents

@Suite("Independent card background motion")
struct CardBackgroundAnimationClockTests {
    @Test func restingClocksUseTheLabDefaults() {
        var clock = CardBackgroundAnimationClock()
        clock.advance(by: 2, press: 0)
        #expect(abs(clock.lineTime - 3.1) < 1e-12)
        #expect(clock.blobTime == 2)
        #expect(clock.boost == 0)
    }

    @Test func touchAcceleratesOnlyTheBlobsAndReleaseReturnsToIdle() {
        var clock = CardBackgroundAnimationClock()
        for _ in 0..<30 { clock.advance(by: 1.0 / 30, press: 1) }
        #expect(clock.boost > 0.99)
        #expect(clock.blobTime > 2.5 && clock.blobTime < 3)
        #expect(abs(clock.lineTime - 1.55) < 1e-12)
        let beforeRelease = clock.blobTime
        clock.advance(by: 1.0 / 30, press: 0)
        #expect(clock.blobTime > beforeRelease)
        #expect(clock.blobTime - beforeRelease < 0.1)
        for _ in 0..<150 { clock.advance(by: 1.0 / 30, press: 0) }
        #expect(clock.boost < 0.001)
        let idleTime = clock.blobTime
        clock.advance(by: 1, press: 0)
        #expect(abs(clock.blobTime - idleTime - 1) < 0.001)
    }

    @Test func speedChangesAreContinuousAndIndependentOfFrameRate() {
        var slow = CardBackgroundAnimationClock(), fast = CardBackgroundAnimationClock()
        for press in [0.0, 1.0, 0.0, 0.5, 0.0] {
            let before = slow.blobTime
            slow.advance(by: 0, press: press)
            #expect(slow.blobTime == before)
            for _ in 0..<15 { slow.advance(by: 1.0 / 30, press: press) }
            for _ in 0..<30 { fast.advance(by: 1.0 / 60, press: press) }
            #expect(abs(slow.blobTime - fast.blobTime) < 1e-12)
            #expect(abs(slow.lineTime - fast.lineTime) < 1e-12)
        }
    }

    @Test func deviceMotionBoostsWithoutTouchAndDoesNotStackWithTouch() {
        var moving = CardBackgroundAnimationClock(), touching = CardBackgroundAnimationClock(), both = CardBackgroundAnimationClock()
        for _ in 0..<30 {
            moving.advance(by: 1.0 / 30, press: 0, activity: 1)
            touching.advance(by: 1.0 / 30, press: 1)
            both.advance(by: 1.0 / 30, press: 1, activity: 1)
        }
        #expect(moving.blobTime == touching.blobTime)
        #expect(both.blobTime == touching.blobTime)
        #expect(moving.blobTime > 2.5)
        #expect(moving.lineTime == touching.lineTime)
        for _ in 0..<150 { moving.advance(by: 1.0 / 30, press: 0, activity: 0) }
        #expect(moving.boost < 0.001)
    }
}
