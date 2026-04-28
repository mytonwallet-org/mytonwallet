import UIKit
import UIComponents
import WalletCore
import WalletContext
import UIDapp

public class ExploreTabVC: WViewController {
    private let exploreVC = ExploreVC()
    private let searchView = ExploreSearch()

    private static let deeplinkSchemes: Set<String> = ["ton", "tc", TONCONNECT_PROTOCOL_SCHEME, "wc", SELF_PROTOCOL_SCHEME]
    private static var deeplinkUniversalHosts: Set<String> {
        var hosts = SELF_UNIVERSAL_URL_HOSTS.union(["walletconnect.com"])
        if let tonConnectUniversalHost = URL(string: TONCONNECT_UNIVERSAL_URL)?.host?.lowercased() {
            hosts.insert(tonConnectUniversalHost)
        }
        return hosts
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    func setupViews() {
        view.backgroundColor = .air.background
      
        // Improvement: move navigationItem setup of Explore screen to ExploreVC | merge with ExploreVC to 1 class
        navigationItem.title = lang("Explore")
        if #available(iOS 26, *) {
            navigationItem.largeTitleDisplayMode = .inline
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = 4
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.largeTitleTextAttributes = [
                .paragraphStyle: p,
            ]
            navigationItem.standardAppearance = appearance
            navigationItem.scrollEdgeAppearance = appearance
        } else if #available(iOS 17, *) {
            navigationItem.largeTitleDisplayMode = .inline
            navigationController?.navigationBar.prefersLargeTitles = true
        } else {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .always
        }
        
        addChild(exploreVC)
        exploreVC.didMove(toParent: self)
        view.addStretchedToBounds(subview: exploreVC.view)

        exploreVC.onSelectAny = { [weak self] in
            guard let self else { return }
            self.view.endEditing(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.searchView.viewModel.string = ""
                self.view.endEditing(true)
            }
        }

        view.addSubview(searchView)
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.keyboardDismissPadding = 40
        }
        NSLayoutConstraint.activate([
            searchView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            searchView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        searchView.viewModel.onChange = { [weak self] in self?.onChange($0) }
        searchView.viewModel.onSubmit = { [weak self] in self?.onSubmit($0) }
        
        updateTheme()
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.background
    }
    
    public override func scrollToTop(animated: Bool) {
        exploreVC.scrollToTop(animated: animated)
    }
    
    func onChange(_ text: String) {
        exploreVC.searchTextDidChange(text)
    }

    private static func deeplinkURLCandidate(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil {
            return url
        }
        guard text.contains(".") else {
            return nil
        }
        return URL(string: "https://" + text)
    }

    private static func isDeeplinkURLCandidate(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        if let scheme = components.scheme?.lowercased(), deeplinkSchemes.contains(scheme) {
            return true
        }
        guard let host = components.host?.lowercased(), deeplinkUniversalHosts.contains(host) else {
            return false
        }
        if host == "walletconnect.com" {
            return components.path == "/wc"
        }
        return true
    }

    private func clearSearchAfterSubmit() {
        view.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.searchView.viewModel.string = ""
            self.view.endEditing(true)
        }
    }
    
    func onSubmit(_ text: String) {
        @MainActor func error() {
            Haptics.play(.error)
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let deeplinkURL = Self.deeplinkURLCandidate(from: trimmedText) {
            let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: deeplinkURL, source: .exploreSearchBar) ?? false
            if deeplinkHandled {
                clearSearchAfterSubmit()
                return
            }
            if Self.isDeeplinkURLCandidate(deeplinkURL) {
                error()
                return
            }
        }

        var urlString = trimmedText
        if !urlString.contains("://") && !urlString.contains(".") {
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: urlString)]
            if let url = components.url {
                AppActions.openInBrowser(url)
            }
        } else {
            if !urlString.contains("://") {
                urlString = "https://" + urlString
            }
            guard let _url = URL(string: urlString), var components = URLComponents(url: _url, resolvingAgainstBaseURL: false) else {
                error()
                return
            }
            if components.scheme == nil {
                components.scheme = "https"
            }
            guard let url = components.url, url.host(percentEncoded: false)?.contains(".") == true else {
                error()
                return
            }
            AppActions.openInBrowser(url)
        }
        clearSearchAfterSubmit()
    }
}
