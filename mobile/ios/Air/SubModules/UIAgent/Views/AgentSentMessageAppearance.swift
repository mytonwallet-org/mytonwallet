import UIKit

/// How a sent question appears where it lands, as Android's chat brings it in: its row opens on a critically damped
/// spring of stiffness 500 from 30% of its height, and the bubble fades in and grows from 80% over the last 30% of that
enum AgentSentMessageAppearance {
    static let duration: TimeInterval = 0.32

    private static let angularFrequency = sqrt(500.0)
    private static let startOpening = 0.3
    private static let appearingOpening = 0.7
    private static let startScale = 0.8
    private static let frameRate = 60.0

    /// Plays the appearance on `view`'s layer, about its center, leaving what the view shows unchanged
    static func animate(_ view: UIView) {
        let frameCount = Int((duration * frameRate).rounded(.up))
        let times = (0...frameCount).map { min(duration, Double($0) / frameRate) }
        let progress = Array(times.map(getProgress(at:)).dropLast()) + [1.0]
        let keyTimes = times.map { NSNumber(value: $0 / duration) }

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = progress
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = progress.map { startScale + (1 - startScale) * $0 }
        for animation in [opacity, scale] {
            animation.keyTimes = keyTimes
            animation.duration = duration
            view.layer.add(animation, forKey: "agentSentMessageAppearance.\(animation.keyPath ?? "")")
        }
    }

    /// How far the bubble has appeared at `time`, from 0 while its row opens to 70% of its height to 1 once it is open
    static func getProgress(at time: TimeInterval) -> Double {
        let phase = angularFrequency * time
        let opening = 1 - (1 - startOpening) * (1 + phase) * exp(-phase)
        return min(1, max(0, (opening - appearingOpening) / (1 - appearingOpening)))
    }
}
