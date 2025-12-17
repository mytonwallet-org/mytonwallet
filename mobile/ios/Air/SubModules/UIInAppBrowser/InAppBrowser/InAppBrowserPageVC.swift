
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


public class InAppBrowserPageVC: WViewController {
    
    public struct Config {
        public var url: URL
        public var title: String?
        public let injectTonConnectBridge: Bool
        public init(url: URL, title: String? = nil, injectTonConnectBridge: Bool) {
            self.url = url
            self.title = title
            self.injectTonConnectBridge = injectTonConnectBridge
        }
    }
    
    public private(set) var config: Config
    internal weak var delegate: (any InAppBrowserPageDelegate)?
    
    /// Use WalletCoreData.notify(.openInBrowser(...)) to open a browser window
    internal init(config: Config) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Model and UI Components
    private(set) internal var webView: WKWebView?
    private var urlObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var backObserver: NSKeyValueObservation?
    
    var isMinimized: Bool {
        sheetPresentationController?.selectedDetentIdentifier == .minimized
    }
    
    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
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
        userContentController.add(self, name: "inAppBrowserHandler")
        
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
        
        if config.injectTonConnectBridge {
            let script = WKUserScript(source: InAppBrowserTonConnectInjectionHelpers.objectToInject(),
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(script)
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
    
    public override func updateTheme() {
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
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    // Called after any ton-connect related request to send response into browser
    @MainActor
    private func injectTonConnectResult(invocationId: String, result: Any?, error: Any?) async throws {
        let connectionResultMessage: [String: Any]
        if error == nil {
            guard let dict = result as? [String: Any] else {
                return
            }
            connectionResultMessage = [
                "type": InAppBrowserTonConnectInjectionHelpers.WebViewBridgeMessageType.functionResponse.rawValue,
                "invocationId": invocationId,
                "status": "fulfilled",
                "data": dict
            ]
        } else {
            connectionResultMessage = [
                "type": InAppBrowserTonConnectInjectionHelpers.WebViewBridgeMessageType.functionResponse.rawValue,
                "invocationId": invocationId,
                "status": "rejected",
                "data": error!
            ]
        }
        guard let jsonData = try? JSONEncoder().encode(AnyEncodable(dict: connectionResultMessage)),
              let resultInJSON = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let _ = try await webView?.callAsyncJavaScript(
          """
          window.dispatchEvent(new MessageEvent('message', {
            data: resultInJSON
          }));
          """,
          arguments: [
            "resultInJSON": resultInJSON,
          ],
          contentWorld: .page
        )
    }
}

extension InAppBrowserPageVC: WKNavigationDelegate, WKUIDelegate {
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    }
    
    public func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
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


extension InAppBrowserPageVC: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = (message.body as? String)?.data(using: .utf8) else {
            return
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
            return
        }
        TonConnect.shared.start()
        
        switch dict["type"] as? String {
        case "invokeFunc":
            switch dict["name"] as? String {
            case "connect":
                guard let connectArgs = dict["args"] as? [Any],
                      let invocationId = dict["invocationId"] as? String,
                      let tcVersion = connectArgs[0] as? Int,
                      let tonConnectArgs = connectArgs[1] as? [String: Any],
                      let origin = config.url.origin else {
                    return
                }
                if tcVersion > supportedTonConnectVersion {
                    return
                }
                guard let accountId = AccountStore.accountId else { return }
                let isUrlEnsured = self.webView?.hasOnlySecureContent
                let dappArg = ApiDappRequest(url: origin, isUrlEnsured: isUrlEnsured, accountId: accountId, identifier: JSBRIDGE_IDENTIFIER, sseOptions: nil)
                
                executeAndInjectResult(invocationId: invocationId) {
                    try await Api.tonConnect_connect(request: dappArg, message: tonConnectArgs)
                }
                
            case "restoreConnection":
                guard let invocationId = dict["invocationId"] as? String else {
                    return
                }
                guard let accountId = AccountStore.accountId, let origin = config.url.origin else { return }
                let isUrlEnsured = self.webView?.hasOnlySecureContent
                let dappArg = ApiDappRequest(url: origin, isUrlEnsured: isUrlEnsured, accountId: accountId, identifier: JSBRIDGE_IDENTIFIER, sseOptions: nil)

                executeAndInjectResult(invocationId: invocationId) {
                    try await Api.tonConnect_reconnect(request: dappArg)
                }

            case "disconnect":
                guard let invocationId = dict["invocationId"] as? String else {
                    return
                }
                guard let accountId = AccountStore.accountId, let origin = config.url.origin else { return }
                let isUrlEnsured = self.webView?.hasOnlySecureContent
                let dappArg = ApiDappRequest(url: origin, isUrlEnsured: isUrlEnsured, accountId: accountId, identifier: JSBRIDGE_IDENTIFIER, sseOptions: nil)

                executeAndInjectResult(invocationId: invocationId) {
                    try await Api.tonConnect_disconnect(request: dappArg)
                }

            case "send":
                guard let invocationId = dict["invocationId"] as? String else {
                    return
                }
                Task { [weak self] in
                    do {
                        let requests = try decodeWalletActionRequestsArray(args: dict["args"])
                        guard let accountId = AccountStore.account?.id, let origin = self?.config.url.origin else {
                            throw NilError()
                        }
                        
                        let request = try requests.first.orThrow() // only the first request is handled to match web version
                        
                        let isUrlEnsured = self?.webView?.hasOnlySecureContent
                        let dapp = ApiDappRequest(url: origin, isUrlEnsured: isUrlEnsured, accountId: accountId, identifier: JSBRIDGE_IDENTIFIER, sseOptions: nil)
                        
                        switch request.method {
                        case .sendTransaction:
                            let response = try await Api.tonConnect_sendTransaction(
                                request: dapp,
                                message: .init(method: request.method.rawValue, params: request.params, id: request.id )
                            )
                            try await self?.injectTonConnectResult(invocationId: invocationId, result: [
                                "id": response.id,
                                "result": response.result
                            ], error: nil)

                        case .signData:
                            let response = try await Api.tonConnect_signData(request: dapp, params: request.params)
                            try await self?.injectTonConnectResult(invocationId: invocationId, result: response, error: nil)
                            
                        case .disconnect:
                            throw TonConnectError(code: .methodNotSupported)
                        }
                        
                        
                    } catch let error as ApiSendTransactionRpcResponseError {
                        try? await self?.injectTonConnectResult(invocationId: invocationId, result: nil, error: TonConnectErrorCodes[error.error.code] ?? "Bad request")
                    } catch let error as TonConnectError {
                        try? await self?.injectTonConnectResult(invocationId: invocationId, result: nil, error: TonConnectErrorCodes[error.code.rawValue])
                    } catch {
                        try? await self?.injectTonConnectResult(invocationId: invocationId, result: nil, error: "Bad request")
                    }
                }
            case "window:open":
                if let args = dict["args"] as? [String: Any], let urlString = args["url"] as? String, let url = URL(string: urlString) {
                    if WalletContextManager.delegate?.handleDeeplink(url: url) ?? false {
                        return
                    }
                    AppActions.openInBrowser(url, title: nil, injectTonConnect: self.config.injectTonConnectBridge)
                }
            case "window:close":
                break
            default:
                assertionFailure("Unexpected invokeFunc: name=\(dict["name"] as Any)")
                break
            }
            break
        default:
            break
        }
    }
    
    private func executeAndInjectResult(invocationId: String, _ f: @escaping () async throws -> Any?) {
        Task {
            do {
                let result = try await f()
                try await self.injectTonConnectResult(invocationId: invocationId, result: result, error: nil)
            } catch {
                try? await self.injectTonConnectResult(invocationId: invocationId, result: nil, error: error)
            }
        }
    }
}
