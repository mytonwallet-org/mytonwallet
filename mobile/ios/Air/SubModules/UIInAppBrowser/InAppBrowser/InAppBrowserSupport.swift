import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("InAppBrowserSupport")

@MainActor
public final class InAppBrowserSupport: NSObject, WalletCoreData.EventsObserver, UIAdaptivePresentationControllerDelegate {

    public static let shared = InAppBrowserSupport()

    private enum BrowserState {
        case closed
        case minimized
        case minimizableSheetPresented
        case systemSheetPresented
    }

    private enum SystemSheetDismissBehavior {
        case minimizeToMinimizableSheet
        case closeAndReset
    }

    private var browser: InAppBrowserVC?
    private var sheetStateObservation: MinimizableSheetObservation?
    private weak var observedSheetController: MinimizableSheetController?
    private var state: BrowserState = .closed
    private var systemSheetDismissBehavior: SystemSheetDismissBehavior = .minimizeToMinimizableSheet

    private var sheetContainerViewController: MinimizableSheetContainerViewController? {
        UIApplication.shared.sceneKeyWindow?.rootViewController?
            .descendantViewController(of: MinimizableSheetContainerViewController.self)
    }

    private var sheetViewController: MinimizableSheetContentViewController? {
        sheetContainerViewController?.sheetViewController as? MinimizableSheetContentViewController
    }

    private var sheetController: MinimizableSheetController? {
        sheetContainerViewController?.sheetController
    }

    private override init() {
        super.init()
        WalletCoreData.add(eventObserver: self)
    }

    public func start() {
        observeSheetStateIfNeeded()
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            if state == .minimized {
                closeBrowser(animated: false)
            }
        case .dappDisconnect(accountId: let accountId, origin: let origin):
            if accountId == AccountStore.accountId,
               let browser,
               origin == browser.currentPage?.config.url.origin,
               state != .minimizableSheetPresented {
                browser.reload()
            }
        default:
            break
        }
    }

    /// Called through AppActions
    public func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool) {
        let config = InAppBrowserPageConfig(url: url, title: title, injectDappConnect: injectDappConnect)
        let browser = ensureBrowser()
        browser.openPage(config: config)

        if shouldPresentInSystemSheet() {
            transitionToSystemSheet(browser)
        } else {
            transitionToMinimizableSheet(browser, targetSheetState: .expanded, animated: true)
        }
    }

    private func ensureBrowser() -> InAppBrowserVC {
        if let browser {
            return browser
        }
        let browser = InAppBrowserVC()
        browser.onCloseRequested = { [weak self] in
            self?.handleBrowserCloseRequested()
        }
        self.browser = browser
        return browser
    }

    private func shouldPresentInSystemSheet() -> Bool {
        guard let root = UIApplication.shared.sceneKeyWindow?.rootViewController else { return false }
        return root.presentedViewController != nil
    }

    private func transitionToSystemSheet(_ browser: InAppBrowserVC) {
        state = .systemSheetPresented
        observeSheetStateIfNeeded()
        systemSheetDismissBehavior = .minimizeToMinimizableSheet

        if sheetViewController?.browser === browser {
            sheetViewController?.setBrowser(nil)
        }
        if let sheetController, sheetController.state != .hidden {
            sheetController.close(animated: false)
        }
        browser.view.layer.removeAllAnimations()
        browser.view.alpha = 1

        if browser.presentingViewController != nil {
            configureSystemSheet(browser)
            return
        }

        guard let presenter = systemSheetPresenter() else {
            log.fault("system browser sheet presenter is unavailable")
            transitionToMinimizableSheet(browser, targetSheetState: .expanded, animated: true)
            return
        }

        browser.modalPresentationStyle = .pageSheet
        presenter.present(browser, animated: true) { [weak self, weak browser] in
            guard let self, let browser else { return }
            self.configureSystemSheet(browser)
        }
    }

    private func transitionToMinimizableSheet(
        _ browser: InAppBrowserVC,
        targetSheetState: MinimizableSheetState,
        animated: Bool
    ) {
        observeSheetStateIfNeeded()

        guard let sheetViewController, let sheetController else {
            log.fault("minimizable sheet container is unavailable")
            finalizeClosedState()
            return
        }

        systemSheetDismissBehavior = .minimizeToMinimizableSheet
        sheetViewController.setBrowser(browser)
        sheetController.setState(targetSheetState, animated: animated)
        updateStateFromMinimizableSheetState(targetSheetState)
    }

    private func systemSheetPresenter() -> UIViewController? {
        var candidate = topViewController()
        while candidate is UIAlertController {
            candidate = candidate?.presentingViewController
        }
        return candidate ?? UIApplication.shared.sceneKeyWindow?.rootViewController
    }

    private func configureSystemSheet(_ browser: InAppBrowserVC) {
        browser.presentationController?.delegate = self
        if let sheet = browser.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
        }
    }

    private func handleBrowserCloseRequested() {
        closeBrowser(animated: true)
    }

    private func closeBrowser(animated: Bool) {
        switch state {
        case .closed:
            finalizeClosedState()
        case .systemSheetPresented:
            systemSheetDismissBehavior = .closeAndReset
            if let browser, browser.presentingViewController != nil {
                browser.dismiss(animated: animated)
            } else {
                finalizeClosedState()
            }
        case .minimized, .minimizableSheetPresented:
            if let sheetController, sheetController.state != .hidden {
                sheetController.close(animated: animated)
            } else {
                finalizeClosedState()
            }
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard state == .systemSheetPresented else { return }
        if let browser, presentationController.presentedViewController !== browser {
            return
        }
        switch systemSheetDismissBehavior {
        case .minimizeToMinimizableSheet:
            guard let browser else {
                finalizeClosedState()
                return
            }
            transitionToMinimizableSheet(browser, targetSheetState: .minimized, animated: true)
        case .closeAndReset:
            finalizeClosedState()
        }
    }

    private func observeSheetStateIfNeeded() {
        guard let controller = sheetController else { return }
        guard observedSheetController !== controller else { return }

        sheetStateObservation?.invalidate()
        observedSheetController = controller
        sheetStateObservation = controller.addObserver(options: .stateChanges) { [weak self] event in
            guard let self else { return }
            guard case let .stateDidChange(change) = event else { return }
            self.handleMinimizableSheetStateChange(change.toState)
        }

        handleMinimizableSheetStateChange(controller.state)
    }

    private func handleMinimizableSheetStateChange(_ sheetState: MinimizableSheetState) {
        guard state != .systemSheetPresented else { return }
        updateStateFromMinimizableSheetState(sheetState)

        if sheetState == .hidden, state == .closed, browser != nil {
            finalizeClosedState()
        }
    }

    private func updateStateFromMinimizableSheetState(_ sheetState: MinimizableSheetState) {
        guard state != .systemSheetPresented else { return }
        switch sheetState {
        case .expanded:
            if browser != nil {
                state = .minimizableSheetPresented
            } else {
                state = .closed
            }
        case .minimized:
            if browser != nil {
                state = .minimized
            } else {
                state = .closed
            }
        case .hidden:
            if state == .minimized || state == .minimizableSheetPresented {
                state = .closed
            }
        }
    }

    private func finalizeClosedState() {
        if let browser, browser.presentingViewController != nil {
            browser.dismiss(animated: false)
        }
        if let sheetController, sheetController.state != .hidden {
            sheetController.close(animated: false)
        }
        sheetViewController?.setBrowser(nil)
        browser = nil
        state = .closed
        systemSheetDismissBehavior = .minimizeToMinimizableSheet
    }
}
