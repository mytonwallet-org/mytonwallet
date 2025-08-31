
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("InAppBrowserSupport")

public final class InAppBrowserSupport: WalletCoreData.EventsObserver, WMinimizableSheetDelegate {
    
    public static let shared = InAppBrowserSupport()
    
    private weak var sheet: WMinimizableSheet?
    private var browser: InAppBrowserVC?
    
    @MainActor private var presentedPrimarySheet: WMinimizableSheet? {
        let rootVC = UIApplication.shared.sceneKeyWindow?.rootViewController as? UITabBarController
        return rootVC?.presentedViewController as? WMinimizableSheet
    }
    
    private init() {
        inject_gestureRecognizerShouldBegin()
        WalletCoreData.add(eventObserver: self)
    }
    
    public func start() {
        // make sure it is initialized
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            self.sheet = nil
            self.browser = nil
        case .minimizedSheetChanged(let state):
            switch state {
            case .closedExternally:
                self.sheet = nil
                self.browser = nil
            default:
                break
            }
        case .dappDisconnect(accountId: let accountId, origin: let origin):
            if accountId == AccountStore.accountId, let browser, origin == browser.currentPage?.config.url.origin, sheet?.isExpanded != true {
                browser.reload()
            }
        case .sheetDismissed(let rootVC):
            restoreMinimizedBrowserIfNeeded(rootVC)
        default:
            break
        }
    }
    
    @MainActor public func openInBrowser(_ url: URL, title: String?, injectTonConnect: Bool) {
        let config = InAppBrowserPageVC.Config(url: url, title: title, injectTonConnectBridge: injectTonConnect)
        if let presentedPrimarySheet {
            if let browser = presentedPrimarySheet.browser {
                browser.openPage(config: config)
            } else if let browser {
                browser.openPage(config: config)
                presentedPrimarySheet.addBrowser(browser)
            } else {
                let browser = InAppBrowserVC()
                self.browser = browser
                browser.openPage(config: config)
                presentedPrimarySheet.addBrowser(browser)
            }
            presentedPrimarySheet.expand()
        } else if let browser {
            browser.openPage(config: config)
            let sheet = WMinimizableSheet(browser: browser)
            sheet.delegate = self
            self.sheet = sheet
            topViewController()?.present(sheet, animated: true)
        } else {
            let inAppBrowserVC = InAppBrowserVC()
            inAppBrowserVC.openPage(config: config)
            let sheet = WMinimizableSheet(browser: inAppBrowserVC)
            sheet.delegate = self
            self.sheet = sheet
            topViewController()?.present(sheet, animated: true)
        }
    }
    
    private func restoreMinimizedBrowserIfNeeded(_ rootVC: UIViewController) {
        if rootVC.presentedViewController == nil, let browser {
            let sheet = WMinimizableSheet(browser: browser, startMinimized: true)
            sheet.delegate = self
            self.sheet = sheet
            rootVC.present(sheet, animated: false)
        }
    }
        
    private func inject_gestureRecognizerShouldBegin() {
        guard let cls = NSClassFromString("_UIFormSheetPresentationController") else { return }
        let originalSelector = #selector(UIGestureRecognizerDelegate.gestureRecognizerShouldBegin(_:))
        let swizzledSelector = #selector(Self.swizzled_gestureRecognizerShouldBegin(_:))
        guard let swizzledMethod = class_getInstanceMethod(Self.self, swizzledSelector) else { return }
        _ = class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
    }
    
    @objc private func swizzled_gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // restrict impact of this method as much as possible
        if gestureRecognizer.description.contains("UISheetPresentationControllerExteriorPanGesture") {
            return false
        }
        return true
    }

    func minimizableSheetDidMinimize(_ sheet: WMinimizableSheet) {
        log.info("minimizableSheetDidMinimize")
        if let browser = sheet.removeBrowser() {
            self.browser = browser
        }
    }

    func minimizableSheetDidExpand(_ sheet: WMinimizableSheet) {
        log.info("minimizableSheetDidExpand")
        if let browser = self.browser {
            sheet.addBrowser(browser)
        }
    }

    func minimizableSheetWillDismiss(_ sheet: WMinimizableSheet) {
        log.info("minimizableSheetWillDismiss")
    }

    func minimizableSheetDidDismiss(_ sheet: WMinimizableSheet) {
        log.info("minimizableSheetDidDismiss")
        if let browser = sheet.removeBrowser() {
            self.browser = browser
        } else {
            self.browser = nil
        }
    }
    
    func minimizableSheetDidClose(_ sheet: WMinimizableSheet) {
        _ = sheet.removeBrowser()
        self.browser = nil
    }
}
