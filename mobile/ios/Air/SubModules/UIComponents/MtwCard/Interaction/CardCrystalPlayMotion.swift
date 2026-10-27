import Foundation
import CoreGraphics

/// One reflection changes from the current light pose into a finger-controlled light.
/// On release it returns to the live gyro pose, or fades out in touch mode.
struct CardCrystalPlayMotion {
    struct Pose: Equatable {
        var position: CGFloat
        var angle: CGFloat
        var opacity: CGFloat
    }
    private(set) var pose: Pose?
    private(set) var isHeld = false
    private var target = Pose(position: 0, angle: 61, opacity: 1)
    private var releaseElapsed: TimeInterval = 0
    private var releaseOpacity: CGFloat = 0
    private var releasePose: Pose?
    private var returnsToGyro = false
    var isAnimating: Bool {
        guard let pose else { return false }
        return !isHeld || abs(pose.position - target.position) > 0.0001
            || abs(Self.angleDelta(target.angle, pose.angle)) > 0.01 || pose.opacity < 0.9999
    }

    mutating func begin(at point: CGPoint, from pose: Pose) {
        guard !isHeld else { return }
        self.pose = pose
        isHeld = true
        releaseElapsed = 0
        releasePose = nil
        returnsToGyro = false
        move(to: point)
    }
    mutating func move(to point: CGPoint) {
        guard isHeld else { return }
        let x = min(1, max(-1, point.x)), y = min(1, max(-1, point.y))
        // Keep the source in view at every edge. Both axes affect its direction
        // as well as its position, even when geometric card tilt is set to zero.
        target = Pose(position: 0.42 * (0.8 * x + 0.6 * y),
                      angle: 61 + 28 * x - 12 * y, opacity: 1)
    }
    mutating func release(to gyro: Pose? = nil) {
        guard isHeld else { return }
        isHeld = false
        releaseElapsed = 0
        releaseOpacity = pose?.opacity ?? 0
        releasePose = pose
        returnsToGyro = gyro != nil
    }
    mutating func reset() { self = Self() }
    mutating func advance(by dt: TimeInterval, returningTo gyro: Pose? = nil) {
        guard dt > 0, var pose else { return }
        if isHeld {
            let amount = CGFloat(1 - exp(-dt / 0.10))
            pose.position += (target.position - pose.position) * amount
            pose.angle += Self.angleDelta(target.angle, pose.angle) * amount
            pose.opacity += (1 - pose.opacity) * amount
            if abs(pose.position - target.position) < 0.0001 { pose.position = target.position }
            if abs(Self.angleDelta(target.angle, pose.angle)) < 0.01 { pose.angle = target.angle }
            if pose.opacity > 0.9999 { pose.opacity = 1 }
            self.pose = pose
        } else {
            releaseElapsed = min(0.4, releaseElapsed + dt)
            let t = CGFloat(releaseElapsed / 0.4)
            let amount = t * t * (3 - 2 * t)
            if returnsToGyro, let gyro, let releasePose {
                // Interpolate one light into the current sensor pose, not two overlays.
                pose.position = releasePose.position + (gyro.position - releasePose.position) * amount
                pose.angle = releasePose.angle + Self.angleDelta(gyro.angle, releasePose.angle) * amount
                pose.opacity = releasePose.opacity + (gyro.opacity - releasePose.opacity) * amount
            } else {
                pose.opacity = releaseOpacity * (1 - amount)
            }
            self.pose = releaseElapsed >= 0.4 ? nil : pose
        }
    }
    private static func angleDelta(_ to: CGFloat, _ from: CGFloat) -> CGFloat {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}
