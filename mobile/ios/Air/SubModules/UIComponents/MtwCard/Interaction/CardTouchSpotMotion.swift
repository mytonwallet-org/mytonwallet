import Foundation
import CoreGraphics

/// Matches the web card's useCardTilt spring, including its softer release.
struct CardTouchSpotMotion {
    var gradualAppearance = false
    var appearanceDelay: TimeInterval = 0.35
    var appearanceDuration: TimeInterval = 0.8
    private var heldTime: TimeInterval = 0
    private var appearance: Double = 1
    private var value = SIMD3<Double>(0.5, 0.5, 0)
    private var target = SIMD3<Double>(0.5, 0.5, 0)
    private var velocity = SIMD3<Double>.zero
    private var remainder: TimeInterval = 0
    private(set) var isFollowing = false

    var isSettled: Bool {
        if isFollowing && gradualAppearance && appearance < 1 { return false }
        let delta = value - target
        return max(abs(delta.x), abs(delta.y), abs(delta.z)) <= 0.0002
            && max(abs(velocity.x), abs(velocity.y), abs(velocity.z)) <= 0.0002
    }

    var light: CardSurfaceLight.TouchSpot {
        CardSurfaceLight.TouchSpot(
            position: CGPoint(x: min(1, max(-1, (value.x - 0.5) * 2 * 1.15)),
                              y: min(1, max(-1, (value.y - 0.5) * 2 * 1.15))),
            opacity: min(1, max(0, value.z)) * appearance)
    }

    mutating func press(at point: CGPoint, began: Bool = false) {
        if began || !isFollowing {
            heldTime = 0
            appearance = gradualAppearance ? 0 : 1
            if gradualAppearance { value.z = 0; velocity.z = 0 }
        }
        isFollowing = true
        target = SIMD3((min(1, max(-1, Double(point.x))) + 1) / 2,
                       (min(1, max(-1, Double(point.y))) + 1) / 2, 1)
    }

    mutating func release() {
        isFollowing = false
        target = SIMD3(0.5, 0.5, 0)
    }

    mutating func reset() {
        value = SIMD3(0.5, 0.5, 0); target = value; velocity = .zero
        remainder = 0; heldTime = 0; appearance = gradualAppearance ? 0 : 1
        isFollowing = false
    }

    mutating func advance(by dt: TimeInterval) {
        guard dt > 0 else { return }
        remainder += min(dt, 0.1)
        let step = 1.0 / 60
        let stiffness = isFollowing ? 0.066 : 0.01
        let damping = isFollowing ? 0.25 : 0.06
        while remainder + 1e-12 >= step {
            remainder = max(0, remainder - step)
            if isFollowing {
                heldTime += step
                let progress = min(1, max(0, (heldTime - max(0, appearanceDelay)) / max(0.05, appearanceDuration)))
                appearance = gradualAppearance ? progress * progress * (3 - 2 * progress) : 1
            }
            velocity = (velocity + (target - value) * stiffness) * (1 - damping)
            value += velocity
        }
        if isSettled {
            value = target
            velocity = .zero
        }
    }
}
