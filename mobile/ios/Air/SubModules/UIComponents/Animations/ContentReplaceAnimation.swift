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
        let toView = toVC.view!
        let fromView = fromVC.view!
        
        container.addSubview(toView)
        container.backgroundColor = toView.backgroundColor
        
        toView.alpha = 0.0
        toView.transform = CGAffineTransform(scaleX: scaleOut, y: scaleOut)
        fromView.alpha = 1.0
        fromView.transform = .identity
        
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

public final class ContentReplaceAnimationCoordinator {
    private weak var navigationController: UINavigationController?
    private let navigationDelegate = NavigationTransitionDelegate()

    public init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        navigationController.delegate = navigationDelegate
    }
    
    public func replaceTop(with vc: UIViewController, animateAlongside: @escaping () -> ()) {
        guard let navigationController else { return }
        
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
}
