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
    
    private let log = Log("WNavigationController")
    private let sheetDimmingController = SheetDimmingController()
    public var onWillShowViewController: ((UIViewController) -> Void)?
    public var onDidShowViewController: ((UIViewController) -> Void)?
    public var pushViewControllerInterceptor: ((UIViewController, Bool) -> Bool)?
    public var popViewControllerInterceptor: ((Bool) -> Bool)?
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
        return super.popViewController(animated: animated)
    }
    
}

extension WNavigationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController,
                                     willShow viewController: UIViewController, animated: Bool) {
        onWillShowViewController?(viewController)
        guard let vc = viewController as? WViewController else {return}
        setNavigationBarHidden(vc.hideNavigationBar,
                               animated: animated)
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     didShow viewController: UIViewController, animated: Bool) {
        onDidShowViewController?(viewController)
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
