import UIKit

@MainActor
final class WNavigationCrossfadeTransition: NSObject, UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning {
    private weak var navigationController: WNavigationController?
    private let duration: TimeInterval
    private let foregroundViews: [UIView]
    private let snapshot: UIView
    var onCompletion: (() -> Void)?

    init(navigationController: WNavigationController, duration: TimeInterval, foregroundViews: [UIView]) {
        self.navigationController = navigationController
        self.duration = duration
        self.foregroundViews = foregroundViews
        navigationController.view.layoutIfNeeded()
        snapshot = UIView(frame: navigationController.view.bounds)
        snapshot.isUserInteractionEnabled = false
        snapshot.backgroundColor = navigationController.view.backgroundColor
        super.init()

        // Capture before willShow changes the bar and the source's safe area.
        if let source = navigationController.topViewController?.view {
            addSnapshot(of: source)
        }
        if !navigationController.isNavigationBarHidden {
            addSnapshot(of: navigationController.navigationBar)
        }
        navigationController.view.addSubview(snapshot)
        bringForegroundViewsToFront()
    }

    private func addSnapshot(of view: UIView) {
        guard let navigationController, let copy = view.snapshotView(afterScreenUpdates: false) else { return }
        copy.frame = view.convert(view.bounds, to: navigationController.view)
        snapshot.addSubview(copy)
    }

    private func bringForegroundViewsToFront() {
        guard let navigationController else { return }
        navigationController.view.bringSubviewToFront(snapshot)
        for view in foregroundViews where view.superview === navigationController.view {
            navigationController.view.bringSubviewToFront(view)
        }
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        self
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        self.navigationController?.navigationController(navigationController, willShow: viewController, animated: false)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        finish()
        self.navigationController?.navigationController(navigationController, didShow: viewController, animated: animated)
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        duration
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let destination = context.viewController(forKey: .to), let destinationView = context.view(forKey: .to) else {
            context.completeTransition(false)
            finish()
            return
        }
        destinationView.frame = context.finalFrame(for: destination)
        context.containerView.addSubview(destinationView)
        destinationView.layoutIfNeeded()
        bringForegroundViewsToFront()
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut]) {
            self.snapshot.alpha = 0
        } completion: { _ in
            self.snapshot.removeFromSuperview()
            context.completeTransition(!context.transitionWasCancelled)
            self.finish()
        }
    }

    func finish() {
        snapshot.removeFromSuperview()
        let completion = onCompletion
        onCompletion = nil
        completion?()
    }
}
