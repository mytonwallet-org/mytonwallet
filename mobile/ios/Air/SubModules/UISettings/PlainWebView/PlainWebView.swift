import Foundation
import UIKit
import UIComponents
import WalletContext
import WebKit

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

        webView = WKWebView()
        webView.accessibilityIdentifier = "plain_web_view"
        view.addStretchedToSafeArea(subview: webView,
                                    top: \.topAnchor,
                                    bottom: \.bottomAnchor)
        webView.isOpaque = false // prevents flashing white during load
        if #available(iOS 26, *) {
            webView.scrollView.topEdgeEffect.style = .hard
        }

        updateTheme()
        
        webView.load(URLRequest(url: url))
    }
    
    private func updateTheme() {
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
