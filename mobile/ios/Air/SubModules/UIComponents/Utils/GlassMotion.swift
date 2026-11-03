import QuartzCore
import UIKit

/// A damped spring as SwiftUI defines it, solved in closed form, so a motion doesn't depend on how it is sampled.
/// Under-, critically and overdamped springs each follow their exact solution.
public struct GlassSpring: Equatable, Sendable {
    public let dampingRatio: CGFloat
    public let response: CGFloat

    public init(dampingRatio: CGFloat, response: CGFloat) {
        self.dampingRatio = dampingRatio
        self.response = response
    }

    /// SwiftUI's `Spring(duration:bounce:)`: the response is the duration, the damping ratio 1 − bounce
    public init(duration: CGFloat, bounce: CGFloat) {
        response = duration
        dampingRatio = bounce >= 0 ? (bounce == 0 ? 1 : 1 - bounce) : 1 / (1 + bounce)
    }

    /// The value and velocity `time` seconds after starting at `value` with `velocity`, moving toward `target`
    public func advance(value: CGFloat, velocity: CGFloat, target: CGFloat, time: CGFloat) -> (value: CGFloat, velocity: CGFloat) {
        let omega = 2 * .pi / response
        let x0 = value - target
        if dampingRatio < 1 {
            let zeta = dampingRatio
            let omegaD = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * time)
            let b = (velocity + zeta * omega * x0) / omegaD
            let cosine = cos(omegaD * time)
            let sine = sin(omegaD * time)
            let x = decay * (x0 * cosine + b * sine)
            let v = decay * ((b * omegaD - zeta * omega * x0) * cosine - (x0 * omegaD + zeta * omega * b) * sine)
            return (target + x, v)
        }
        if dampingRatio > 1 {
            let root = omega * (dampingRatio * dampingRatio - 1).squareRoot()
            let fast = -dampingRatio * omega - root
            let slow = -dampingRatio * omega + root
            let slowAmount = (velocity - fast * x0) / (slow - fast)
            let fastAmount = x0 - slowAmount
            let slowDecay = exp(slow * time)
            let fastDecay = exp(fast * time)
            return (
                target + slowAmount * slowDecay + fastAmount * fastDecay,
                slowAmount * slow * slowDecay + fastAmount * fast * fastDecay
            )
        }
        let decay = exp(-omega * time)
        let b = velocity + omega * x0
        return (target + (x0 + b * time) * decay, (b - omega * (x0 + b * time)) * decay)
    }
}

/// A spring's motion from a start state toward a target, as a function of time on a shared clock: it holds `from`
/// until `startTime` and rests exactly on `target` from `restTime` on
public struct GlassSpringCurve: Equatable, Sendable {
    public let startTime: CFTimeInterval
    public let from: CGFloat
    public let initialVelocity: CGFloat
    public let target: CGFloat
    public let spring: GlassSpring
    public let restTime: CFTimeInterval

    public init(
        startTime: CFTimeInterval,
        from: CGFloat,
        velocity: CGFloat = 0,
        target: CGFloat,
        spring: GlassSpring,
        restThreshold: CGFloat = 0.001
    ) {
        self.startTime = startTime
        self.from = from
        initialVelocity = velocity
        self.target = target
        self.spring = spring
        restTime = startTime + Self.computeSettleDuration(
            from: from, velocity: velocity, target: target, spring: spring, threshold: restThreshold
        )
    }

    public static func constant(_ value: CGFloat) -> GlassSpringCurve {
        GlassSpringCurve(startTime: 0, from: value, target: value, spring: GlassMotion.transition)
    }

    public func getValue(at time: CFTimeInterval) -> CGFloat {
        if time >= restTime { return target }
        if time <= startTime { return from }
        return spring.advance(value: from, velocity: initialVelocity, target: target, time: CGFloat(time - startTime)).value
    }

    public func getVelocity(at time: CFTimeInterval) -> CGFloat {
        if time >= restTime || time < startTime { return 0 }
        return spring.advance(value: from, velocity: initialVelocity, target: target, time: CGFloat(time - startTime)).velocity
    }

    /// From `time` on, toward `target` on `spring`, starting where and how fast this curve moves then
    public func makeRetargeted(at time: CFTimeInterval, to target: CGFloat, spring: GlassSpring) -> GlassSpringCurve {
        GlassSpringCurve(startTime: time, from: getValue(at: time), velocity: getVelocity(at: time), target: target, spring: spring)
    }

    private static func computeSettleDuration(
        from: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        spring: GlassSpring,
        threshold: CGFloat
    ) -> CFTimeInterval {
        let scale = max(1, abs(from - target))
        let valueThreshold = threshold * scale
        func isAtRest(_ value: CGFloat, _ velocity: CGFloat) -> Bool {
            abs(value - target) < valueThreshold && abs(velocity) < valueThreshold * 10
        }
        if isAtRest(from, velocity) { return 0 }
        var time: CFTimeInterval = 1.0 / 240
        while time < 10 {
            let state = spring.advance(value: from, velocity: velocity, target: target, time: CGFloat(time))
            if isAtRest(state.value, state.velocity) { return time }
            time += 1.0 / 240
        }
        return 10
    }
}

/// The scale pulse SwiftUI's glass gives a capsule whose content changes: it swells up to 20% (at most 16 pt per
/// axis) and settles, its height a little before its width
public struct GlassPulseCurve: Equatable, Sendable {
    /// The square root of the peak scale per axis, which the rise and each fall scale by in turn
    private let peakScaleRoot: CGSize
    private let rising: GlassSpringCurve
    private let fallingHeight: GlassSpringCurve
    private let fallingWidth: GlassSpringCurve
    /// The unit point of the shape that stays put
    public let anchor: CGPoint

    /// `strength` scales how far the shape swells past its size, per axis: 1 is the full swell, 0 none
    public init(
        size: CGSize,
        startTime: CFTimeInterval,
        anchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
        strength: CGSize = CGSize(width: 1, height: 1)
    ) {
        func computePeakScaleRoot(_ length: CGFloat, _ strength: CGFloat) -> CGFloat {
            guard length > 0 else { return 1 }
            let peak = min((length + 16) / length, GlassMotion.pulseMaxScale)
            return (1 + (peak - 1) * max(0, strength)).squareRoot()
        }
        peakScaleRoot = CGSize(
            width: computePeakScaleRoot(size.width, strength.width),
            height: computePeakScaleRoot(size.height, strength.height)
        )
        self.anchor = anchor
        rising = GlassSpringCurve(startTime: startTime, from: 0, target: 1, spring: GlassMotion.pulseUp)
        fallingHeight = GlassSpringCurve(
            startTime: startTime + GlassMotion.pulseDownHeightDelay, from: 1, target: 0, spring: GlassMotion.pulseDownHeight
        )
        fallingWidth = GlassSpringCurve(
            startTime: startTime + GlassMotion.pulseDownWidthDelay, from: 1, target: 0, spring: GlassMotion.pulseDownWidth
        )
    }

    public var restTime: CFTimeInterval {
        max(rising.restTime, fallingHeight.restTime, fallingWidth.restTime)
    }

    public func getScale(at time: CFTimeInterval) -> CGSize {
        func computeFactor(_ progress: CGFloat, _ root: CGFloat) -> CGFloat { 1 / root + (root - 1 / root) * progress }
        let rising = rising.getValue(at: time)
        return CGSize(
            width: computeFactor(rising, peakScaleRoot.width) * computeFactor(fallingWidth.getValue(at: time), peakScaleRoot.width),
            height: computeFactor(rising, peakScaleRoot.height) * computeFactor(fallingHeight.getValue(at: time), peakScaleRoot.height)
        )
    }
}

/// The motion of Liquid Glass capsules on a bar as SwiftUI's toolbar glass has it, after Telegram's measurements:
/// one spring moves and resizes a capsule, content swapped inside a kept capsule shrinks away and grows in, and a
/// capsule with no counterpart materializes or dematerializes in place
public enum GlassMotion {
    public static let transition = GlassSpring(duration: 0.416, bounce: 0.25)
    /// Appearing and disappearing without the bounce, as under Reduce Motion
    public static let materialize = GlassSpring(duration: 0.416, bounce: 0)
    /// Content swapped inside a kept capsule shrinks to and grows from this scale
    public static let matchScale: CGFloat = 0.2
    static let pulseUp = GlassSpring(duration: 0.292, bounce: 0.5)
    static let pulseDownHeight = GlassSpring(duration: 0.416, bounce: 0.416)
    static let pulseDownHeightDelay: CFTimeInterval = 0.113
    static let pulseDownWidth = GlassSpring(duration: 0.416, bounce: 0.5)
    static let pulseDownWidthDelay: CFTimeInterval = 0.142
    static let pulseMaxScale: CGFloat = 1.2

    /// The scale a capsule of `size` materializes from and dematerializes to: 1.2, growing by at most 16 pt per axis
    public static func getMaterializeScale(size: CGSize) -> CGSize {
        func computeAxisScale(_ length: CGFloat) -> CGFloat { length > 0 ? min(1.2, (length + 16) / length) : 1 }
        return CGSize(width: computeAxisScale(size.width), height: computeAxisScale(size.height))
    }

    /// The blur content gets as it shrinks away or before it grows in, at its smallest
    public static let blurRadius: CGFloat = 10
    /// A capsule collapsing into a neighbour waits this long before it moves; one growing out of a neighbour doesn't
    public static let matchedRemovalDelay: CFTimeInterval = 0.083
}

/// Calls `tick` with the current media time on every display frame until stopped. The display link goes with the
/// clock, so an owner only keeps the clock.
@MainActor
public final class GlassMotionClock {
    public static let glassFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    private var displayLink: CADisplayLink?
    private let frameRateRange: CAFrameRateRange?
    private let tick: @MainActor (CFTimeInterval) -> Void

    /// A nil `frameRateRange` leaves the rate to the system, as for a display link that doesn't set one
    public init(
        frameRateRange: CAFrameRateRange? = GlassMotionClock.glassFrameRateRange,
        tick: @escaping @MainActor (CFTimeInterval) -> Void
    ) {
        self.frameRateRange = frameRateRange
        self.tick = tick
    }

    /// Started and not paused
    public var isRunning: Bool { displayLink?.isPaused == false }

    /// The time from the frame being drawn to the next one, while `tick` runs
    public var frameDuration: CFTimeInterval {
        displayLink.map { $0.targetTimestamp - $0.timestamp } ?? 0
    }

    /// When the frame prepared in `tick` shows
    public var targetTimestamp: CFTimeInterval? {
        displayLink?.targetTimestamp
    }

    /// Starts the frames, or resumes them after `pause`
    public func start() {
        if let displayLink {
            displayLink.isPaused = false
            return
        }
        displayLink = .makeWeak(owner: self, frameRateRange: frameRateRange) { clock, _ in clock.step() }
    }

    /// Holds the frames and keeps the display link for `start`
    public func pause() {
        displayLink?.isPaused = true
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { displayLink?.invalidate() }

    fileprivate func step() {
        tick(CACurrentMediaTime())
    }
}
