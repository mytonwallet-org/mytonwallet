import Foundation
import CoreGraphics

public struct CardSurfaceLight: Equatable, Sendable {
    public struct TouchSpot: Equatable, Sendable {
        /// Offset from card center, normalized to its half-width / half-height.
        public var position: CGPoint
        public var opacity: CGFloat
    }

    public var tilt: CGPoint = .zero
    public var activity: CGFloat = 0
    public var press: CGFloat = 0
    /// Normalized band travel: -1 is beyond the top left, +1 beyond the bottom right for the default diagonal.
    public var linearPosition: CGFloat?
    /// Optional touch override in degrees above horizontal; negative mirrors the diagonal.
    public var linearAngle: CGFloat?
    public var touchSpot: TouchSpot?

    public init(tilt: CGPoint = .zero, activity: CGFloat = 0, press: CGFloat = 0, linearPosition: CGFloat? = nil, linearAngle: CGFloat? = nil, touchSpot: TouchSpot? = nil) {
        self.tilt = tilt
        self.activity = activity
        self.press = press
        self.linearPosition = linearPosition
        self.linearAngle = linearAngle
        self.touchSpot = touchSpot
    }
}

/// Motion wakes the reflection; holding a different device angle does not keep it lit.
struct CardLightActivity {
    private(set) var value: Double = 0
    private var holdRemaining: TimeInterval = 0
    private var fadeElapsed: TimeInterval = 0
    private var fadeStart = 0.0
    var isSettled: Bool { value == 0 }

    mutating func reset() {
        value = 0
        holdRemaining = 0
        fadeElapsed = 0
        fadeStart = 0
    }

    mutating func advance(angularSpeed: Double, touch: Double, by dt: TimeInterval) {
        guard dt > 0 else { return }
        // Ignore small movements. Full response at about 34 degrees per second.
        let movement = min(1, max(0, (angularSpeed - 0.08) / 0.52))
        let target = max(movement * movement * (3 - 2 * movement), min(1, max(0, touch)))
        if target > 0 {
            holdRemaining = 1
            fadeElapsed = 0
            if target > value {
                value += (target - value) * (1 - exp(-dt / (touch > 0 ? 0.08 : 0.16)))
            }
        } else if value > 0 {
            let fadingTime = max(0, dt - holdRemaining)
            holdRemaining = max(0, holdRemaining - dt)
            guard fadingTime > 0 else { return }
            if fadeElapsed == 0 { fadeStart = value }
            fadeElapsed = min(2, fadeElapsed + fadingTime)
            let t = fadeElapsed / 2
            value = fadeStart * (1 - t * t * (3 - 2 * t))
        }
    }
}
