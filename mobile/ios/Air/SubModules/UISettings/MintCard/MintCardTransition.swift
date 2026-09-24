import UIKit
import WalletCore

enum MintCardTransition {
    static let duration: TimeInterval = 0.28

    @MainActor
    static func isEnabled(in view: UIView) -> Bool {
        view.window != nil && view.bounds.width > 0 && UIView.areAnimationsEnabled
            && !UIAccessibility.isReduceMotionEnabled && AppStorageHelper.animations
    }

    @MainActor
    static func crossfade(_ view: UIView, animated: Bool, changes: @escaping () -> Void) {
        guard animated else {
            UIView.performWithoutAnimation(changes)
            return
        }
        UIView.transition(with: view, duration: duration,
                          options: [.transitionCrossDissolve, .curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            UIView.performWithoutAnimation {
                changes()
                view.layoutIfNeeded()
            }
        }
    }

    @MainActor
    static func setText(_ text: String?, on label: UILabel, animated: Bool) {
        guard label.text != text else { return }
        crossfade(label, animated: animated) { label.text = text }
    }
}
