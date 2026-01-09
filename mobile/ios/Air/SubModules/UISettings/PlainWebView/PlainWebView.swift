import Foundation
import UIKit
import UIComponents
import WalletContext
import WebKit

private let CSS = """
body {
    background-color: #fff;
}

.tl_article .tl_article_content,
.tl_article .tl_article_content .ql-editor *,
.tl_article h1,
.tl_article h2 {
    color: #000;
}

.tl_article_header address,
.tl_article_header address a {
    color: #8E8E93;
}

@media (prefers-color-scheme: dark) {
    body {
        background-color: #0E0E0F;
    }

    .tl_article .tl_article_content,
    .tl_article .tl_article_content .ql-editor *,
    .tl_article h1,
    .tl_article h2 {
        color: #fff;
    }

    .tl_article_header address,
    .tl_article_header address a {
        color: #8E8E93;
    }
}
"""
private let INJECT_SCRIPT = """
var style = document.createElement('style');
style.innerHTML = `\(CSS)`;
document.head.appendChild(style);
"""

private let _backgroundColor = UIColor(light: "#fff", dark: "#0E0E0F")

@MainActor
final class PlainWebView: WViewController {
    
    private let url: URL
    
    private var webView: WKWebView!
    
    init(title: String, url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let injectCss = WKUserScript(source: INJECT_SCRIPT, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let contentController = WKUserContentController()
        contentController.addUserScript(injectCss)
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView.isOpaque = false // prevents flashing white during load
        if #available(iOS 26, *) {
            webView.scrollView.topEdgeEffect.style = .hard
        }
        
        bringNavigationBarToFront()
        
        updateTheme()
        
        webView.load(URLRequest(url: url))
    }
    
    override func updateTheme() {
        view.backgroundColor = _backgroundColor
        webView.backgroundColor = _backgroundColor
        webView.scrollView.backgroundColor = _backgroundColor
    }
}


extension UINavigationController {
    func pushPlainWebView(title: String, url: URL) {
        let vc = PlainWebView(title: title, url: url)
        pushViewController(vc, animated: true)
    }
}
