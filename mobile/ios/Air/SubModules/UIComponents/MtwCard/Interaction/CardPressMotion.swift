import Foundation
import QuartzCore

/// One pose drives both the card transform and its light response.
struct CardPressMotion {
    var depth: Double = 0.7
    private(set) var value = SIMD3<Double>.zero
    private var velocity = SIMD3<Double>.zero
    private var target = SIMD3<Double>.zero

    var isEngaged: Bool { target.z > 0 || value.z > 0.00015 }
    var isSettled: Bool {
        let delta = value - target
        return max(abs(delta.x), abs(delta.y), abs(delta.z)) < 0.00015
            && max(abs(velocity.x), abs(velocity.y), abs(velocity.z)) < 0.002
    }

    mutating func press(at point: CGPoint) {
        var x = min(1, max(-1, Double(point.x)))
        var y = min(1, max(-1, Double(point.y)))
        let length = max(1, hypot(x, y))
        x /= length
        y /= length
        target = SIMD3(x, y, 1)
    }

    mutating func release() { target = .zero }

    mutating func reset() {
        value = .zero
        velocity = .zero
        target = .zero
    }

    mutating func advance(by dt: TimeInterval) {
        // Exact critically damped spring integration: same response at 30 and 60 Hz.
        let frequency = target.z > 0 ? 28.0 : 14.0
        let offset = value - target
        let term = velocity + offset * frequency
        let decay = exp(-frequency * dt)
        value = target + (offset + term * dt) * decay
        velocity = (velocity - term * frequency * dt) * decay
        if isSettled {
            value = target
            velocity = .zero
        }
    }

    private var rotation: CATransform3D {
        let angle = CGFloat(8 * Double.pi / 180 * depth)
        // +z faces the viewer. At the touched corner, these signs move z away.
        let xRotation = CATransform3DMakeRotation(-CGFloat(value.y) * angle, 1, 0, 0)
        return CATransform3DRotate(xRotation, CGFloat(value.x) * angle, 0, 1, 0)
    }

    var lightTilt: CGPoint {
        let normal = rotation
        let referenceAngle = sin(CGFloat.pi / 15)
        return CGPoint(x: normal.m31 / referenceAngle, y: normal.m32 / referenceAngle)
    }

    func transform(cardWidth: CGFloat) -> CATransform3D {
        guard value != .zero, depth > 0 else { return CATransform3DIdentity }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(650, cardWidth * 2.5)
        let push = CGFloat(value.z * depth)
        let translation = CATransform3DMakeTranslation(0, 0, -4 * push)
        let pose = CATransform3DConcat(rotation, translation)
        let scale = 1 - 0.01 * push
        return CATransform3DScale(CATransform3DConcat(pose, perspective), scale, scale, 1)
    }
}
