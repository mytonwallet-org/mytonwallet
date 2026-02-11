import Foundation
import UIKit
import Capacitor

/**
 * Implement three common native-dialog types: alert, confirm, and prompt
 */
@objc(DialogPlugin)
public class DialogPlugin: CAPPlugin {
    private var alertWindow: UIWindow?

    private func makeAlertWindow() -> UIWindow? {
        let scene = self.bridge?.viewController?.view.window?.windowScene
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let windowScene = scene else {
            return nil
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIViewController()
        window.windowLevel = UIWindow.Level.alert + 1
        window.makeKeyAndVisible()
        alertWindow = window
        return window
    }

    @objc public func alert(_ call: CAPPluginCall) {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            call.reject("Please provide a message for the dialog")
            return
        }
        let buttonTitle = call.options["buttonTitle"] as? String ?? "OK"

        DispatchQueue.main.async {
            guard let alertWindow = self.makeAlertWindow() else {
                call.reject("Unable to present dialog: no active window scene")
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: { (_) -> Void in
                call.resolve()
                self.cleanupWindow(alertWindow)
            }))

            alertWindow.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }

    @objc public func confirm(_ call: CAPPluginCall) {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            call.reject("Please provide a message for the dialog")
            return
        }
        let okButtonTitle = call.options["okButtonTitle"] as? String ?? "OK"
        let cancelButtonTitle = call.options["cancelButtonTitle"] as? String ?? "Cancel"

        DispatchQueue.main.async {
            guard let alertWindow = self.makeAlertWindow() else {
                call.reject("Unable to present dialog: no active window scene")
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: cancelButtonTitle, style: .default, handler: { (_) -> Void in
                call.resolve([
                    "value": false
                ])
                self.cleanupWindow(alertWindow)
            }))
            alert.addAction(UIAlertAction(title: okButtonTitle, style: .default, handler: { (_) -> Void in
                call.resolve([
                    "value": true
                ])
                self.cleanupWindow(alertWindow)
            }))

            alertWindow.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }

    @objc public func prompt(_ call: CAPPluginCall) {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            call.reject("Please provide a message for the dialog")
            return
        }
        let okButtonTitle = call.options["okButtonTitle"] as? String ?? "OK"
        let cancelButtonTitle = call.options["cancelButtonTitle"] as? String ?? "Cancel"
        let inputPlaceholder = call.options["inputPlaceholder"] as? String ?? ""
        let inputText = call.options["inputText"] as? String ?? ""

        DispatchQueue.main.async {
            guard let alertWindow = self.makeAlertWindow() else {
                call.reject("Unable to present dialog: no active window scene")
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { (textField) in
                textField.placeholder = inputPlaceholder
                textField.text = inputText
            }

            alert.addAction(UIAlertAction(title: cancelButtonTitle, style: .default, handler: { (_) -> Void in
                call.resolve([
                    "value": "",
                    "cancelled": true
                ])
                self.cleanupWindow(alertWindow)
            }))
            alert.addAction(UIAlertAction(title: okButtonTitle, style: .default, handler: { (_) -> Void in
                let textField = alert.textFields?.first
                call.resolve([
                    "value": textField?.text ?? "",
                    "cancelled": false
                ])
                self.cleanupWindow(alertWindow)
            }))

            alertWindow.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }

    private func cleanupWindow(_ window: UIWindow?) {
        window?.isHidden = true
        window?.rootViewController = nil
        window?.windowLevel = UIWindow.Level.normal
        if alertWindow === window {
            alertWindow = nil
        }
    }
}
