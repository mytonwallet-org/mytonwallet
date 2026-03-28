//
//  UIWindowUtils.swift
//  UIComponents
//
//  Created by Sina on 6/30/24.
//

import UIKit

public final class WWindow: UIWindow, WSensitiveDataProtocol {
    
    public override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor
    public func updateTheme() {
        tintColor = AirTintColor
        NotificationCenter.default.post(name: .updateTheme, object: self)
    }

    public func updateSensitiveData() {
        var visited: Set<ObjectIdentifier> = []

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
            guard nil == visited.update(with: ObjectIdentifier(vc)) else { return }
            
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
        
        NotificationCenter.default.post(name: .updateSensitiveData, object: self)
    }
}

public extension Notification.Name {
    static let updateTheme = Notification.Name("updateTheme")
    static let updateSensitiveData = Notification.Name("updateSensitiveData")
}
