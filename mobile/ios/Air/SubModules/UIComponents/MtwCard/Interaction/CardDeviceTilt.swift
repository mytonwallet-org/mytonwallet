import CoreMotion
import UIKit

struct CardDeviceTilt {
    private var reference: CMQuaternion?
    private var orientation: UIInterfaceOrientation = .unknown
    private var idleDuration: TimeInterval = 0
    private(set) var pitch: CGFloat = 0
    private(set) var roll: CGFloat = 0
    private(set) var pitchAngularSpeed = 0.0
    private(set) var rollAngularSpeed = 0.0
    private(set) var didRecenter = false

    mutating func reset() {
        reference = nil
        idleDuration = 0
        pitch = 0
        roll = 0
        pitchAngularSpeed = 0
        rollAngularSpeed = 0
        didRecenter = false
    }

    mutating func update(attitude q: CMQuaternion, rotationRate: CMRotationRate,
                         orientation: UIInterfaceOrientation, touchActive: Bool,
                         lightIsSettled: Bool, sensitivity: CGFloat, by dt: TimeInterval) -> (tilt: CGPoint, angularSpeed: Double) {
        didRecenter = false
        if self.orientation != orientation {
            self.orientation = orientation
            reset()
        }
        // Use raw motion, before the light's dead zone, so slow deliberate tilts
        // and held touches cannot silently move the reference pose.
        let speed = hypot(rotationRate.x, rotationRate.y)
        pitchAngularSpeed = abs(orientation.isLandscape ? rotationRate.y : rotationRate.x)
        rollAngularSpeed = abs(orientation.isLandscape ? rotationRate.x : rotationRate.y)
        if !touchActive, hypot(speed, rotationRate.z) < 0.035 {
            idleDuration += max(0, dt)
        } else {
            idleDuration = 0
        }
        if reference == nil || (idleDuration >= 3 && lightIsSettled) {
            reference = q
            pitch = 0
            roll = 0
            didRecenter = true
            return (.zero, 0)
        }
        guard let r = reference else { return (.zero, 0) }
        // inverse(reference) × sample works from any resting pose, including flat.
        let x = r.w * q.x - r.x * q.w - r.y * q.z + r.z * q.y
        let y = r.w * q.y + r.x * q.z - r.y * q.w - r.z * q.x
        let w = r.w * q.w + r.x * q.x + r.y * q.y + r.z * q.z
        let sign = w < 0 ? -1.0 : 1.0
        let horizontal = CGFloat(2 * asin(min(1, max(-1, y * sign))))
        let vertical = CGFloat(2 * asin(min(1, max(-1, x * sign))))
        let screenTilt: CGPoint
        switch orientation {
        case .landscapeLeft: screenTilt = CGPoint(x: vertical, y: -horizontal)
        case .landscapeRight: screenTilt = CGPoint(x: -vertical, y: horizontal)
        case .portraitUpsideDown: screenTilt = CGPoint(x: -horizontal, y: -vertical)
        default: screenTilt = CGPoint(x: horizontal, y: vertical)
        }
        pitch = screenTilt.y
        roll = screenTilt.x
        return Self.response(to: screenTilt, angularSpeed: speed, sensitivity: sensitivity)
    }

    /// A radial dead zone gates direction and activity before temporal smoothing.
    static func response(to tilt: CGPoint, angularSpeed: Double, sensitivity: CGFloat) -> (tilt: CGPoint, angularSpeed: Double) {
        let angle = hypot(tilt.x, tilt.y)
        let threshold = CGFloat.pi / 45 // Four degrees from the resting pose.
        guard angle > threshold else { return (.zero, 0) }
        let excess = angle - threshold
        let ramp = min(1, excess / threshold)
        let gain = ramp * ramp * (3 - 2 * ramp)
        let scale = excess / angle * gain * sensitivity
        return (CGPoint(x: min(1, max(-1, tilt.x * scale)), y: min(1, max(-1, tilt.y * scale))),
                angularSpeed * Double(gain))
    }
}
