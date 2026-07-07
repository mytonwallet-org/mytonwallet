import UIKit

private let scaleOut: CGFloat = 0.95
private let scaleIn: CGFloat = 0.99

private final class ContentReplaceAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    
    let duration: TimeInterval
    
    init(duration: TimeInterval = 0.32) {
        self.duration = duration
    }
    
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }
    
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard
            let fromVC = context.viewController(forKey: .from),
            let toVC = context.viewController(forKey: .to)
        else {
            context.completeTransition(false)
            return
        }
        
        let container = context.containerView
        let toView = context.view(forKey: .to) ?? toVC.view!
        let fromView = context.view(forKey: .from) ?? fromVC.view!
        
        UIView.performWithoutAnimation {
            toView.frame = context.finalFrame(for: toVC)
            toView.alpha = 0.0
            toView.transform = CGAffineTransform(scaleX: scaleOut, y: scaleOut)
            fromView.alpha = 1.0
            fromView.transform = .identity
            container.addSubview(toView)
            container.backgroundColor = toView.backgroundColor
            toView.setNeedsLayout()
            toView.layoutIfNeeded()
        }
        
        let duration = transitionDuration(using: context)
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            fromView.alpha = 0.0
            fromView.transform = CGAffineTransform(scaleX: scaleIn, y: scaleIn)
            toView.alpha = 1.0
            toView.transform = .identity
        } completion: { _ in
            fromView.alpha = 1.0
            fromView.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        }
    }
}

private final class NavigationTransitionDelegate: NSObject, UINavigationControllerDelegate {
    let animator = ContentReplaceAnimation()

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push:
            return animator
        default:
            return nil
        }
    }
}

@MainActor
public final class ContentReplaceAnimationCoordinator {
    private weak var navigationController: UINavigationController?
    private let navigationDelegate = NavigationTransitionDelegate()

    public init() { }
    
    public func replaceNavigationTop(with vc: UIViewController, in navigationController: UINavigationController, animateAlongside: @escaping () -> ()) {
        self.navigationController = navigationController
        navigationController.delegate = navigationDelegate
        navigationController.pushViewController(vc, animated: true)
        
        guard let transitionCoordinator = navigationController.transitionCoordinator else { return }

        transitionCoordinator.animate { context in
            animateAlongside()
        } completion: { [self] _ in
            navigationController.setViewControllers([vc], animated: false)
            // do not deallocate self until transition completes
            _ = self
        }
    }
    
    @discardableResult
    public func replaceContentInPresentedSheet(_ sheetVC: UIViewController, with vc: UIViewController,
                                               animateAlongside: (() -> Void)? = nil, completion: (() -> Void)? = nil) -> Bool {
        guard let presentationController = sheetVC.sheetPresentationController else {
            return false
        }
        guard let view = sheetVC.view else {
            assertionFailure()
            return false
        }
        
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sheetVC.addChild(vc)
        view.addSubview(vc.view)
        vc.didMove(toParent: sheetVC)
        
        UIView.performWithoutAnimation {
            vc.view.alpha = 0
            vc.view.layoutIfNeeded()
        }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion?()
            // do not deallocate self until transition completes
            _ = self
        }
        presentationController.animateChanges {
            presentationController.detents = [.large()]
            presentationController.selectedDetentIdentifier = .large
            vc.view.alpha = 1.0
            animateAlongside?()
        }
        CATransaction.commit()
        return true
    }
}
