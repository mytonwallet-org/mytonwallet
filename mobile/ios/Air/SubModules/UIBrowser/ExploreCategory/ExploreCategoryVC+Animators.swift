import UIKit

extension ExploreCategoryVC: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented _: UIViewController,
                                    presenting _: UIViewController,
                                    source _: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        CategoryDappsAnimator(dismissing: false, rectToShowFrom: rectToShowFrom)
    }

    public func animationController(forDismissed _: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        CategoryDappsAnimator(dismissing: true, rectToShowFrom: rectToShowFrom)
    }
}

extension ExploreCategoryVC {
    private final class CategoryDappsAnimator: NSObject, UIViewControllerAnimatedTransitioning {
        private let dismissing: Bool
        private let rectToShowFrom: CGRect?

        init(dismissing: Bool, rectToShowFrom: CGRect?) {
            self.dismissing = dismissing
            self.rectToShowFrom = rectToShowFrom
        }

        func transitionDuration(using _: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
            dismissing ? 0.375 : 0.4
        }

        func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
            if !dismissing {
                guard let to = transitionContext.viewController(forKey: .to) else { transitionContext.completeTransition(false); return }
                transitionContext.containerView.addSubview(to.view)
                to.view.alpha = 0.0
                to.view.center = getRectToShowFrom(to).center
                to.view.bounds = CGRect(x: 0, y: 0, width: transitionContext.finalFrame(for: to).width, height: transitionContext.finalFrame(for: to).height)
                to.view.transform = .identity.scaledBy(x: 0.2, y: 0.2)
                UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1) {
                    to.view.alpha = 1
                    to.view.transform = .identity
                    to.view.center = transitionContext.finalFrame(for: to).center
                } completion: { _ in
                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            } else {
                guard let from = transitionContext.viewController(forKey: .from) else { transitionContext.completeTransition(false); return }
                let sourceFrame = getRectToShowFrom(from)
                UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                    from.view.alpha = 0.0
                    from.view.center = sourceFrame.center
                    from.view.transform = .identity.scaledBy(x: 0.2, y: 0.2)
                } completion: { _ in
                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            }
        }

        private func getRectToShowFrom(_ vc: UIViewController) -> CGRect {
            rectToShowFrom ?? vc.view.frame
        }
    }
}
