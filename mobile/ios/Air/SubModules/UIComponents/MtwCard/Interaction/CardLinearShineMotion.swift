import Foundation
import CoreGraphics

/// A deliberate tilt triggers a complete pass. Input can request the next pass,
/// but cannot stop, reverse or balance a band that is already crossing the card.
struct CardLinearShineMotion {
    private(set) var position: CGFloat = 1
    private(set) var isAnimating = false
    private var direction: CGFloat = 1
    private var progress: Double = 0
    private var rate: Double = 1
    private var targetRate: Double = 1
    private var pendingSweep: (direction: CGFloat, speed: Double, angle: CGFloat?, isTouch: Bool)?
    private var isTouchSweep = false
    private var vectorMovement = CGPoint.zero
    private var lastTriggerVector: CGPoint?
    private var lastRequestedVector: CGPoint?
    private var touch: (point: CGPoint, angle: CGFloat, improved: Bool, aspectRatio: CGFloat, elapsed: TimeInterval)?
    private(set) var linearAngle: CGFloat?
    private var lastTriggerDirection: CGFloat?
    private var lastRequestedDirection: CGFloat?
    private var movement: CGFloat = 0
    private var previousPitch: CGFloat = 0
    private var previousRoll: CGFloat = 0
    private var idleTime: TimeInterval = 0
    static let duration: TimeInterval = 1
    static let directionalRate: Double = 1.7

    mutating func reset() { self = Self() }

    mutating func rebase(to pitch: CGFloat, roll: CGFloat = 0) {
        previousPitch = pitch
        previousRoll = roll
        recenterInput()
    }

    mutating func recenterInput() {
        movement = 0
        vectorMovement = .zero
        lastTriggerVector = nil
        lastTriggerDirection = nil
        idleTime = 0
    }

    mutating func press() {
        guard !isAnimating else { return }
        recenterInput()
        start(direction: position >= 0 ? 1 : -1, speed: 0)
    }

    mutating func beginDirectionalPress(at point: CGPoint, angle: CGFloat,
                                        improved: Bool = false, aspectRatio: CGFloat = 358 / 208) {
        // A fresh touch takes priority over any active or queued tilt sweep.
        pendingSweep = nil
        recenterInput()
        touch = (point, angle, improved, aspectRatio, 0)
        let pose = Self.touchPose(at: point, angle: angle, improved: improved, aspectRatio: aspectRatio)
        start(direction: pose.direction, speed: 0, angle: pose.angle, isTouch: true)
    }

    mutating func moveDirectionalPress(to point: CGPoint) {
        touch?.point = point
    }

    mutating func endDirectionalPress(cancelled: Bool = false) {
        guard let touch else { return }
        self.touch = nil
        recenterInput()
        guard !cancelled, touch.elapsed >= 0.45 else { return }
        let pose = Self.touchPose(at: touch.point, angle: touch.angle, improved: touch.improved, aspectRatio: touch.aspectRatio)
        if isAnimating {
            pendingSweep = (-pose.direction, 0, pose.angle, true)
            lastRequestedDirection = -pose.direction
        } else {
            start(direction: -pose.direction, speed: 0, angle: pose.angle, isTouch: true)
        }
    }

    private static func touchPose(at point: CGPoint, angle: CGFloat, improved: Bool,
                                  aspectRatio: CGFloat) -> (direction: CGFloat, angle: CGFloat) {
        if improved {
            // The shader normal is (sin(angle), cos(angle)). Convert the normalized
            // touch back to card space: cardinal touches stay cardinal, corners
            // interpolate continuously. An exact center touch uses a vertical pass.
            let x = point.x * max(0.01, aspectRatio), y = point.y
            return (1, hypot(x, y) < 0.001 ? 0 : atan2(x, y) * 180 / .pi)
        }
        return (point.y >= 0 ? 1 : -1, point.x * point.y < 0 ? -angle : angle)
    }

    mutating func advance(pitch: CGFloat, roll: CGFloat = 0,
                          pitchSensitivity: CGFloat = 0.89, rollSensitivity: CGFloat = 0.68,
                          triggerAngle: CGFloat = 25, returnAngle: CGFloat = 25,
                          angularSpeed: Double? = nil,
                          suppressTilt: Bool = false, improved: Bool = false,
                          by dt: TimeInterval) {
        guard dt > 0 else { return }
        let ignoresTilt = suppressTilt || touch != nil || (isAnimating && isTouchSweep)
        let pitchDelta = pitch - previousPitch
        let rollDelta = roll - previousRoll
        previousPitch = pitch
        previousRoll = roll
        let delta = pitchDelta * pitchSensitivity - rollDelta * rollSensitivity
        let speed = angularSpeed ?? hypot(pitchDelta * pitchSensitivity, rollDelta * rollSensitivity) / dt
        touch?.elapsed += dt
        advanceAnimation(by: dt, speed: speed)
        if ignoresTilt {
            // Discard input through the final touch-animation frame so resuming
            // device control requires fresh travel from the current pose.
            recenterInput()
            return
        }
        idleTime = hypot(pitchDelta, rollDelta) / dt < 0.035 ? idleTime + dt : 0
        if idleTime >= 0.5 {
            recenterInput()
            return
        }
        if improved {
            advanceDirectionalTilt(delta: CGPoint(x: -rollDelta * rollSensitivity,
                                                  y: pitchDelta * pitchSensitivity),
                                   speed: speed, triggerAngle: triggerAngle, returnAngle: returnAngle)
            return
        }
        movement += delta
        // Follow the furthest pose after firing: continuing the same gesture
        // cannot repeat, and a return requires fresh travel from that pose.
        if let lastTriggerDirection, movement * lastTriggerDirection > 0 { movement = 0 }
        let nextDirection: CGFloat = movement > 0 ? 1 : -1
        let threshold = (lastRequestedDirection == -nextDirection ? returnAngle : triggerAngle) * .pi / 180
        guard abs(movement) + 1e-12 >= max(0.01, threshold) else { return }
        movement = 0
        lastTriggerDirection = nextDirection
        if isAnimating {
            // Keep at most one deliberate return. Never interrupt the visible pass.
            if pendingSweep == nil {
                pendingSweep = (nextDirection, speed, nil, false)
                lastRequestedDirection = nextDirection
            }
        } else {
            start(direction: nextDirection, speed: speed)
        }
    }

    private mutating func advanceDirectionalTilt(delta: CGPoint, speed: Double,
                                                 triggerAngle: CGFloat, returnAngle: CGFloat) {
        vectorMovement.x += delta.x
        vectorMovement.y += delta.y
        // Track the furthest pose along the last fired direction, while retaining
        // perpendicular movement. Pitch and roll must never cancel one another.
        if let last = lastTriggerVector {
            let continuing = vectorMovement.x * last.x + vectorMovement.y * last.y
            if continuing > 0 {
                vectorMovement.x -= continuing * last.x
                vectorMovement.y -= continuing * last.y
            }
        }
        let distance = hypot(vectorMovement.x, vectorMovement.y)
        let returning = lastRequestedVector.map { vectorMovement.x * $0.x + vectorMovement.y * $0.y < 0 } ?? false
        let threshold = max(0.01, (returning ? returnAngle : triggerAngle) * .pi / 180)
        guard distance + 1e-12 >= threshold else { return }
        let normal = CGPoint(x: vectorMovement.x / distance, y: vectorMovement.y / distance)
        let angle = atan2(normal.x, normal.y) * 180 / .pi
        vectorMovement = .zero
        lastTriggerVector = normal
        if isAnimating {
            if pendingSweep == nil {
                pendingSweep = (1, speed, angle, false)
                lastRequestedVector = normal
            }
        } else {
            lastRequestedVector = normal
            start(direction: 1, speed: speed, angle: angle)
        }
    }

    private mutating func start(direction: CGFloat, speed: Double, angle: CGFloat? = nil, isTouch: Bool = false) {
        linearAngle = angle
        isTouchSweep = isTouch
        self.direction = direction
        lastRequestedDirection = direction
        position = direction
        progress = 0
        rate = Self.animationRate(for: speed)
        targetRate = rate
        isAnimating = true
    }

    private static func animationRate(for speed: Double) -> Double {
        // Deliberate, gentle movement takes one second; fast tilts take 400 ms.
        1 + 1.5 * min(1, max(0, (speed - 0.35) / 2.15))
    }

    private mutating func advanceAnimation(by dt: TimeInterval, speed: Double) {
        guard isAnimating else { return }
        let isDirectional = isTouchSweep
        if isDirectional {
            progress += dt * Self.directionalRate / Self.duration
        } else {
            // Input may accelerate a pass, never slow it down enough to catch it.
            targetRate = max(targetRate, Self.animationRate(for: speed))
            let decay = exp(-dt / 0.08)
            progress += (targetRate * dt + (rate - targetRate) * 0.08 * (1 - decay)) / Self.duration
            rate = targetRate + (rate - targetRate) * decay
        }
        if progress >= 1 {
            position = -direction
            isAnimating = false
            if let pendingSweep {
                self.pendingSweep = nil
                start(direction: pendingSweep.direction, speed: pendingSweep.speed, angle: pendingSweep.angle, isTouch: pendingSweep.isTouch)
            }
        } else {
            // Constant touch travel brings the off-card band into view promptly;
            // the soft band edges already ease its appearance and disappearance.
            let travel = isDirectional ? progress : progress * progress * (3 - 2 * progress)
            position = direction * (1 - 2 * travel)
        }
    }
}
