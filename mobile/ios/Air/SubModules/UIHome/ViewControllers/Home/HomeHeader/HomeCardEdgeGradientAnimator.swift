import UIKit

/// Matches Motion Lab's edge transitions, including layout passes during a swipe.
@MainActor
final class HomeCardEdgeGradientAnimator {
    private var target: CGPoint?
    private var motionEnabled: Bool?

    func update(leading: UIView, trailing: UIView, leadingOffset: CGFloat, trailingOffset: CGFloat, animated: Bool, motionEnabled: Bool = true) {
        let next = motionEnabled ? CGPoint(x: leadingOffset, y: trailingOffset) : .zero
        // Layout and observation can both deliver the same target. Reapplying it
        // without animation would fast-forward the transition already in flight.
        guard target != next || self.motionEnabled != motionEnabled else { return }
        target = next
        self.motionEnabled = motionEnabled
        let changes = {
            leading.transform = CGAffineTransform(translationX: next.x, y: 0)
            trailing.transform = CGAffineTransform(translationX: next.y, y: 0)
        }
        if animated && motionEnabled {
            UIView.animate(withDuration: 0.24, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: changes)
        } else {
            leading.layer.removeAllAnimations()
            trailing.layer.removeAllAnimations()
            UIView.performWithoutAnimation(changes)
        }
    }
}
