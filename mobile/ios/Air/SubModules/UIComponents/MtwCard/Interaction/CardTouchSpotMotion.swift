import Foundation
import CoreGraphics

/// Matches the web card's useCardTilt spring, including its softer release.
struct CardTouchSpotMotion {
    private var value = SIMD3<Double>(0.5, 0.5, 0)
    private var target = SIMD3<Double>(0.5, 0.5, 0)
    private var velocity = SIMD3<Double>.zero
    private var remainder: TimeInterval = 0
    private(set) var isFollowing = false

    var isSettled: Bool {
        let delta = value - target
        return max(abs(delta.x), abs(delta.y), abs(delta.z)) <= 0.0002
            && max(abs(velocity.x), abs(velocity.y), abs(velocity.z)) <= 0.0002
    }

    var light: CardSurfaceLight.TouchSpot {
        CardSurfaceLight.TouchSpot(
            position: CGPoint(x: min(1, max(-1, (value.x - 0.5) * 2 * 1.15)),
                              y: min(1, max(-1, (value.y - 0.5) * 2 * 1.15))),
            opacity: min(1, max(0, value.z)))
    }

    mutating func press(at point: CGPoint) {
        isFollowing = true
        target = SIMD3((min(1, max(-1, Double(point.x))) + 1) / 2,
                       (min(1, max(-1, Double(point.y))) + 1) / 2, 1)
    }

    mutating func release() {
        isFollowing = false
        target = SIMD3(0.5, 0.5, 0)
    }

    mutating func reset() { self = Self() }

    mutating func advance(by dt: TimeInterval) {
        guard dt > 0 else { return }
        remainder += min(dt, 0.1)
        let step = 1.0 / 60
        let stiffness = isFollowing ? 0.066 : 0.01
        let damping = isFollowing ? 0.25 : 0.06
        while remainder + 1e-12 >= step {
            remainder = max(0, remainder - step)
            velocity = (velocity + (target - value) * stiffness) * (1 - damping)
            value += velocity
        }
        if isSettled {
            value = target
            velocity = .zero
        }
    }
}
