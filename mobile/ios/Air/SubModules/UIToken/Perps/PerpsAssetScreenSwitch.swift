import UIKit
import UIComponents
import WalletContext
import WalletCore

extension UINavigationController {
    /// The asset and position screens are two states of one screen, as a token is with and without a balance.
    /// The new state takes the old one's place, so Back still leaves the asset.
    /// Async so that nothing runs between reading the stack and pushing. UIKit queues navigation requested during the animation and applies it to the result.
    @MainActor public func switchAssetScreen(_ current: UIViewController, to next: UIViewController) async {
        let shown = viewControllers
        if current === shown.last, viewIfLoaded?.window != nil, AppStorageHelper.animations,
           UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled,
           await ContentReplaceAnimationCoordinator().replaceNavigationStack(
               with: next, in: self, targetViewControllers: shown.dropLast() + [next], animateAlongside: {}) {
            return
        }
        var stack = viewControllers.filter { $0 !== next }
        guard let index = stack.firstIndex(of: current) else { return }
        stack[index] = next
        setViewControllers(stack, animated: false)
    }
}
