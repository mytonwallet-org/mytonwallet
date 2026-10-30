//
//  WNavigationController.swift
//  UIComponents
//
//  Created by Sina on 6/29/24.
//

import UIKit
import WalletContext
import WalletCore

public protocol WBackSwipeControlling: AnyObject {
    func shouldAllowBackSwipe(at point: CGPoint) -> Bool
}

class SlowedPanGestureRecognizer: UIPanGestureRecognizer {
    override func velocity(in view: UIView?) -> CGPoint {
        let originalVelocity = super.velocity(in: view)
        return CGPoint(x: min(1000, originalVelocity.x),
                       y: originalVelocity.y)
    }
}

open class WNavigationController: UINavigationController {
    open override var childForStatusBarStyle: UIViewController? { topViewController }

    public typealias CustomTransitionProvider = @MainActor @Sendable (
        UINavigationController.Operation, UIViewController, UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)?

    
    private let log = Log("WNavigationController")
    private let sheetDimmingController = SheetDimmingController()
    /// Allows container-owned chrome to replace the root navigation bar.
    public var hidesRootNavigationBar = false {
        didSet {
            guard oldValue != hidesRootNavigationBar, let topViewController else { return }
            updateNavigationBarVisibility(for: topViewController, animated: false)
        }
    }

    private func updateNavigationBarVisibility(for viewController: UIViewController, animated: Bool) {
        guard let vc = viewController as? WViewController else { return }
        setNavigationBarHidden(
            (hidesRootNavigationBar && viewControllers.first === vc) || vc.hideNavigationBar,
            animated: animated
        )
    }

    public var onWillShowViewController: ((UIViewController) -> Void)?
    public var onDidShowViewController: ((UIViewController) -> Void)?
    public var pushViewControllerInterceptor: ((UIViewController, Bool) -> Bool)?
    public var popViewControllerInterceptor: ((Bool) -> Bool)?
    /// Custom animation for a specific button-driven push or pop; returning nil keeps UIKit's.
    /// Installed only for that one transition: a delegate that animates transitions at all turns
    /// off UIKit's back swipe, so the controller's own delegate never does.
    public final var customTransitionProvider: CustomTransitionProvider?
    private var customTransition: WNavigationCustomTransition?
    private var interactivePushTransition: WInteractivePushTransition?
    private var crossfadeTransition: WNavigationCrossfadeTransition?

    public func withCrossfade(
        duration: TimeInterval,
        keepingAboveTransition views: [UIView] = [],
        updates: () -> Void
    ) {
        guard transitionCoordinator == nil, delegate === self, view.window != nil else {
            updates()
            return
        }
        let transition = WNavigationCrossfadeTransition(
            navigationController: self,
            duration: duration,
            foregroundViews: views
        )
        crossfadeTransition = transition
        delegate = transition
        transition.onCompletion = { [weak self, weak transition] in
            guard let self, crossfadeTransition === transition else { return }
            delegate = self
            crossfadeTransition = nil
        }
        updates()
        if transitionCoordinator == nil {
            transition.finish()
        }
    }

    /// Starts a gesture-driven push using UIKit's navigation animation.
    public func beginInteractivePush(_ viewController: UIViewController) -> WInteractivePushTransition? {
        guard interactivePushTransition == nil, transitionCoordinator == nil,
              presentedViewController == nil, view.window != nil, view.bounds.width > 0,
              delegate === self, viewController.parent == nil,
              !viewControllers.contains(viewController),
              let transition = WInteractivePushTransition(navigationController: self) else { return nil }
        interactivePushTransition = transition
        // Expose animation callbacks only during this push, preserving UIKit's native back gesture.
        delegate = transition
        pushViewController(viewController, animated: true)
        guard let coordinator = transitionCoordinator else {
            delegate = self
            interactivePushTransition = nil
            return nil
        }
        coordinator.notifyWhenInteractionChanges { [weak self] _ in
            guard let self else { return }
            delegate = self
            interactivePushTransition?.allowNativePop(in: self)
        }
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            if delegate === interactivePushTransition {
                delegate = self
            }
            interactivePushTransition = nil
        }
        return transition
    }
    
    public var isExtraSheetDimmingEnabled: Bool = false {
        didSet {
            guard !isExtraSheetDimmingEnabled else { return }
            sheetDimmingController.removeDimmingView()
        }
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        if !IOS_26_MODE_ENABLED {
            setupFullWidthBackGesture()
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isExtraSheetDimmingEnabled else { return }
        sheetDimmingController.viewWillAppear(in: self, animated: animated)
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard isExtraSheetDimmingEnabled else { return }
        sheetDimmingController.viewDidLayoutSubviews(in: self)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isExtraSheetDimmingEnabled else { return }
        sheetDimmingController.viewWillDisappear(in: self, animated: animated)
    }

    private func installCustomTransition(_ animator: (any UIViewControllerAnimatedTransitioning)?) {
        guard let animator, delegate === self, transitionCoordinator == nil else { return }
        let transition = WNavigationCustomTransition(navigationController: self, animator: animator)
        customTransition = transition
        delegate = transition
        transition.onCompletion = { [weak self, weak transition] in
            guard let self, customTransition === transition else { return }
            delegate = self
            customTransition = nil
        }
    }

    fileprivate lazy var fullWidthBackGestureRecognizer = SlowedPanGestureRecognizer()

    private func setupFullWidthBackGesture() {
        // The trick here is to wire up our full-width `fullWidthBackGestureRecognizer` to execute the same handler as the system `interactivePopGestureRecognizer`.
        guard let interactivePopGestureRecognizer = interactivePopGestureRecognizer,
              let targets = interactivePopGestureRecognizer.value(forKey: "targets") else {
            return
        }
        fullWidthBackGestureRecognizer.setValue(targets, forKey: "targets")
        fullWidthBackGestureRecognizer.delegate = self
        view.addGestureRecognizer(fullWidthBackGestureRecognizer)

        // Disable default pop gesture
        interactivePopGestureRecognizer.isEnabled = false
    }
    
    public override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if pushViewControllerInterceptor?(viewController, animated) == true {
            return
        }
        if viewControllers.count > 0, (viewController as? WViewController)?.hideBottomBar != false {
            viewController.hidesBottomBarWhenPushed = true
        }
        if animated, let topViewController {
            installCustomTransition(customTransitionProvider?(.push, topViewController, viewController))
        }
        super.pushViewController(viewController, animated: animated)
    }
    
    open override func popViewController(animated: Bool) -> UIViewController? {
        if let presentedViewController, presentedViewController.isBeingDismissed {
            log.error("Dismissing a modal view controller. Will not pop to prevent freeze")
            return nil
        }
        if popViewControllerInterceptor?(animated) == true {
            return nil
        }
        if animated, !isInteractivePopInProgress, viewControllers.count > 1, let topViewController {
            let destination = viewControllers[viewControllers.count - 2]
            installCustomTransition(customTransitionProvider?(.pop, topViewController, destination))
        }
        return super.popViewController(animated: animated)
    }
    
}

extension WNavigationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController,
                                     willShow viewController: UIViewController, animated: Bool) {
        onWillShowViewController?(viewController)
        updateNavigationBarVisibility(for: viewController, animated: animated)
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     didShow viewController: UIViewController, animated: Bool) {
        onDidShowViewController?(viewController)
        setNeedsStatusBarAppearanceUpdate()
    }

    /// True while a back swipe drives the current pop; custom animations must not take those over.
    public var isInteractivePopInProgress: Bool {
        let active: Set<UIGestureRecognizer.State> = [.began, .changed]
        if active.contains(interactivePopGestureRecognizer?.state ?? .possible) { return true }
        if active.contains(fullWidthBackGestureRecognizer.state) { return true }
        if #available(iOS 26.0, *), active.contains(interactiveContentPopGestureRecognizer?.state ?? .possible) {
            return true
        }
        return false
    }
}

extension WNavigationController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let isThereStackedViewControllers = viewControllers.count > 1
        guard isThereStackedViewControllers, presentedViewController == nil else {
            return false
        }

        if let controller = topViewController,
           let backSwipeController = controller as? WBackSwipeControlling
        {
            let point = gestureRecognizer.location(in: controller.view)
            return backSwipeController.shouldAllowBackSwipe(at: point)
        }

        return true
    }

    public func fullWidthBackGestureRecognizerRequireToFail(_ otherGestureRecognizer: UIGestureRecognizer) {
        fullWidthBackGestureRecognizer.require(toFail: otherGestureRecognizer)
    }
}

extension UINavigationController {

    public var isBackSwipeToDismissAllowed: Bool {
        if let navigationController = self as? WNavigationController,
           !IOS_26_MODE_ENABLED {
            return navigationController.fullWidthBackGestureRecognizer.isEnabled
        }
        if #available(iOS 26.0, *) {
            return interactiveContentPopGestureRecognizer?.isEnabled ?? true
        }
        return interactivePopGestureRecognizer?.isEnabled ?? true
    }
    
    /// A temporary solution to disable backswipe for a navigation controller stack
    /// Should be revised with full navigation management refactoring
    public func allowBackSwipeToDismiss(_ allow: Bool) {
        if let navigationController = self as? WNavigationController,
           !IOS_26_MODE_ENABLED {
            navigationController.fullWidthBackGestureRecognizer.isEnabled = allow
            return
        }
        if #available(iOS 26.0, *) {
            self.interactiveContentPopGestureRecognizer?.isEnabled = allow
            return
        }
        self.interactivePopGestureRecognizer?.isEnabled = allow
    }
}

/// Temporary delegate for one custom-animated push or pop; forwards the regular callbacks.
@MainActor
private final class WNavigationCustomTransition: NSObject, UINavigationControllerDelegate {
    private weak var navigationController: WNavigationController?
    private let animator: any UIViewControllerAnimatedTransitioning
    var onCompletion: (() -> Void)?

    init(navigationController: WNavigationController, animator: any UIViewControllerAnimatedTransitioning) {
        self.navigationController = navigationController
        self.animator = animator
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        animator
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        self.navigationController?.navigationController(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        let completion = onCompletion
        onCompletion = nil
        completion?()
        self.navigationController?.navigationController(navigationController, didShow: viewController, animated: animated)
    }
}
