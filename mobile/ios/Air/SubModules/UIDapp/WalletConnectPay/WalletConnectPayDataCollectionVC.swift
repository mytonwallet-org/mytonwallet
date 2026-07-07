import UIKit
import WebKit
import UIComponents
import WalletCore
import WalletContext

private let walletConnectPayDataCollectionHandlerName = "payDataCollectionComplete"

private let walletConnectPayDataCollectionScript = """
(function() {
  if (window.__mytonwalletWalletConnectPayDataCollection) {
    return;
  }
  window.__mytonwalletWalletConnectPayDataCollection = true;

  function normalize(data) {
    if (typeof data === 'string') {
      try {
        return JSON.parse(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  window.addEventListener('message', function(event) {
    try {
      window.webkit.messageHandlers.payDataCollectionComplete.postMessage(JSON.stringify({
        origin: event.origin,
        data: normalize(event.data)
      }));
    } catch (_) {}
  });
})();
"""

@MainActor
final class WalletConnectPayDataCollectionVC: WViewController, UISheetPresentationControllerDelegate {
    private let update: ApiUpdate.WalletConnectPayDataCollection
    private let collectionURL: URL
    private let expectedOrigin: String?
    private var onComplete: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var onError: ((String) -> Void)?
    private var hasFinished = false
    private var didRemoveScriptMessageHandler = false

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: walletConnectPayDataCollectionHandlerName)
        userContentController.addUserScript(WKUserScript(
            source: walletConnectPayDataCollectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .air.background
        webView.scrollView.backgroundColor = .air.background
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        return webView
    }()

    private lazy var activityIndicator = {
        let indicator = WActivityIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    init?(
        update: ApiUpdate.WalletConnectPayDataCollection,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let url = URL(string: update.url) else {
            return nil
        }
        self.update = update
        self.collectionURL = url
        self.expectedOrigin = Self.origin(from: url)
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        activityIndicator.startAnimating(animated: false)
        webView.load(URLRequest(url: collectionURL))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            removeScriptMessageHandler()
        }
    }

    private func setupViews() {
        navigationItem.title = lang("Payment")
        addCloseNavigationItemIfNeeded()
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.cancel()
            })
        }
        view.backgroundColor = .air.background
        view.addSubview(webView)
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
    }

    private func complete() {
        guard !hasFinished else { return }
        hasFinished = true
        onComplete?()
        clearCallbacks()
        activityIndicator.startAnimating(animated: true)
        webView.isUserInteractionEnabled = false
    }

    private func fail(_ error: String) {
        guard !hasFinished else { return }
        hasFinished = true
        onError?(error)
        clearCallbacks()
    }

    private func cancel() {
        guard !hasFinished else { return }
        hasFinished = true
        onCancel?()
        clearCallbacks()
    }

    private func clearCallbacks() {
        onComplete = nil
        onCancel = nil
        onError = nil
    }

    private func removeScriptMessageHandler() {
        guard !didRemoveScriptMessageHandler else { return }
        didRemoveScriptMessageHandler = true
        webView.configuration.userContentController.removeScriptMessageHandler(forName: walletConnectPayDataCollectionHandlerName)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        cancel()
    }

    private static func origin(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }
        var origin = "\(scheme)://\(host)"
        if let port = components.port {
            origin += ":\(port)"
        }
        return origin
    }

    private static func origin(from securityOrigin: WKSecurityOrigin) -> String? {
        guard !securityOrigin.protocol.isEmpty,
              !securityOrigin.host.isEmpty else {
            return nil
        }
        var origin = "\(securityOrigin.protocol)://\(securityOrigin.host)"
        if securityOrigin.port != 0 {
            origin += ":\(securityOrigin.port)"
        }
        return origin
    }

    private func parseMessageBody(_ rawBody: Any) -> (origin: String?, data: [String: Any])? {
        var body = rawBody
        if let string = body as? String {
            guard let data = string.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            body = parsed
        }

        guard let bodyDict = body as? [String: Any] else {
            return nil
        }

        if let nested = bodyDict["data"] {
            var nestedBody = nested
            if let string = nestedBody as? String,
               let data = string.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                nestedBody = parsed
            }
            guard let dataDict = nestedBody as? [String: Any] else {
                return nil
            }
            return (bodyDict["origin"] as? String, dataDict)
        }

        return (nil, bodyDict)
    }

    private func isTrusted(message: WKScriptMessage, forwardedOrigin: String?) -> Bool {
        guard let expectedOrigin else {
            return true
        }
        let origin = forwardedOrigin ?? Self.origin(from: message.frameInfo.securityOrigin)
        return origin == expectedOrigin
    }

    private func openExternalURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }
        UIApplication.shared.open(url, options: [:])
    }
}

extension WalletConnectPayDataCollectionVC: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = parseMessageBody(message.body),
              isTrusted(message: message, forwardedOrigin: parsed.origin),
              let type = parsed.data["type"] as? String else {
            return
        }

        switch type {
        case "IC_COMPLETE":
            if parsed.data["success"] as? Bool == false {
                fail(parsed.data["error"] as? String ?? lang("Unknown error"))
            } else {
                complete()
            }
        case "IC_ERROR":
            fail(parsed.data["error"] as? String ?? lang("Unknown error"))
        default:
            break
        }
    }
}

extension WalletConnectPayDataCollectionVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating(animated: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        fail(error.localizedDescription)
    }
}

extension WalletConnectPayDataCollectionVC: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            openExternalURL(url)
        }
        return nil
    }
}
