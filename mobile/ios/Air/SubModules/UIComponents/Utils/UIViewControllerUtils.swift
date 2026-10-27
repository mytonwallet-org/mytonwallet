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
        } else if let error = error as? SdkError {
            switch error {
            case .message(let message):
                showAlert(apiError: message, onOK: onOK)
            case .apiReturnedError(let rawError, let displayError, _):
                if let displayError {
                    showAlert(apiError: displayError, onOK: onOK)
                } else {
                    showAlert(title: lang("Error"),
                              text: rawError,
                              button: lang("OK")) {
                        onOK?()
                    }
                }
            default:
                showAlert(title: lang("Error"),
                          text: error.errorDescription ?? error.localizedDescription,
                          button: lang("OK")) {
                    onOK?()
                }
            }
        } else if let error = error as? ApiAnyDisplayError {
            showAlert(apiError: error, onOK: onOK)
        } else if let error = error as? LocalizedError {
            showAlert(title: lang("Error"),
                      text: error.errorDescription ?? error.localizedDescription,
                      button: lang("OK")) {
                onOK?()
            }
        } else {
            showAlert(title: lang("Error"),
                      text: error.localizedDescription,
                      button: lang("OK")) {
                onOK?()
            }
        }
    }

    @MainActor private func showAlert(apiError: ApiAnyDisplayError, onOK: (() -> Void)? = nil) {
        showAlert(title: lang("Error"),
                  text: apiError.toLocalized,
                  button: lang("OK")) {
            onOK?()
        }
    }
    
    func removeChild(_ child: UIViewController) {
        guard child.parent == self else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    @MainActor func presentActivityViewController(
        _ activityViewController: UIActivityViewController,
        sourceView: UIView? = nil,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        var presenter: UIViewController = self
        while presenter is UIAlertController || presenter is UIActivityViewController {
            guard let presentingViewController = presenter.presentingViewController else {
                break
            }
            presenter = presentingViewController
        }

        if let popover = activityViewController.popoverPresentationController {
            let popoverSourceView: UIView
            if let sourceView, sourceView.window != nil {
                popoverSourceView = sourceView
            } else if let presenterView = presenter.viewIfLoaded, presenterView.window != nil {
                popoverSourceView = presenterView
            } else {
                popoverSourceView = presenter.view
            }
            popover.sourceView = popoverSourceView
            popover.sourceRect = CGRect(
                x: popoverSourceView.bounds.midX,
                y: popoverSourceView.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activityViewController, animated: animated, completion: completion)
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

    private var presentationHostViewController: UIViewController {
        var host = self
        while let parent = host.parent {
            host = parent
        }
        return host
    }

    var windowHorizontalSizeClass: UIUserInterfaceSizeClass {
        if let sizeClass = viewIfLoaded?.window?.traitCollection.horizontalSizeClass,
           sizeClass != .unspecified {
            return sizeClass
        }
        if let sizeClass = presentationHostViewController.presentingViewController?.viewIfLoaded?.window?.traitCollection.horizontalSizeClass,
           sizeClass != .unspecified {
            return sizeClass
        }
        return .unspecified
    }

    var isPresentedInRegularWidthWindow: Bool {
        windowHorizontalSizeClass == .regular
    }

    var isSheetPresentationAttachedToBottom: Bool {
        sheetPresentationMode == .bottomAttached
    }

    var sheetPresentationMode: SheetPresentationMode? {
        let host = presentationHostViewController
        guard let presenter = host.presentingViewController else { return nil }
        return host.sheetPresentationMode(presentingFrom: presenter)
    }

    /// Resolve before presentation using the window, since a floating sheet can itself have compact traits.
    func sheetPresentationMode(presentingFrom presenter: UIViewController) -> SheetPresentationMode? {
        let host = presentationHostViewController
        switch host.modalPresentationStyle {
        case .fullScreen, .overFullScreen:
            return .fullScreen
        case .automatic, .pageSheet, .formSheet:
            guard let sheet = host.sheetPresentationController else { return nil }
            let traits = presenter.viewIfLoaded?.window?.traitCollection ?? presenter.traitCollection
            return SheetPresentationMode(
                traits: traits,
                prefersEdgeAttachedInCompactHeight: sheet.prefersEdgeAttachedInCompactHeight
            )
        default:
            return nil
        }
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
