import Foundation
import CoreGraphics

/// A pose-driven environment light, like Gram's continuous radial reflection.
/// Slow movement is meaningful too: no trigger threshold, looping sweep or idle expiry.
struct CardCrystalGyroMotion {
    private var value = SIMD2<Double>.zero
    private var velocity = SIMD2<Double>.zero
    private var opacity = 0.0
    private(set) var hasSample = false
    var tilt: CGPoint { CGPoint(x: value.x, y: value.y) }
    var pose: CardCrystalPlayMotion.Pose? {
        guard hasSample else { return nil }
        return .init(position: CGFloat(0.38 * (0.84 * value.x + 0.6 * value.y)),
                     angle: CGFloat(61 + 40 * value.x - 24 * value.y), opacity: CGFloat(opacity))
    }
    mutating func reset() { self = Self() }
    mutating func advance(pitch: CGFloat, roll: CGFloat, sensitivity: CGFloat, by dt: TimeInterval) {
        guard dt > 0, pitch.isFinite, roll.isFinite else { return }
        hasSample = true
        let gain = Double(max(0, sensitivity)) / 0.65
        let target = SIMD2(tanh(Double(roll) * gain), tanh(Double(pitch) * gain))
        // Exact critically damped integration follows intent and filters hand tremor.
        let frequency = 18.0
        let offset = value - target
        let term = velocity + offset * frequency
        let decay = exp(-frequency * dt)
        value = target + (offset + term * dt) * decay
        velocity = (velocity - term * frequency * dt) * decay
        opacity += (1 - opacity) * (1 - exp(-dt / 0.20))
        if opacity > 0.9999 { opacity = 1 }
    }
}
