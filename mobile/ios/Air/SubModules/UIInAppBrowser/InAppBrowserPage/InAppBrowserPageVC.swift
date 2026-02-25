import UIKit
import WebKit
import UIDapp
import UIComponents
import WalletCore
import WalletContext

private var log = Log("InAppBrowserPageVC")

protocol InAppBrowserPageDelegate: AnyObject {
    func inAppBrowserPageStateChanged(_ browserPageVC: InAppBrowserPageVC)
}

final class InAppBrowserPageVC: WViewController {
    
    private(set) var config: InAppBrowserPageConfig {
        didSet {
            messageHandler.config = config
        }
    }
    weak var delegate: (any InAppBrowserPageDelegate)?
    
    private let messageHandler: InAppBrowserMessageHandler
    
    /// Use WalletCoreData.notify(.openInBrowser(...)) to open a browser window
    init(config: InAppBrowserPageConfig) {
        self.config = config
        self.messageHandler = InAppBrowserMessageHandler(config: config)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Model and UI Components
    private(set) var webView: WKWebView? {
        didSet {
            messageHandler.webView = webView
        }
    }
    private var urlObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var backObserver: NSKeyValueObservation?
    private lazy var downloadManager = DownloadManager(presentingViewController: self)
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }
    
    // MARK: - Load and SetupView Functions
    override func loadView() {
        super.loadView()
        setupViews()
        setupObservers()
    }
    
    private func setupViews() {
        view.backgroundColor = WTheme.background
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let webViewConfiguration = WKWebViewConfiguration()
        
        // make logging possible to get results from js promise
        let userContentController = WKUserContentController()
        userContentController.add(messageHandler, name: "inAppBrowserHandler")
        
        webViewConfiguration.userContentController = userContentController
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
        
        if config.injectDappConnect {
            let bridgeScript = WKUserScript(
                source: BridgeInjectionScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(bridgeScript)

            let tonConnectScript = WKUserScript(
                source: TonConnectInjectionScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(tonConnectScript)

            let walletConnectScript = WKUserScript(
                source: WalletConnectInjectionScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(walletConnectScript)
        }
        webView.load(URLRequest(url: config.url))
        delegate?.inAppBrowserPageStateChanged(self)
        
        updateTheme()
    }
    
    func setupObservers() {
        self.urlObserver = webView?.observe(\.url) { [weak self] webView, _ in
            if let self, let url = webView.url {
                self.config.url = url
                self.delegate?.inAppBrowserPageStateChanged(self)
            }
        }
        self.titleObserver = webView?.observe(\.title) { [weak self] webView, _ in
            if let self {
                self.config.title = webView.title
                self.delegate?.inAppBrowserPageStateChanged(self)
            }
        }
        self.backObserver = webView?.observe(\.canGoBack) { [weak self] webView, _ in
            if let self {
                self.delegate?.inAppBrowserPageStateChanged(self)
            }
        }
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.background
        webView?.backgroundColor = WTheme.background
        webView?.scrollView.backgroundColor = WTheme.background
    }
    
    func reload() {
        webView?.reload()
    }
    
    func openInSafari() {
        guard UIApplication.shared.canOpenURL(config.url) else { return }
        UIApplication.shared.open(config.url, options: [:], completionHandler: nil)
    }
    
    func copyUrl() {
        UIPasteboard.general.string = config.url.absoluteString
    }
    
    func share() {
        let activityViewController = UIActivityViewController(activityItems: [config.url], applicationActivities: nil)
        activityViewController.excludedActivityTypes = [.assignToContact, .print]
        activityViewController.popoverPresentationController?.sourceView = self.webView
        self.present(activityViewController, animated: true, completion: nil)
    }
}

extension InAppBrowserPageVC: WKNavigationDelegate, WKUIDelegate {
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    }
    
    func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if downloadManager.handleNavigationResponse(navigationResponse, webView: webView) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            return decisionHandler(.cancel)
        }
        
        let allowedSchemes = ["itms-appss", "itms-apps", "tel", "sms", "mailto", "geo", "tg", "mtw"]
        var shouldStart = true
        var shouldDismiss = false
        
        if let scheme = url.scheme, allowedSchemes.contains(scheme) {
            webView.stopLoading()
            openSystemUrl(url)
            shouldStart = false
            if scheme == "mtw" {
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
            // Handle links with target="_blank"
            if navigationAction.targetFrame == nil {
                openSystemUrl(url)
                return decisionHandler(.cancel)
            } else {
                return decisionHandler(.allow)
            }
        } else {
            return decisionHandler(.cancel)
        }
    }
    
    private func openSystemUrl(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:])
        }
    }
}
