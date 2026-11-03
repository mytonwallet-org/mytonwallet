import Foundation
import UIComponents

/// A damped oscillator stepped in closed form by `GlassSpring`. `response` is its undamped period in seconds and
/// `damping` its damping ratio, as in Telegram's chat list swipe, whose motion this file ports.
struct AgentThreadSwipeSpring {
    var value: Double = 0
    var velocity: Double = 0
    var target: Double = 0
    var response: Double = 0.5
    var damping: Double = 1

    var isAtRest: Bool { abs(value - target) < 0.001 && abs(velocity) < 0.01 }

    mutating func snap(to value: Double) {
        self.value = value
        target = value
        velocity = 0
    }

    mutating func advance(by dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        if isAtRest {
            snap(to: target)
            return
        }
        let spring = GlassSpring(dampingRatio: max(0.01, damping), response: max(0.01, response))
        let next = spring.advance(value: value, velocity: velocity, target: target, time: dt)
        value = next.value
        velocity = next.velocity
    }
}

/// The geometry a swipe is measured against. Distances run from the row's trailing edge toward its leading edge.
struct AgentThreadSwipeParameters {
    var width: Double = 0
    var buttonWidth: Double = 50
    var spacing: Double = 10
    var edgeInset: Double = 10
    var count: Int = 0
    var displayScale: Double = 2

    var openDistance: Double {
        count == 0 ? 0 : 2 * edgeInset + Double(count) * buttonWidth + Double(count - 1) * spacing
    }

    /// The distance that arms the outermost, destructive action: nearly the whole row
    var confirmationDistance: Double {
        let scale = max(1, displayScale)
        return (max(openDistance, width - 29) * scale).rounded() / scale
    }

    /// A finger this close to the leading edge arms the action before the confirmation distance
    var edgeZone: Double { width >= 414 ? 90 : (width == 375 ? 75 : 50) }

    func getEdgeFraction(velocity: Double) -> Double {
        min(width >= 414 ? 0.75 : 0.8, max(width >= 414 ? 0.5 : 0.66, abs(velocity) / 2500))
    }

    /// Finger travel past the confirmation distance, or against the reveal, moves the row less than the finger
    func applyResistance(to distance: Double, isInverse: Bool = false) -> Double {
        let exponent = isInverse ? 1 / 0.7 : 0.7
        if distance < 0 { return -pow(-distance, exponent) }
        if distance > confirmationDistance { return confirmationDistance + pow(distance - confirmationDistance, exponent) }
        return distance
    }
}

struct AgentThreadSwipeButtonGeometry {
    /// Distance of the center from the row's trailing edge. Index zero is the outermost action.
    var center: Double
    var width: Double
    var scale: Double
    var opacity: Double

    static func calculate(reveal: Double, parameters p: AgentThreadSwipeParameters) -> [AgentThreadSwipeButtonGeometry] {
        let distance = max(0, reveal)
        return (0..<p.count).map { index in
            let outside = p.edgeInset + Double(index) * (p.buttonWidth + p.spacing)
            let end = outside + p.buttonWidth + p.edgeInset
            let start = end - p.buttonWidth + 2 * p.spacing
            var scale = min(1, max(0, (distance - start) / max(1, end - start)))
            var opacity = scale
            var width = p.buttonWidth
            var center = outside + width / 2
            if index == 0 {
                // The outermost action stretches over everything revealed past the open distance
                width += max(0, distance - p.openDistance)
                center = p.edgeInset + width / 2
            }
            if distance > p.openDistance + 0.001 {
                scale = 1
                if index == 0 {
                    opacity = 1
                } else {
                    center += distance - p.openDistance
                    // The other actions fade from full opacity at the open distance to 30% where the swipe arms
                    let stretch = (distance - p.openDistance) / max(1, p.confirmationDistance - p.openDistance)
                    opacity = 1 - min(1, stretch) * 0.7
                }
            }
            return AgentThreadSwipeButtonGeometry(center: center, width: width, scale: scale, opacity: opacity < 0.01 ? 0 : opacity)
        }
    }
}

/// Telegram's chat list swipe for a row whose outermost action is destructive: the row follows the finger, past the
/// actions with resistance, and a swipe across nearly the whole row arms that action, which then runs on release
struct AgentThreadSwipeMotion {
    enum State: Equatable {
        case closed
        case dragging
        case settling(isOpening: Bool)
        case open
    }

    var parameters = AgentThreadSwipeParameters()
    private(set) var state: State = .closed
    private(set) var isArmed = false
    /// The revealed distance
    private(set) var body = AgentThreadSwipeSpring()
    /// The rounding of the card the row becomes
    private(set) var surface = AgentThreadSwipeSpring(response: 0.66, damping: 0.95)
    /// The card's opacity, which the row's separator gives way to
    private(set) var surfaceOpacity = AgentThreadSwipeSpring(response: 0.66, damping: 0.95)
    /// Moves the armed action's icon to the end that follows the finger
    private(set) var expansion = AgentThreadSwipeSpring()
    private(set) var scales: [AgentThreadSwipeSpring] = []
    private(set) var opacities: [AgentThreadSwipeSpring] = []
    private var initial = 0.0
    private var confirmationAdjustment = 0.0
    private var gestureOriginAdjustment = 0.0
    private var isSpringContinuing = false

    var isAtRest: Bool {
        body.isAtRest && surface.isAtRest && surfaceOpacity.isAtRest && expansion.isAtRest
            && scales.allSatisfy(\.isAtRest) && opacities.allSatisfy(\.isAtRest)
    }

    var isOpenOrOpening: Bool { state == .dragging || body.target > 0 }

    var buttonGeometry: [AgentThreadSwipeButtonGeometry] {
        AgentThreadSwipeButtonGeometry.calculate(reveal: body.value, parameters: parameters)
    }

    mutating func configure(_ parameters: AgentThreadSwipeParameters) {
        self.parameters = parameters
        if scales.count != parameters.count {
            scales = Array(repeating: AgentThreadSwipeSpring(response: 0.5, damping: 0.7), count: parameters.count)
            opacities = Array(repeating: AgentThreadSwipeSpring(), count: parameters.count)
        }
        retargetButtons()
    }

    /// The spring that carries the row while the finger holds it: quick, so a jump to the armed distance catches up with
    /// the finger at once
    static let draggingResponse = 0.18
    static let settlingResponse = 0.5

    mutating func begin() {
        // A row grabbed while it settles stops where it is and follows the finger from there
        body.snap(to: body.value)
        body.response = Self.draggingResponse
        isSpringContinuing = false
        initial = parameters.applyResistance(to: body.value, isInverse: true)
        gestureOriginAdjustment = 0
        confirmationAdjustment = 0
        isArmed = false
        state = .dragging
        surface.target = 1
        surfaceOpacity.target = 1
    }

    mutating func change(translation: Double, velocity: Double, distanceFromCommitEdge: Double, isReduceMotionEnabled: Bool) {
        guard state == .dragging else { return }
        var proposed = initial + translation + gestureOriginAdjustment + confirmationAdjustment
        let confirmation = parameters.confirmationDistance
        var shouldArm = proposed >= confirmation
        if !shouldArm && proposed > confirmation * parameters.getEdgeFraction(velocity: velocity) && distanceFromCommitEdge < parameters.edgeZone {
            shouldArm = true
            if confirmationAdjustment == 0 {
                confirmationAdjustment = confirmation - proposed
                proposed = confirmation
            }
        }
        isArmed = shouldArm
        if shouldArm && !isReduceMotionEnabled {
            // Once armed, the row moves on a spring for the rest of the touch, also after disarming
            isSpringContinuing = true
        }
        let target = parameters.applyResistance(to: proposed)
        if (shouldArm || isSpringContinuing) && !isReduceMotionEnabled {
            body.target = target
        } else {
            body.snap(to: target)
        }
        retargetButtons()
        // The actions pop in as the finger uncovers them, with the row rather than after it
        snapButtons()
        if isReduceMotionEnabled { snapToTargets() }
    }

    /// Settles open or closed and reports whether the release runs the armed action
    @discardableResult
    mutating func end(translation: Double, velocity: Double, isCancelled: Bool, animated: Bool) -> Bool {
        guard state == .dragging else { return false }
        let shouldCommit = !isCancelled && isArmed
        let shouldOpen = shouldCommit || (abs(velocity) > 50 ? velocity > 50 : initial + translation + gestureOriginAdjustment > parameters.openDistance / 2)
        settle(to: shouldOpen ? parameters.openDistance : 0, velocity: velocity, animated: animated)
        return shouldCommit
    }

    mutating func settle(to target: Double, velocity: Double, animated: Bool) {
        state = .settling(isOpening: target > 0)
        isArmed = false
        isSpringContinuing = false
        body.response = Self.settlingResponse
        body.target = target
        body.velocity = Self.getTransferredVelocity(velocity, position: body.value, target: target)
        surface.target = target > 0 ? 1 : 0
        surfaceOpacity.target = surface.target
        retargetButtons()
        if !animated {
            snapToTargets()
            finishSettling()
        }
    }

    mutating func advance(by dt: Double) {
        if state != .dragging || isArmed || isSpringContinuing { body.advance(by: dt) }
        surface.advance(by: dt)
        surfaceOpacity.advance(by: dt)
        retargetButtons()
        expansion.advance(by: dt)
        for index in scales.indices {
            scales[index].advance(by: dt)
            opacities[index].advance(by: dt)
        }
        if isAtRest {
            snapToTargets()
            finishSettling()
        }
    }

    mutating func reset() {
        let parameters = self.parameters
        self = AgentThreadSwipeMotion()
        configure(parameters)
    }

    /// A release's velocity carries into the settle only toward its target, and at most at 100 times the remaining distance per second
    static func getTransferredVelocity(_ velocity: Double, position: Double, target: Double) -> Double {
        let remaining = target - position
        guard abs(remaining) > 0.000001 else { return 0 }
        return min(100, max(0, velocity / remaining)) * remaining
    }

    private mutating func snapButtons() {
        for index in scales.indices {
            scales[index].snap(to: scales[index].target)
            opacities[index].snap(to: opacities[index].target)
        }
    }

    private mutating func snapToTargets() {
        body.snap(to: body.target)
        surface.snap(to: surface.target)
        surfaceOpacity.snap(to: surfaceOpacity.target)
        expansion.snap(to: expansion.target)
        for index in scales.indices {
            scales[index].snap(to: scales[index].target)
            opacities[index].snap(to: opacities[index].target)
        }
    }

    private mutating func retargetButtons() {
        expansion.target = isArmed ? 1 : 0
        let geometry = AgentThreadSwipeButtonGeometry.calculate(reveal: body.target, parameters: parameters)
        for index in scales.indices {
            scales[index].target = geometry[index].scale
            opacities[index].target = geometry[index].opacity
            opacities[index].response = state == .dragging ? 0.25 : 0.5
        }
    }

    private mutating func finishSettling() {
        if case let .settling(isOpening) = state {
            state = isOpening ? .open : .closed
        }
    }
}
