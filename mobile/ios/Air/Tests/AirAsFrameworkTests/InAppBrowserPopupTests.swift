import UIKit
import WalletContext
import WalletResources
import WebKit
import XCTest
@testable import UIInAppBrowser

@MainActor
final class InAppBrowserPopupTests: XCTestCase {
    func testWalletConnectPopupDispatchesOnceWithoutOpeningATab() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        try await browser.webView.evaluateJavaScript("window.open('mywallet-wc://wc?uri=wc%3Atest', '_blank'); void 0")
        try await waitFor { !browser.deeplinks.isEmpty }
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(browser.deeplinks.count, 1)
        XCTAssertEqual(browser.deeplinks.first?.1, .inAppBrowser)
        XCTAssertTrue(browser.popups.isEmpty)
    }

    func testDelayedPopupKeepsAWindowHandleAndReusesNamedTab() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        try await browser.webView.evaluateJavaScript("""
            setTimeout(() => { window.popup = window.open('https://popup.example/', 'walletPopup'); }, 0); void 0
            """)
        try await waitFor { !browser.popups.isEmpty }
        let hasHandle = try await browser.webView.evaluateJavaScript("window.popup !== null && !window.popup.closed")
        XCTAssertEqual(hasHandle as? Bool, true)
        let sameWindow = try await browser.webView.evaluateJavaScript("window.open('https://popup.example/second', 'walletPopup') === window.popup")
        XCTAssertEqual(sameWindow as? Bool, true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(browser.popups.count, 1)

        let popup = try XCTUnwrap(browser.popups.first?.webViewForWebKitPopup())
        popup.stopLoading()
        let hasOpener = try await popup.evaluateJavaScript("window.opener !== null")
        XCTAssertEqual(hasOpener as? Bool, true)
        try await popup.evaluateJavaScript("window.close(); void 0")
        try await waitFor { browser.closedPages.count == 1 }
    }

    func testSelfTargetNavigatesWithoutOpeningATab() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        let sameWindow = try await browser.webView.evaluateJavaScript("window.open('#same-tab', '_self') === window")
        XCTAssertEqual(sameWindow as? Bool, true)
        try await waitFor { browser.webView.url?.fragment == "same-tab" }
        XCTAssertTrue(browser.popups.isEmpty)
    }

    func testExplicitTonConnectWindowOpenBridgeStillRoutesOnce() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        try await browser.webView.evaluateJavaScript("window._mtwAir_invokeFunc('window:open', { url: 'mywallet-wc://wc?uri=wc%3Atest' }); void 0")
        try await waitFor { !browser.deeplinks.isEmpty }
        XCTAssertEqual(browser.deeplinks.first?.1, .inAppBrowser)
        XCTAssertTrue(browser.popups.isEmpty)
    }

    func testNoopenerPopupCreatesOnlyOneTabDespiteReturningNull() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        let isNull = try await browser.webView.evaluateJavaScript("window.open('https://popup.example/', '_blank', 'noopener') === null")
        XCTAssertEqual(isNull as? Bool, true)
        try await waitFor { !browser.popups.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(browser.popups.count, 1)
        XCTAssertEqual(browser.popups.first?.state.url.host, "popup.example")
        XCTAssertTrue(browser.deeplinks.isEmpty)
    }

    func testBlankTargetLinkOpensOneTab() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        try await browser.webView.evaluateJavaScript("""
            const link = document.createElement('a');
            link.href = 'https://popup.example/link';
            link.target = '_blank';
            document.body.append(link);
            link.click(); void 0
            """)
        try await waitFor { !browser.popups.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(browser.popups.count, 1)
        XCTAssertTrue(browser.deeplinks.isEmpty)
    }

    func testOfframpAndSubframePopupsCannotReachNativeRouting() async throws {
        let browser = try await makeBrowser()
        defer { browser.close() }

        try await browser.webView.evaluateJavaScript("""
            window.open('\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test', '_blank');
            const frame = document.createElement('iframe');
            frame.srcdoc = '<script>window.open("mywallet-wc://wc?uri=wc%3Atest", "_blank"); window.open("https://popup.example/", "_blank");</script>';
            document.body.append(frame); void 0
            """)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(browser.deeplinks.isEmpty)
        XCTAssertTrue(browser.popups.isEmpty)
    }

    private func makeBrowser() async throws -> PopupBrowser {
        _ = WalletResourcesBundle.bundle.load()
        let browser = PopupBrowser()
        browser.webView.loadHTMLString("<html><body id='ready'>Popup tests</body></html>", baseURL: URL(string: "https://dapp.example/"))
        try await waitFor {
            (try? await browser.webView.evaluateJavaScript("document.body?.id === 'ready'")) as? Bool == true
        }
        return browser
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<250 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for WebKit")
        throw PopupTestError.timeout
    }
}

private enum PopupTestError: Error { case timeout }

@MainActor
private final class PopupBrowser: NSObject, InAppBrowserPageDelegate, WalletContextDelegate {
    private let previousDelegate: WalletContextDelegate?
    private let window: UIWindow
    private let page: InAppBrowserPageVC
    let webView: WKWebView
    private(set) var popups: [InAppBrowserPageVC] = []
    private(set) var closedPages: [UUID] = []
    private(set) var deeplinks: [(URL, DeeplinkOpenSource)] = []

    override init() {
        previousDelegate = WalletContextManager.delegate
        page = InAppBrowserPageVC(
            config: InAppBrowserPageConfig(url: URL(string: "https://dapp.example/")!, injectDappConnect: true),
            loadsInitialRequest: false
        )
        page.loadViewIfNeeded()
        webView = page.webViewForWebKitPopup()!
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        super.init()
        page.delegate = self
        WalletContextManager.delegate = self
        window.rootViewController = page
        window.makeKeyAndVisible()
    }

    func close() {
        WalletContextManager.delegate = previousDelegate
        window.isHidden = true
        window.rootViewController = nil
        webView.stopLoading()
        for popup in popups { popup.webViewForWebKitPopup()?.stopLoading() }
        popups.removeAll()
    }

    func inAppBrowserPageStateChanged(_ browserPageVC: InAppBrowserPageVC) {}

    func inAppBrowserPage(_ browserPageVC: InAppBrowserPageVC, wantsOpenNewPageWith config: InAppBrowserPageConfig) {
        let popup = InAppBrowserPageVC(config: config, loadsInitialRequest: false)
        popup.delegate = self
        popup.loadViewIfNeeded()
        popups.append(popup)
    }

    func inAppBrowserPage(_ browserPageVC: InAppBrowserPageVC, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction) -> WKWebView? {
        let popup = InAppBrowserPageVC(
            config: browserPageVC.childConfig(url: navigationAction.request.url ?? URL(string: "about:blank")!),
            webViewConfiguration: configuration,
            loadsInitialRequest: false
        )
        popup.delegate = self
        popup.loadViewIfNeeded()
        popups.append(popup)
        return popup.webViewForWebKitPopup()
    }

    func inAppBrowserPageWantsClose(_ browserPageVC: InAppBrowserPageVC) {
        closedPages.append(browserPageVC.id)
    }

    func handleDeeplink(url: URL, source: DeeplinkOpenSource) -> Bool {
        deeplinks.append((url, source))
        return true
    }

    func bridgeIsReady() {}
    func walletIsReady(isReady: Bool) {}
    func restartApp() {}
    var isWalletReady: Bool { true }
    var isAppUnlocked: Bool { true }
}
