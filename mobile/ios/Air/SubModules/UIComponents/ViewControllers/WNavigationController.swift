//
//  WNavigationController.swift
//  UIComponents
//
//  Created by Sina on 6/29/24.
//

import UIKit
import WalletContext
import WalletCore

class SlowedPanGestureRecognizer: UIPanGestureRecognizer {
    override func velocity(in view: UIView?) -> CGPoint {
        let originalVelocity = super.velocity(in: view)
        return CGPoint(x: min(1000, originalVelocity.x),
                       y: originalVelocity.y)
    }
}

open class WNavigationController: UINavigationController {
    
    private let log = Log("WNavigationController")
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        if !IOS_26_MODE_ENABLED {
            setupFullWidthBackGesture()
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
        return super.popViewController(animated: animated)
    }
    
}

extension WNavigationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController,
                                     willShow viewController: UIViewController, animated: Bool) {
        guard let vc = viewController as? WViewController else {return}
        setNavigationBarHidden(vc.hideNavigationBar,
                               animated: animated)
    }
}

extension WNavigationController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let isThereStackedViewControllers = viewControllers.count > 1
        return isThereStackedViewControllers && presentedViewController == nil
    }
    
    public func fullWidthBackGestureRecognizerRequireToFail(_ otherGestureRecognizer: UIGestureRecognizer) {
        fullWidthBackGestureRecognizer.require(toFail: otherGestureRecognizer)
    }
}

extension UINavigationController {
    
    /// A temporary solution to disable backswipe for a navigation controller stack
    /// Should be revised with full navigation management refactoring
    public func allowBackSwipeToDismiss(_ allow: Bool) {
        if #available(iOS 26.0, *) {
            self.interactiveContentPopGestureRecognizer?.isEnabled = allow
        }
        if let nc = self as?  WNavigationController {
            nc.fullWidthBackGestureRecognizer.isEnabled = allow
            return
        }
        self.interactivePopGestureRecognizer?.isEnabled = allow
    }
}
