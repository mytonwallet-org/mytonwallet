import Foundation
import Testing
@testable import UIComponents

struct GlassSpringTests {
    /// The closed form against the spring's equation x″ = −ω²x − 2ζωx′ integrated in small steps
    @Test(arguments: [0.4, 1, 4.56])
    func followsTheSpringEquation(dampingRatio: Double) {
        let spring = GlassSpring(dampingRatio: dampingRatio, response: 0.5)
        let omega = 2 * Double.pi / 0.5
        func acceleration(_ x: Double, _ v: Double) -> Double { -omega * omega * x - 2 * dampingRatio * omega * v }

        var x = 40.0
        var v = -300.0
        let step = 1e-5
        for index in 1...100_000 {
            let k1 = (v, acceleration(x, v))
            let k2 = (v + step / 2 * k1.1, acceleration(x + step / 2 * k1.0, v + step / 2 * k1.1))
            let k3 = (v + step / 2 * k2.1, acceleration(x + step / 2 * k2.0, v + step / 2 * k2.1))
            let k4 = (v + step * k3.1, acceleration(x + step * k3.0, v + step * k3.1))
            x += step / 6 * (k1.0 + 2 * k2.0 + 2 * k3.0 + k4.0)
            v += step / 6 * (k1.1 + 2 * k2.1 + 2 * k3.1 + k4.1)
            guard index.isMultiple(of: 10_000) else { continue }
            let solved = spring.advance(value: 50, velocity: -300, target: 10, time: CGFloat(Double(index) * step))
            #expect(abs(Double(solved.value) - 10 - x) < 1e-6)
            #expect(abs(Double(solved.velocity) - v) < 1e-4)
        }
    }

    /// `ValueAnimator`'s curve with `makeSpringAnimation`'s overdamped spring (mass 3, stiffness 1000, damping 500, so a
    /// damping ratio of 4.56) and with an underdamped ratio: the displacement solved in closed form, normalized to reach
    /// 1 at the animation's duration
    @Test(arguments: [0.0, 2])
    func valueAnimatorCurveFollowsTheCoreAnimationSpring(initialVelocity: Double) {
        func expectedProgress(dampingRatio: Double, stiffness: Double, mass: Double, duration: Double) -> (Double) -> Double {
            let naturalFrequency = (stiffness / mass).squareRoot()
            func displacement(_ time: Double) -> Double {
                let velocity = -initialVelocity
                if dampingRatio > 1 {
                    let root = (dampingRatio * dampingRatio - 1).squareRoot()
                    let fast = -naturalFrequency * (dampingRatio + root)
                    let slow = -naturalFrequency * (dampingRatio - root)
                    let slowAmount = (velocity - fast) / (slow - fast)
                    return slowAmount * exp(slow * time) + (1 - slowAmount) * exp(fast * time)
                }
                let damped = naturalFrequency * (1 - dampingRatio * dampingRatio).squareRoot()
                let coefficient = (velocity + dampingRatio * naturalFrequency) / damped
                return exp(-dampingRatio * naturalFrequency * time) * (cos(damped * time) + coefficient * sin(damped * time))
            }
            return { fraction in min(max((1 - displacement(fraction * duration)) / (1 - displacement(duration)), 0), 1) }
        }

        let overdamped = SpringCurve(initialVelocity: initialVelocity)
        let overdampedExpected = expectedProgress(dampingRatio: 500 / (2 * (1000.0 * 3).squareRoot()), stiffness: 1000, mass: 3, duration: 0.5)
        let underdamped = SpringCurve(initialVelocity: initialVelocity, dampingRatio: 0.5, referenceDuration: 0.6)
        let underdampedExpected = expectedProgress(dampingRatio: 0.5, stiffness: 280, mass: 1, duration: 0.6)
        for fraction in stride(from: 0.0, through: 1, by: 0.05) {
            #expect(abs(Double(overdamped.value(at: fraction)) - overdampedExpected(fraction)) < 1e-9)
            #expect(abs(Double(underdamped.value(at: fraction)) - underdampedExpected(fraction)) < 1e-9)
        }
    }
}
