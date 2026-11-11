import UIKit

private let STORY_CARD_MARGIN: CGFloat = 24
private let STORY_MAXIMUM_HEIGHT: CGFloat = 1080

final class StoriesPresentationController: UIPresentationController {
    private let backdrop = UIView()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView, let controller = presentedViewController as? StoriesViewController else { return .zero }
        return Self.calculateFrame(in: containerView.bounds, safeAreaInsets: containerView.safeAreaInsets,
                                   contentSize: controller.preferredContentSize, isCardLayout: controller.isCardLayout)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        backdrop.backgroundColor = .black.withAlphaComponent(0.7)
        backdrop.alpha = 0
        backdrop.frame = containerView.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdrop.alpha = 1
        })
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        if completed {
            backdrop.alpha = 1
            containerView?.setNeedsLayout()
        }
        else { backdrop.removeFromSuperview() }
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdrop.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed { backdrop.removeFromSuperview() }
        else { backdrop.alpha = 1 }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let controller = presentedViewController as? StoriesViewController,
              !controller.isBeingPresented, !controller.isBeingDismissed,
              controller.view.transform == .identity else { return }
        controller.view.frame = frameOfPresentedViewInContainerView
        controller.updatePresentationAppearance()
    }

    static func calculateFrame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets,
                               contentSize: CGSize, isCardLayout: Bool) -> CGRect {
        guard isCardLayout else { return bounds }
        let safeFrame = bounds.inset(by: safeAreaInsets)
        let available = safeFrame.insetBy(dx: STORY_CARD_MARGIN, dy: STORY_CARD_MARGIN)
        let aspectRatio = contentSize.width > 0 && contentSize.height > 0 ? contentSize.width / contentSize.height : 9 / 16.0
        let height = max(1, min(STORY_MAXIMUM_HEIGHT, available.height, available.width / aspectRatio))
        let width = height * aspectRatio
        return CGRect(x: safeFrame.midX - width / 2, y: safeFrame.midY - height / 2, width: width, height: height)
    }
}
