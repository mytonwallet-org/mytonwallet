import UIKit

@MainActor
public final class WInteractivePushTransition: UIPercentDrivenInteractiveTransition {
    private let animator: any UIViewControllerAnimatedTransitioning
    private let direction: CGFloat
    private let width: CGFloat

    init?(navigationController: UINavigationController) {
        guard let animator = Self.makeAnimator() else { return nil }
        self.animator = animator
        direction = navigationController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 : -1
        width = navigationController.view.bounds.width
        super.init()
        wantsInteractiveStart = true
        completionCurve = .easeOut
        completionSpeed = 2
    }

    private static func makeAnimator() -> (any UIViewControllerAnimatedTransitioning)? {
        // WebKit uses the same UIKit animator for its back/forward swipe transitions.
        // Keep the private entry points optional so an OS change falls back to paging.
        let selector = NSSelectorFromString(String(":noitarepOtnerruChtiWtini".reversed()))
        guard let cls = NSClassFromString(String("noitisnarTxallaraPnoitagivaNIU_".reversed())) as? NSObject.Type,
              let method = class_getInstanceMethod(cls, selector),
              let allocated = cls.perform(NSSelectorFromString("alloc")) else { return nil }
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, Int) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(method_getImplementation(method), to: Initialize.self)
        return initialize(
            allocated.toOpaque(), selector, UINavigationController.Operation.push.rawValue
        )?.takeRetainedValue() as? any UIViewControllerAnimatedTransitioning
    }

    func allowNativePop(in navigationController: UINavigationController) {
        guard #available(iOS 26.0, *) else { return }
        let controllerSelector = NSSelectorFromString(String("rellortnoCnoitcaretnInitliub_".reversed()))
        let animatorSelector = NSSelectorFromString(String(":rellortnoCnoitaminAtes".reversed()))
        if navigationController.responds(to: controllerSelector),
           let controller = navigationController.perform(controllerSelector)?.takeUnretainedValue() as? NSObject,
           controller.responds(to: animatorSelector) {
            typealias SetAnimator = @convention(c) (NSObject, Selector, AnyObject) -> Void
            unsafeBitCast(controller.method(for: animatorSelector), to: SetAnimator.self)(
                controller, animatorSelector, animator
            )
        }
        // UIKit treats delegate-provided animators as custom, blocking native back gestures
        // while they settle. Identify its own animator so it can preempt this push with a pop.
        let selector = NSSelectorFromString(String(":rotaminAnitliuBgnisUtes_".reversed()))
        guard navigationController.responds(to: selector) else { return }
        typealias SetBuiltinAnimator = @convention(c) (UINavigationController, Selector, Bool) -> Void
        unsafeBitCast(navigationController.method(for: selector), to: SetBuiltinAnimator.self)(
            navigationController, selector, true
        )
    }

    func handle(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view).x * direction
        let velocity = gesture.velocity(in: gesture.view).x * direction
        let progress = min(1, max(0, translation / width))
        switch gesture.state {
        case .began, .changed:
            update(progress)
        case .ended:
            if translation + velocity * 0.2 > width * 0.5 {
                finish()
            } else {
                cancel()
            }
        case .cancelled, .failed:
            cancel()
        default:
            break
        }
    }
}

extension WInteractivePushTransition: UINavigationControllerDelegate {
    public func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        operation == .push ? animator : nil
    }

    public func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        animationController === animator ? self : nil
    }

    public func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        (navigationController as? WNavigationController)?.navigationController(
            navigationController, willShow: viewController, animated: animated
        )
    }
}
