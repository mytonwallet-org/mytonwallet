//
//  UIViewControllerUtils.swift
//  UIComponents
//
//  Created by Sina on 4/13/23.
//

import UIKit
import WalletCore
import WalletContext

public extension UIViewController {
    
    func alert(title: String?, text: String,
                           button: String, buttonStyle: UIAlertAction.Style, buttonPressed: (() -> ())? = nil,
                           secondaryButton: String? = nil, secondaryButtonPressed: (() -> ())? = nil,
                           preferPrimary: Bool = true) -> UIAlertController {
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        if let secondaryButton {
            alert.addAction(UIAlertAction(title: secondaryButton,
                                          style: .default,
                                          handler: {(alert: UIAlertAction!) in
                secondaryButtonPressed?()
            })
            )
        }
        let primaryAction = UIAlertAction(title: button,
                                          style: buttonStyle,
                                          handler: {(alert: UIAlertAction!) in
            buttonPressed?()
        }
        )
        alert.addAction(primaryAction)
        if preferPrimary {
            alert.preferredAction = primaryAction
        }

        return alert
    }
    
    // show alert view error message
    @MainActor func showAlert(title: String?, text: String,
                   button: String, buttonStyle: UIAlertAction.Style = .default, buttonPressed: (() -> ())? = nil,
                   secondaryButton: String? = nil, secondaryButtonPressed: (() -> ())? = nil,
                   preferPrimary: Bool = true) {
        if self is UIAlertController || self.presentedViewController is UIAlertController || topViewController() is UIAlertController {
            return
        }
        let alert = alert(
            title: title,
            text: text,
            button: button,
            buttonStyle: buttonStyle,
            buttonPressed: buttonPressed,
            secondaryButton: secondaryButton,
            secondaryButtonPressed: secondaryButtonPressed,
            preferPrimary: preferPrimary
        )
        // TODO:: Actions stack view should fill one row per action
        present(alert, animated: true, completion: nil)
    }
    
    @MainActor func showNetworkAlert(onOK: (() -> Void)? = nil) {
        showAlert(title: lang("Network error"),
                  text: lang("Please make sure your internet connection is working and try again."),
                  button: lang("OK")) {
            onOK?()
        }
    }
    
    @MainActor func showAlert(error: any Error, onOK: (() -> Void)? = nil) {
        if let error = error as? DisplayError {
            showAlert(title: error.title ?? lang("Error"),
                      text: error.text,
                      button: lang("OK")) {
                onOK?()
            }
        } else if let error = error as? BridgeCallError {
            switch error {
            case .message(let bridgeCallErrorMessages, _):
                if bridgeCallErrorMessages == .serverError {
                    showNetworkAlert(onOK: onOK)
                } else {
                    showAlert(title: lang("Error"),
                              text: bridgeCallErrorMessages.toLocalized,
                              button: lang("OK")) {
                        onOK?()
                    }
                }
            case .customMessage(let string, _):
                showAlert(title: lang("Error"),
                          text: string,
                          button: lang("OK")) {
                    onOK?()
                }
            case .apiReturnedError(let error, _):
                showAlert(error: BridgeCallError.message(BridgeCallErrorMessages(rawValue: error) ?? .serverError, nil), onOK: onOK)
            default:
                showAlert(error: BridgeCallError.message(.serverError, nil), onOK: onOK)
            }
        } else if let error = error as? LocalizedError {
            showAlert(error: BridgeCallError.customMessage(error.errorDescription ?? error.localizedDescription, nil), onOK: onOK)
        } else {
            showAlert(error: BridgeCallError.customMessage(error.localizedDescription, nil), onOK: onOK)
        }
    }
    
    func removeChild(_ child: UIViewController) {
        guard child.parent == self else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}

@MainActor public func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.sceneKeyWindow
    
    if var topController = keyWindow?.rootViewController {
        while let presentedViewController = topController.presentedViewController {
            if presentedViewController.isBeingDismissed {
                break
            }
            topController = presentedViewController
        }
        
        return topController
    }

    return nil
}


@MainActor public func topWViewController() -> WViewController? {
    guard let topVC = topViewController() else { return nil }
    if let wViewController = topVC.visibleContentViewController as? WViewController {
        return wViewController
    }
    if let presentingVC = topVC.presentingViewController {
        if let wViewController = presentingVC.visibleContentViewController as? WViewController {
            return wViewController
        }
    }
    return nil
}

@MainActor public func endEditing() {
    UIApplication.shared.anySceneKeyWindow?.endEditing(true)
}

@MainActor public protocol VisibleContentProviding {
    var visibleContentProviderViewController: UIViewController { get }
}

public extension UIViewController {
    var visibleContentViewController: UIViewController {
        if let provider = self as? VisibleContentProviding {
            return provider.visibleContentProviderViewController.visibleContentViewController
        }
        if let navigation = self as? UINavigationController,
           let visible = navigation.visibleViewController ?? navigation.topViewController {
            return visible.visibleContentViewController
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.visibleContentViewController
        }
        if let split = self as? UISplitViewController, let last = split.viewControllers.last {
            return last.visibleContentViewController
        }
        return self
    }
    
    func descendantViewController<T: UIViewController>(of type: T.Type) -> T? {
        if let vc = self as? T {
            return vc
        }
        for child in children {
            if let vc = child.descendantViewController(of: type) {
                return vc
            }
        }
        return nil
    }
    
    func descendantViewController(where predicate: (UIViewController) -> Bool) -> UIViewController? {
        if predicate(self) {
            return self
        }
        for child in children {
            if let vc = child.descendantViewController(where: predicate) {
                return vc
            }
        }
        return nil
    }
}
