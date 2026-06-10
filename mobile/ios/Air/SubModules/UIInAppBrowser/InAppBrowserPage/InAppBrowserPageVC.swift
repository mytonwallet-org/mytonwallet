import UIKit
import WebKit
import UIDapp
import UIComponents
import WalletCore
import WalletContext

private let log = Log("InAppBrowserPageVC")

protocol InAppBrowserPageDelegate: AnyObject {
    func inAppBrowserPageStateChanged(_ browserPageVC: InAppBrowserPageVC)
    func inAppBrowserPage(_ browserPageVC: InAppBrowserPageVC, wantsOpenNewPageWith config: InAppBrowserPageConfig)
    func inAppBrowserPage(_ browserPageVC: InAppBrowserPageVC, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction) -> WKWebView?
    func inAppBrowserPageWantsClose(_ browserPageVC: InAppBrowserPageVC)
}

struct InAppBrowserPageState {
    let id: UUID
    var url: URL
    var title: String?
    var canGoBack: Bool
    var previewImage: UIImage?
}

final class InAppBrowserPageVC: WViewController {

    var id: UUID { state.id }
    private(set) var state: InAppBrowserPageState
    private var config: InAppBrowserPageConfig {
        didSet {
            messageHandler.config = config
        }
    }
    weak var delegate: (any InAppBrowserPageDelegate)?

    private let messageHandler: InAppBrowserMessageHandler
    private let initialWebViewConfiguration: WKWebViewConfiguration?
    private let loadsInitialRequest: Bool

    /// Use WalletCoreData.notify(.openInBrowser(...)) to open a browser window
    init(
        config: InAppBrowserPageConfig,
        webViewConfiguration: WKWebViewConfiguration? = nil,
        loadsInitialRequest: Bool = true
    ) {
        self.config = config
        self.state = InAppBrowserPageState(
            id: UUID(),
            url: config.url,
            title: config.title,
            canGoBack: false,
            previewImage: nil
        )
        self.messageHandler = InAppBrowserMessageHandler(config: config)
        self.initialWebViewConfiguration = webViewConfiguration
        self.loadsInitialRequest = loadsInitialRequest
        super.init(nibName: nil, bundle: nil)
        self.messageHandler.onOpenWindow = { [weak self] url in
            self?.openNewPage(url: url)
        }
        self.messageHandler.onCloseWindow = { [weak self] in
            guard let self else { return }
            self.delegate?.inAppBrowserPageWantsClose(self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Model and UI Components
    private var webView: WKWebView? {
        didSet {
            messageHandler.webView = webView
        }
    }
    private var urlObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var backObserver: NSKeyValueObservation?
    private lazy var downloadManager = DownloadManager(presentingViewController: self)

    isolated deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "inAppBrowserHandler")
    }

    // MARK: - Load and SetupView Functions
    override func loadView() {
        super.loadView()
        setupViews()
        setupObservers()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if loadsInitialRequest {
            webView?.load(URLRequest(url: config.url))
        }
    }

    private func setupViews() {
        view.backgroundColor = .air.background
        view.translatesAutoresizingMaskIntoConstraints = false

        let webViewConfiguration = initialWebViewConfiguration ?? WKWebViewConfiguration()
        configure(webViewConfiguration)
        webViewConfiguration.allowsInlineMediaPlayback = true

        // create web view
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                            configuration: webViewConfiguration)

        // while this is preferrable to setting top constraint constant to 60, it caused jittering when dismissing fragment.com - check if support is better in the future
//        webView.scrollView.contentInset.top = 60
//        webView.scrollView.verticalScrollIndicatorInsets.top = 60
//        webView.scrollView.contentInset.bottom = 30

        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        webView.isOpaque = false // prevents flashing white during load

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor, constant: 60), // see comment above
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30)
        ])
        webView.clipsToBounds = false
        webView.scrollView.clipsToBounds = false // see comment above

        delegate?.inAppBrowserPageStateChanged(self)

        updateTheme()
    }

    private func configure(_ webViewConfiguration: WKWebViewConfiguration) {
        webViewConfiguration.userContentController = WKUserContentController()
        let userContentController = webViewConfiguration.userContentController
        userContentController.add(messageHandler, name: "inAppBrowserHandler")

        guard config.injectDappConnect else { return }

        let bridgeScript = WKUserScript(
            source: BridgeInjectionScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(bridgeScript)

        let tonConnectScript = WKUserScript(
            source: TonConnectInjectionScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(tonConnectScript)

        let evmConnectScript = WKUserScript(
            source: EvmConnectInjectionScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(evmConnectScript)

        let walletConnectScript = WKUserScript(
            source: WalletConnectInjectionScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(walletConnectScript)
    }

    private func setupObservers() {
        self.urlObserver = webView?.observe(\.url) { [weak self] webView, _ in
            Task { @MainActor in
                if let self, let url = webView.url {
                    self.config.url = url
                    self.state.url = url
                    self.delegate?.inAppBrowserPageStateChanged(self)
                }
            }
        }
        self.titleObserver = webView?.observe(\.title) { [weak self] webView, _ in
            Task { @MainActor in
                if let self {
                    self.config.title = webView.title
                    self.state.title = webView.title
                    self.delegate?.inAppBrowserPageStateChanged(self)
                }
            }
        }
        self.backObserver = webView?.observe(\.canGoBack) { [weak self] webView, _ in
            Task { @MainActor in
                if let self {
                    self.state.canGoBack = webView.canGoBack
                    self.delegate?.inAppBrowserPageStateChanged(self)
                }
            }
        }
    }

    private func updateTheme() {
        view.backgroundColor = .air.background
        webView?.backgroundColor = .air.background
        webView?.scrollView.backgroundColor = .air.background
    }

    func reload() {
        webView?.reload()
    }

    func navigate(to url: URL) {
        webView?.load(URLRequest(url: url))
    }

    func goBackInHistory() {
        webView?.goBack()
    }

    func hasOrigin(_ origin: String) -> Bool {
        state.url.origin == origin
    }

    func childConfig(url: URL) -> InAppBrowserPageConfig {
        InAppBrowserPageConfig(
            url: url,
            injectDappConnect: config.injectDappConnect,
            historyTag: config.historyTag
        )
    }

    func webViewForWebKitPopup() -> WKWebView? {
        webView
    }

    func capturePreview(completion: (() -> Void)? = nil) {
        guard let webView, webView.bounds.width > 0, webView.bounds.height > 0 else {
            completion?()
            return
        }
        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.rect = webView.bounds
        snapshotConfiguration.snapshotWidth = NSNumber(value: Double(min(webView.bounds.width, 640)))
        webView.takeSnapshot(with: snapshotConfiguration) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else {
                    completion?()
                    return
                }
                self.state.previewImage = image
                self.delegate?.inAppBrowserPageStateChanged(self)
                completion?()
            }
        }
    }

    func openInSafari() {
        guard UIApplication.shared.canOpenURL(state.url) else { return }
        UIApplication.shared.open(state.url, options: [:], completionHandler: nil)
    }

    func copyUrl() {
        UIPasteboard.general.string = state.url.absoluteString
    }

    func share() {
        let activityViewController = UIActivityViewController(activityItems: [state.url], applicationActivities: nil)
        activityViewController.excludedActivityTypes = [.assignToContact, .print]
        presentActivityViewController(activityViewController, sourceView: webView)
    }

    private func openNewPage(url: URL) {
        delegate?.inAppBrowserPage(self, wantsOpenNewPageWith: childConfig(url: url))
    }
}

extension InAppBrowserPageVC: WKNavigationDelegate, WKUIDelegate {

    // Fetches the first declared favicon href from the page, falling back to /favicon.ico.
    private static let fetchFaviconScript = """
        (function() {
            var link = document.querySelector('link[rel~="icon"]') ||
                    document.querySelector('link[rel="shortcut icon"]');
            return link ? link.href : (window.location.origin + '/favicon.ico');
        })()
    """

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tag = config.historyTag,
              let url = webView.url,
              url.scheme == "https" || url.scheme == "http" else { return }
        let title = webView.title?.nilIfEmpty ?? url.host ?? url.absoluteString
        webView.evaluateJavaScript(Self.fetchFaviconScript) { result, _ in
            let favicon = (result as? String) ?? ""
            Task { @MainActor in
                guard let accountId = AccountStore.accountId else { return }
                BrowserHistoryStore.shared.saveVisit(
                    accountId: accountId,
                    url: url.absoluteString,
                    title: title,
                    favicon: favicon,
                    tag: tag
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    }

    func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if downloadManager.handleNavigationResponse(navigationResponse, webView: webView) {
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {

        guard let url = navigationAction.request.url else {
            return .cancel
        }

        let allowedSchemes = ["itms-appss", "itms-apps", "tel", "sms", "mailto", "geo", "tg", SELF_PROTOCOL_SCHEME]
        var shouldStart = true
        var shouldDismiss = false

        if let scheme = url.scheme, allowedSchemes.contains(scheme) {
            webView.stopLoading()
            openSystemUrl(url)
            shouldStart = false
            if scheme == SELF_PROTOCOL_SCHEME {
                shouldDismiss = true
            }
        }

        if WalletContextManager.delegate?.handleDeeplink(url: url) ?? false {
            shouldStart = false
            shouldDismiss = true
        }
        defer {
            if shouldDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self.presentingViewController?.dismiss(animated: true)
                }
            }
        }
        if shouldStart {
            let scheme = url.scheme?.lowercased()
            if navigationAction.targetFrame == nil, scheme == "http" || scheme == "https" {
                openNewPage(url: url)
                return .cancel
            } else {
                return .allow
            }
        } else {
            return .cancel
        }
    }

    private func openSystemUrl(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        delegate?.inAppBrowserPage(self, createWebViewWith: configuration, for: navigationAction)
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.inAppBrowserPageWantsClose(self)
    }
}
