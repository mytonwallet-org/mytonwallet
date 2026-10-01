import UIKit

/// Owns visibility only: hiding also blocks interaction, while showing
/// leaves interaction to the button's presenter, which reasserts the
/// model-derived state on every update.
@MainActor
func setSendContinueButtonHidden(
    _ button: UIView,
    hidden: Bool,
    animated: Bool = true
) {
    let targetAlpha: CGFloat = hidden ? 0 : 1
    let isAtTarget = button.alpha == targetAlpha
        && button.isHidden == hidden
        && (!hidden || !button.isUserInteractionEnabled)
    guard !isAtTarget else { return }

    if hidden {
        button.isUserInteractionEnabled = false
    } else {
        button.isHidden = false
    }

    let animations = {
        button.alpha = targetAlpha
        button.transform = hidden
            ? CGAffineTransform(translationX: 0, y: 12)
            : .identity
    }
    guard animated && !UIAccessibility.isReduceMotionEnabled else {
        animations()
        button.isHidden = hidden
        return
    }

    UIView.animate(
        withDuration: 0.2,
        delay: 0,
        options: [.beginFromCurrentState, .curveEaseInOut],
        animations: animations
    ) { finished in
        if finished && hidden && button.alpha == 0 {
            button.isHidden = true
        }
    }
}
