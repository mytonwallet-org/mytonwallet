import Testing
@testable import UIComponents

@Suite("Card background animation policy")
struct CardBackgroundMotionPolicyTests {
    private var enabled: CardBackgroundMotionPolicy {
        .init(requested: true, animationsEnabled: true, lowPowerMode: false, reduceMotion: false, applicationActive: true, visible: true)
    }

    @Test func lowPowerModeAlwaysDisablesAnimation() {
        var policy = enabled
        #expect(policy.canAnimate)
        policy.lowPowerMode = true
        #expect(!policy.canAnimate)
        policy.lowPowerMode = false
        #expect(policy.canAnimate)
    }

    @Test func leavingLowPowerModeDoesNotOverrideUserPreference() {
        var policy = enabled
        policy.animationsEnabled = false
        policy.lowPowerMode = true
        #expect(!policy.canAnimate)
        policy.lowPowerMode = false
        #expect(!policy.canAnimate)
    }

    @Test func staticConsumersNeverAnimate() {
        var policy = enabled
        policy.requested = false
        #expect(!policy.canAnimate)
        policy.lowPowerMode = true
        policy.lowPowerMode = false
        #expect(!policy.canAnimate)
    }

    @Test func reduceMotionAndVisibilityAreIndependentGates() {
        var policy = enabled
        policy.reduceMotion = true
        #expect(!policy.canAnimate)
        policy.reduceMotion = false
        policy.visible = false
        #expect(!policy.canAnimate)
        policy.visible = true
        policy.applicationActive = false
        #expect(!policy.canAnimate)
        policy.applicationActive = true
        #expect(policy.canAnimate)
    }
}
