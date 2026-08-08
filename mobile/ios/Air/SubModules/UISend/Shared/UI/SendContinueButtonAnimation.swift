import UIKit

@MainActor
func setSendContinueButtonHidden(
    _ button: UIView,
    hidden: Bool,
    animated: Bool = true
) {
    let targetAlpha: CGFloat = hidden ? 0 : 1
    let isUserInteractionEnabled = !hidden
    let isAtTarget = button.alpha == targetAlpha
        && button.isHidden == hidden
        && button.isUserInteractionEnabled
            == isUserInteractionEnabled
    guard !isAtTarget else { return }

    button.isUserInteractionEnabled = isUserInteractionEnabled
    if !hidden {
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
    ) { _ in
        if !button.isUserInteractionEnabled
            && button.alpha == 0 {
            button.isHidden = true
        }
    }
}
