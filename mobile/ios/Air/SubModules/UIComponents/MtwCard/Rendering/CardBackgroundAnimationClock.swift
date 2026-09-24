import Foundation

/// Integrate speed into phase so a press never jumps or resets the blob positions.
struct CardBackgroundAnimationClock {
    private(set) var lineTime = 0.0
    private(set) var blobTime = 0.0
    private(set) var boost = 0.0

    mutating func advance(by dt: TimeInterval, press: Double, activity: Double = 0) {
        guard dt > 0 else { return }
        let target = min(1, max(0, max(press, activity)))
        let response = target > boost ? 0.12 : 0.65
        let decay = exp(-dt / response)
        let integratedBoost = target * dt + (boost - target) * response * (1 - decay)
        lineTime += dt * CardBackgroundMotion.defaultSpeed
        blobTime += dt + 2 * integratedBoost
        boost = target + (boost - target) * decay
    }
}
