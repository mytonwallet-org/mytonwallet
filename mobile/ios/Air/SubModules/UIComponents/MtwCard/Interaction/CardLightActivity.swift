import Foundation
import CoreGraphics

public struct CardSurfaceLight: Equatable, Sendable {
    public struct TouchSpot: Equatable, Sendable {
        /// Offset from card center, normalized to its half-width / half-height.
        public var position: CGPoint
        public var opacity: CGFloat
    }

    /// Independent continuous border light: also works with surface shine and tilt disabled.
    var gramReflection: CardGramReflectionPose?
    public var borderTilt: CGPoint?
    public var tilt: CGPoint = .zero
    public var activity: CGFloat = 0
    public var press: CGFloat = 0
    /// Normalized band travel: -1 is beyond the top left, +1 beyond the bottom right for the default diagonal.
    public var linearPosition: CGFloat?
    /// Optional touch override in degrees above horizontal; negative mirrors the diagonal.
    public var linearAngle: CGFloat?
    public var touchSpot: TouchSpot?

    public init(tilt: CGPoint = .zero, activity: CGFloat = 0, press: CGFloat = 0, linearPosition: CGFloat? = nil, linearAngle: CGFloat? = nil, touchSpot: TouchSpot? = nil, borderTilt: CGPoint? = nil) {
        self.borderTilt = borderTilt
        self.tilt = tilt
        self.activity = activity
        self.press = press
        self.linearPosition = linearPosition
        self.linearAngle = linearAngle
        self.touchSpot = touchSpot
    }
}

extension CardSurfaceLight {
    /// Compare with the last published pose, so slow motion accumulates rather than disappears.
    func visuallyMatches(_ other: Self) -> Bool {
        func close(_ a: CGFloat, _ b: CGFloat, _ epsilon: CGFloat = 0.00015) -> Bool { abs(a - b) <= epsilon }
        func point(_ a: CGPoint, _ b: CGPoint) -> Bool { close(a.x,b.x) && close(a.y,b.y) }
        func optionalPoint(_ a: CGPoint?, _ b: CGPoint?) -> Bool {
            switch (a,b) { case (nil,nil): return true; case let (a?,b?): return point(a,b); default: return false }
        }
        func optionalScalar(_ a: CGFloat?, _ b: CGFloat?, _ epsilon: CGFloat) -> Bool {
            switch (a,b) { case (nil,nil): return true; case let (a?,b?): return close(a,b,epsilon); default: return false }
        }
        guard point(tilt,other.tilt), optionalPoint(borderTilt,other.borderTilt),
              close(activity,other.activity,0.0005), close(press,other.press,0.0005),
              optionalScalar(linearPosition,other.linearPosition,0.00015),
              optionalScalar(linearAngle,other.linearAngle,0.01) else { return false }
        switch (touchSpot,other.touchSpot) {
        case (nil,nil): break
        case let (a?,b?): if !point(a.position,b.position) || !close(a.opacity,b.opacity,0.0005) { return false }
        default: return false
        }
        switch (gramReflection,other.gramReflection) {
        case (nil,nil): return true
        case let (a?,b?):
            let angle = atan2(sin(a.rotation-b.rotation),cos(a.rotation-b.rotation))
            return abs(angle) <= 0.0002 && abs(a.balance-b.balance) <= 0.00015 && abs(a.energy-b.energy) <= 0.0005
                && abs(a.light.x-b.light.x) <= 0.00015 && abs(a.light.y-b.light.y) <= 0.00015 && abs(a.light.z-b.light.z) <= 0.00015
                && abs(a.view.x-b.view.x) <= 0.00015 && abs(a.view.y-b.view.y) <= 0.00015 && abs(a.view.z-b.view.z) <= 0.00015
        default: return false
        }
    }

    static let resumeDuration: TimeInterval = 0.28

    static func resumeProgress(elapsed: TimeInterval) -> CGFloat {
        let t = min(1, max(0, elapsed / resumeDuration))
        return t * t * (3 - 2 * t)
    }

    func interpolated(from start: Self, progress: CGFloat) -> Self {
        let p = min(1, max(0, progress))
        if p == 0 { return start }
        if p == 1 { return self }
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        func point(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y))
        }
        var result = self
        result.tilt = point(start.tilt, tilt)
        result.activity = mix(start.activity, activity)
        result.press = mix(start.press, press)
        if start.borderTilt != nil || borderTilt != nil {
            result.borderTilt = point(start.borderTilt ?? start.tilt, borderTilt ?? tilt)
        }
        if start.linearPosition != nil || linearPosition != nil {
            result.linearPosition = mix(start.linearPosition ?? -start.tilt.y, linearPosition ?? -tilt.y)
        }
        if start.linearAngle != nil || linearAngle != nil {
            result.linearAngle = mix(start.linearAngle ?? 61, linearAngle ?? 61)
        }
        if let spot = touchSpot ?? start.touchSpot {
            result.touchSpot = .init(position: point(start.touchSpot?.position ?? spot.position, touchSpot?.position ?? spot.position),
                                     opacity: mix(start.touchSpot?.opacity ?? 0, touchSpot?.opacity ?? 0))
        }
        if start.gramReflection != nil || gramReflection != nil {
            let a = start.gramReflection ?? CardGramReflectionPose(), b = gramReflection ?? CardGramReflectionPose()
            let delta = atan2(sin(b.rotation - a.rotation), cos(b.rotation - a.rotation))
            result.gramReflection = .init(rotation: a.rotation + delta * Double(p),
                balance: a.balance + (b.balance - a.balance) * Double(p),
                energy: a.energy + (b.energy - a.energy) * Double(p),
                light: a.light + (b.light - a.light) * Float(p), view: a.view + (b.view - a.view) * Float(p))
        }
        return result
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
