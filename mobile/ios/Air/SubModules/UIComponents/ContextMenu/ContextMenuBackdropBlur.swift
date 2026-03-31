import UIKit

@MainActor
public enum ContextMenuBackdropBlur {
    @discardableResult
    public static func show(
        in window: UIWindow?,
        animator: (any UIContextMenuInteractionAnimating)?
    ) -> UIView? {
        guard let window else {
            return nil
        }

        let blurView = WBlurView()
        blurView.frame = window.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        blurView.alpha = 0
        window.addSubview(blurView)

        if let animator {
            animator.addAnimations {
                blurView.alpha = 1
            }
        } else {
            blurView.alpha = 1
        }

        return blurView
    }

    public static func hide(
        _ blurView: UIView?,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        guard let blurView else {
            return
        }

        if let animator {
            animator.addAnimations {
                blurView.alpha = 0
            }
            animator.addCompletion {
                blurView.removeFromSuperview()
            }
        } else {
            blurView.removeFromSuperview()
        }
    }
}
