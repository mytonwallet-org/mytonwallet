import UIKit
import UIComponents
import WalletCore
@preconcurrency import WalletContext
import UIDapp

public class ExploreTabVC: WViewController {
    private let exploreVC = ExploreVC()
    
    private var newSearch: ExploreSearch?
    
    private var searchBarContainer: UIView?
    private var searchBar: WSearchBar?
    private var searchBarContainerBottomConstraint: NSLayoutConstraint?

    private static let deeplinkSchemes: Set<String> = ["ton", "tc", "mytonwallet-tc", "wc", "mtw"]
    private static let deeplinkUniversalHosts: Set<String> = ["connect.mytonwallet.org", "walletconnect.com", "go.mytonwallet.org", "my.tt"]
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WKeyboardObserver.observeKeyboard(delegate: self)
    }
    
    func setupViews() {
        view.backgroundColor = WTheme.background
      
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
            self.searchBar?.resignFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.searchBar?.text = nil
                self.searchBar?.setCenteredPlaceholder()
                self.searchBar?.onChange?("")
                self.view.endEditing(true)
                self.searchBar?.resignFirstResponder()
                self.newSearch?.viewModel.string = ""
                self.view.endEditing(true)
            }
        }
        
        // MARK: search bar
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let newSearch = ExploreSearch()
            self.newSearch = newSearch
            view.addSubview(newSearch)
            view.keyboardLayoutGuide.keyboardDismissPadding = 40
            NSLayoutConstraint.activate([
                newSearch.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
                newSearch.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newSearch.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            newSearch.viewModel.onChange = { [weak self] in self?.onChange($0) }
            newSearch.viewModel.onSubmit = { [weak self] in self?.onSubmit($0) }
        } else {
            let searchBarContainer = UIView()
            self.searchBarContainer = searchBarContainer
            searchBarContainer.translatesAutoresizingMaskIntoConstraints = false
            searchBarContainer.backgroundColor = .clear
            view.addSubview(searchBarContainer)
            let searchBarContainerBottomConstraint = searchBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -view.safeAreaInsets.bottom)
            self.searchBarContainerBottomConstraint = searchBarContainerBottomConstraint
            NSLayoutConstraint.activate([
                searchBarContainerBottomConstraint,
                searchBarContainer.leftAnchor.constraint(equalTo: view.leftAnchor),
                searchBarContainer.rightAnchor.constraint(equalTo: view.rightAnchor),
                searchBarContainer.heightAnchor.constraint(equalToConstant: 67)
            ])
            
            let searchBarBlurView = Self.makeBlurView()
            view.addSubview(searchBarBlurView)
            searchBarBlurView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                searchBarBlurView.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
                searchBarBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                searchBarBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchBarBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            let separatorView = UIView()
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            separatorView.backgroundColor = WTheme.border
            searchBarContainer.addSubview(separatorView)
            NSLayoutConstraint.activate([
                separatorView.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
                separatorView.leftAnchor.constraint(equalTo: searchBarContainer.leftAnchor),
                separatorView.rightAnchor.constraint(equalTo: searchBarContainer.rightAnchor),
                separatorView.heightAnchor.constraint(equalToConstant: 0.33)
            ])
            
            let searchBar = WSearchBar()
            self.searchBar = searchBar
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            searchBar.placeholder = lang("Search or enter address")
            searchBar.onChange = { [weak self] in self?.onChange($0) }
            searchBar.onSubmit = { [weak self] in self?.onSubmit($0) }
            searchBarContainer.addSubview(searchBar)
            NSLayoutConstraint.activate([
                searchBar.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor, constant: -1),
                searchBar.leftAnchor.constraint(equalTo: searchBarContainer.leftAnchor, constant: 16),
                searchBar.rightAnchor.constraint(equalTo: searchBarContainer.rightAnchor, constant: -16)
            ])
            view.bringSubviewToFront(searchBarContainer)
        }
        
        updateTheme()
    }
    
    private static func makeBlurView() -> WBlurView {
        let color = UIColor {
            $0.userInterfaceStyle != .dark ? WColors.blurBackground : WColors.blurBackground.withAlphaComponent(0.85)
        }
        return WBlurView(background: color)
    }
    
    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        
        if searchBar?.text?.isEmpty != false {
            DispatchQueue.main.async {
                self.searchBar?.setCenteredPlaceholder()
            }
        }
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.background
    }
    
    public override func scrollToTop(animated: Bool) {
        exploreVC.scrollToTop(animated: animated)
    }
    
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if !IOS_26_MODE_ENABLED {
            UIView.animate(withDuration: 0.3) { [self] in
                searchBarContainerBottomConstraint?.constant = -view.safeAreaInsets.bottom
                view.layoutIfNeeded()
            }
        }
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
            self.searchBar?.text = nil
            self.searchBar?.setCenteredPlaceholder()
            self.searchBar?.onChange?("")
            self.view.endEditing(true)
            self.searchBar?.resignFirstResponder()
            self.newSearch?.viewModel.string = ""
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


extension ExploreTabVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: 0.25) { [self] in
            if let window = view.window {
                searchBarContainerBottomConstraint?.constant = -info.height + (window.bounds.height - view.frame.height) // keyboard height is in windows coordinates
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: 0.25) { [self] in
            searchBarContainerBottomConstraint?.constant = -view.safeAreaInsets.bottom
            view.layoutIfNeeded()
        }
    }
}
