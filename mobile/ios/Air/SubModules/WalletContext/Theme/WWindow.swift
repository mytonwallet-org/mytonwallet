//
//  UIWindowUtils.swift
//  UIComponents
//
//  Created by Sina on 6/30/24.
//

import UIKit

public final class WWindow: UIWindow, WThemedView, WSensitiveDataProtocol {
    
    public override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor
    public func updateTheme() {
        tintColor = WTheme.tint

        // update theme on view
        func updateViewTheme(on view: UIView) {
            if let view = view as? WThemedView {
                view.updateTheme()
            }
            for subview in view.subviews {
                updateViewTheme(on: subview)
            }
        }

        // update theme on view controller
        func updateTheme(on vc: UIViewController?) {
            guard let vc else {return}
            if !vc.isViewLoaded {
                return
            }
            if let vc = vc as? WThemedView {
                vc.updateTheme()
            }
            updateViewTheme(on: vc.view)
            updateTheme(on: vc.presentedViewController)
            if let vc = vc as? UITabBarController {
                for tabVC in vc.viewControllers ?? [] {
                    updateTheme(on: tabVC)
                }
            }
            if let vc = vc as? UINavigationController {
                for navChildVC in vc.viewControllers {
                    updateTheme(on: navChildVC)
                }
            }
            for vc in vc.children {
                updateTheme(on: vc)
            }
        }
        
        // start theme update on root vc
        updateTheme(on: rootViewController)
        
        NotificationCenter.default.post(name: .updateTheme, object: self)
    }

    public func updateSensitiveData() {
        
        func _updateView(_ view: UIView) {
            if let view = view as? WSensitiveDataProtocol {
                view.updateSensitiveData()
            }
            for subview in view.subviews {
                _updateView(subview)
            }
        }

        func _updateViewController(_ vc: UIViewController) {
            guard vc.isViewLoaded else { return }
            if let vc = vc as? WSensitiveDataProtocol {
                vc.updateSensitiveData()
            }
            _updateView(vc.view)
            if let presented = vc.presentedViewController {
                _updateViewController(presented)
            }
            if let vc = vc as? UITabBarController {
                for tabVC in vc.viewControllers ?? [] {
                    _updateViewController(tabVC)
                }
            }
            if let vc = vc as? UINavigationController {
                for navChildVC in vc.viewControllers {
                    _updateViewController(navChildVC)
                }
            }
            for vc in vc.children {
                _updateViewController(vc)
            }
        }
        
        if let rootViewController {
            _updateViewController(rootViewController)
        }
    }
}

public extension Notification.Name {
    static let updateTheme = Notification.Name("updateTheme")
}
