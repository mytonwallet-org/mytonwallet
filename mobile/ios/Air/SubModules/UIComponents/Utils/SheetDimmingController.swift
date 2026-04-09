import UIKit
import WalletContext

@MainActor
final class SheetDimmingController {
    private let extraDimmingAlpha: CGFloat
    private let extraDimmingColor: UIColor
    private let extraDimmingView = UIView()
    private weak var hostViewController: UIViewController?

    public init(
        extraDimmingAlpha: CGFloat = 1,
        extraDimmingColor: UIColor = .air.extraSheetDimming
    ) {
        self.extraDimmingAlpha = extraDimmingAlpha
        self.extraDimmingColor = extraDimmingColor
        extraDimmingView.alpha = 0
    }

    public func viewWillAppear(in viewController: UIViewController, animated: Bool) {
        hostViewController = presentationHostViewController(for: viewController)
        syncExtraDimmingView()
        guard let hostViewController, hostViewController.isBeingPresented, !hostViewController.isBeingDismissed else { return }
        animateExtraDimming(to: extraDimmingAlpha, animated: animated, canceledAlpha: 0)
    }

    public func viewDidLayoutSubviews(in viewController: UIViewController) {
        hostViewController = presentationHostViewController(for: viewController)
        syncExtraDimmingView()
    }

    public func viewWillDisappear(in viewController: UIViewController, animated: Bool) {
        hostViewController = presentationHostViewController(for: viewController)
        guard let hostViewController, hostViewController.isBeingDismissed else { return }
        animateExtraDimming(to: 0, animated: animated, canceledAlpha: extraDimmingAlpha)
    }
    
    func removeDimmingView() {
        extraDimmingView.removeFromSuperview()
        extraDimmingView.alpha = 0
    }

    private func presentationHostViewController(for viewController: UIViewController) -> UIViewController? {
        viewController.navigationController ?? viewController
    }

    private func syncExtraDimmingView() {
        guard let hostViewController, let containerView = hostViewController.presentationController?.containerView else { return }

        extraDimmingView.backgroundColor = extraDimmingColor
        extraDimmingView.isUserInteractionEnabled = false
        extraDimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        extraDimmingView.frame = containerView.bounds

        if let presentedHostView = presentedHostView(in: containerView) {
            if extraDimmingView.superview !== containerView {
                extraDimmingView.removeFromSuperview()
            }
            containerView.insertSubview(extraDimmingView, belowSubview: presentedHostView)
        } else if extraDimmingView.superview !== containerView {
            extraDimmingView.removeFromSuperview()
            containerView.addSubview(extraDimmingView)
        }
    }

    private func presentedHostView(in containerView: UIView) -> UIView? {
        var hostView = hostViewController?.view
        while let currentView = hostView, let superview = currentView.superview {
            if superview === containerView {
                return currentView
            }
            hostView = superview
        }
        return nil
    }

    private func animateExtraDimming(to alpha: CGFloat, animated: Bool, canceledAlpha: CGFloat) {
        syncExtraDimmingView()
        let apply = {
            self.extraDimmingView.alpha = alpha
        }

        guard animated, let coordinator = hostViewController?.transitionCoordinator else {
            apply()
            if alpha == 0 {
                extraDimmingView.removeFromSuperview()
            }
            return
        }

        coordinator.animate(alongsideTransition: { _ in
            apply()
        }) { context in
            self.extraDimmingView.alpha = context.isCancelled ? canceledAlpha : alpha
            if alpha == 0, !context.isCancelled {
                self.extraDimmingView.removeFromSuperview()
            }
        }
    }
}
