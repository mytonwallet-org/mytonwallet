import UIKit
import UIComponents
import WalletCore
import WalletContext
import UIDapp

public class ExploreTabVC: WViewController {
    private let exploreVC = ExploreVC()
    private let searchView = ExploreSearch()
    private var navBarBlurView: UIView?
    private let navigationHeader = NavigationHeader2()
    private let largeExploreTitleLabel = UILabel()
    
    private struct State {
        var isLargeTitleVisible: Bool?
        var isNavigationTitleVisible: Bool?
        var isSearchActive: Bool = false
        var lastScrollOffset: CGFloat = 0
    }
    private var state = State()
    private var didCompleteInitialAppearance = false

    private static let deeplinkSchemes: Set<String> = ["ton", "tc", TONCONNECT_PROTOCOL_SCHEME, "wc", SELF_PROTOCOL_SCHEME]
    private static var deeplinkUniversalHosts: Set<String> {
        var hosts = SELF_UNIVERSAL_URL_HOSTS.union([
            "walletconnect.com",
            "pay.walletconnect.com",
            "pay.walletconnect.org",
        ])
        if let tonConnectUniversalHost = URL(string: TONCONNECT_UNIVERSAL_URL)?.host?.lowercased() {
            hosts.insert(tonConnectUniversalHost)
        }
        return hosts
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncNavChrome()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let isFirstAppearance = !didCompleteInitialAppearance
        didCompleteInitialAppearance = true
        if isFirstAppearance {
            state.lastScrollOffset = 0
        }
        syncNavChrome(animated: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }
    
    private func setupViews() {
        addChild(exploreVC)
        exploreVC.didMove(toParent: self)
        view.addStretchedToBounds(subview: exploreVC.view)

        navigationHeader.setTitle(lang("Explore"), fixedColor: true)
        navigationItem.titleView = navigationHeader
        navBarBlurView = addCustomNavigationBarBackground(color: .air.groupedBackground)
        
        exploreVC.onScrollOffsetChange = { [weak self] offset in
            guard let self else { return }
            state.lastScrollOffset = offset
            guard didCompleteInitialAppearance else { return }
            syncNavChrome()
        }

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
        searchView.viewModel.onSubmit = { [weak self] text in
            guard let self else { return }
            if !self.exploreVC.performTopMatchActionIfPresent() {
                self.onSubmit(text)
            }
        }
        searchView.viewModel.onActiveChange = { [weak self] isActive in
            guard let self else { return }
            state.isSearchActive = isActive
            exploreVC.searchActiveDidChange(isActive)
            applySearchModeChange()
            syncNavChrome()
        }

        exploreVC.onSubmitSearch = { [weak self] text in
            self?.onSubmit(text)
        }

        exploreVC.onGoogleSearch = { [weak self] text in
            self?.onGoogleSearch(text)
        }
        
        exploreVC.onInsertToSearchString = { [weak self] text in
            self?.searchView.viewModel.string = text
        }
        
        updateTheme()

        largeExploreTitleLabel.text = lang("Explore")
        largeExploreTitleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        largeExploreTitleLabel.textColor = .label
        largeExploreTitleLabel.accessibilityTraits = .header
        largeExploreTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(largeExploreTitleLabel)
        NSLayoutConstraint.activate([
            largeExploreTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            largeExploreTitleLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -8),
        ])

        syncNavChrome(animated: false)
    }

    private func applySearchModeChange() {
        state.lastScrollOffset = 0
        state.isLargeTitleVisible = false
        state.isNavigationTitleVisible = false
        UIView.performWithoutAnimation {
            navBarBlurView?.alpha = 0
            largeExploreTitleLabel.alpha = 0
            navigationHeader.visibilityAlpha = 0
        }
        applyNavChromeAccessibility(isLargeTitleVisible: false, isNavigationTitleVisible: false)
    }

    private func syncNavChrome(animated: Bool = true) {
        let isLargeTitleVisible: Bool
        let isNavigationTitleVisible: Bool

        if state.isSearchActive {
            isLargeTitleVisible = false
            isNavigationTitleVisible = false
            navBarBlurView?.alpha = 0
        } else {
            let progress = calculateNavigationBarProgressiveBlurProgress(state.lastScrollOffset)
            navBarBlurView?.alpha = progress
            if state.isLargeTitleVisible == true {
                isLargeTitleVisible = progress <= 0.7
            } else {
                isLargeTitleVisible = progress <= 0.1
            }
            isNavigationTitleVisible = true
        }

        applyNavChromeAccessibility(isLargeTitleVisible: isLargeTitleVisible, isNavigationTitleVisible: isNavigationTitleVisible)

        if state.isLargeTitleVisible != isLargeTitleVisible || state.isNavigationTitleVisible != isNavigationTitleVisible {
            state.isLargeTitleVisible = isLargeTitleVisible
            state.isNavigationTitleVisible = isNavigationTitleVisible
            applyNavChromeVisuals(
                isLargeTitleVisible: isLargeTitleVisible,
                isNavigationTitleVisible: isNavigationTitleVisible,
                animated: animated
            )
        }
    }

    private func applyNavChromeVisuals(
        isLargeTitleVisible: Bool,
        isNavigationTitleVisible: Bool,
        animated: Bool
    ) {
        let largeTitleAlpha: CGFloat = isLargeTitleVisible ? 1 : 0
        let compactTitleAlpha: CGFloat = isNavigationTitleVisible ? (isLargeTitleVisible ? 0 : 1) : 0
        let applyAlphas = {
            self.largeExploreTitleLabel.alpha = largeTitleAlpha
            self.navigationHeader.visibilityAlpha = compactTitleAlpha
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: applyAlphas)
        } else {
            UIView.performWithoutAnimation(applyAlphas)
        }
    }

    private func applyNavChromeAccessibility(
        isLargeTitleVisible: Bool,
        isNavigationTitleVisible: Bool
    ) {
        let showLargeTitle = isLargeTitleVisible && !state.isSearchActive
        let showCompactTitle = isNavigationTitleVisible && !isLargeTitleVisible && !state.isSearchActive

        largeExploreTitleLabel.isAccessibilityElement = showLargeTitle
        navigationHeader.accessibilityElementsHidden = !showCompactTitle
        if let titleLabel = navigationHeader.contentView as? UILabel {
            titleLabel.isAccessibilityElement = showCompactTitle
            titleLabel.accessibilityTraits = .header
        }
    }

    private func updateTheme() {
        view.backgroundColor = .air.background
    }
    
    public override func scrollToTop(animated: Bool) {
        exploreVC.scrollToTop(animated: animated)
    }
    
    private func onChange(_ text: String) {
        exploreVC.searchTextDidChange(text)
    }

    private static func deeplinkURLCandidate(from text: String) -> URL? {
        if isWalletConnectPayPaymentId(text) {
            return URL(string: text)
        }
        if let url = URL(string: text), url.scheme != nil {
            return url
        }
        guard text.contains(".") else {
            return nil
        }
        return URL(string: "https://" + text)
    }

    private static func isDeeplinkURLCandidate(_ url: URL) -> Bool {
        if isWalletConnectPayPaymentId(url.absoluteString) {
            return true
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        if let scheme = components.scheme?.lowercased(), deeplinkSchemes.contains(scheme) {
            return true
        }
        guard let host = components.host?.lowercased(), isDeeplinkUniversalHost(host) else {
            return false
        }
        if host == "walletconnect.com" {
            return components.path == "/wc"
        }
        return true
    }

    private static func isDeeplinkUniversalHost(_ host: String) -> Bool {
        if deeplinkUniversalHosts.contains(host) {
            return true
        }
        return host.hasSuffix(".pay.walletconnect.com") || host.hasSuffix(".pay.walletconnect.org")
    }

    private static func isWalletConnectPayPaymentId(_ text: String) -> Bool {
        text.hasPrefix("pay_")
    }

    private func clearSearchAfterSubmit() {
        view.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.searchView.viewModel.string = ""
            self.view.endEditing(true)
        }
    }
    
    private func onGoogleSearch(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmedText)]
        if let url = components.url {
            saveRecentSearch(trimmedText)
            AppActions.openInBrowser(url, title: nil, injectDappConnect: false, historyTag: exploreHistoryTag)
        }
    }
    
    private func onSubmit(_ text: String) {
        @MainActor func error() {
            Haptics.play(.error)
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if let openableUrl = SearchOpenableURL(trimmedText), case .deeplink = openableUrl.kind {
            let isHandled = WalletContextManager.delegate?.handleDeeplink(url: openableUrl.url, source: .exploreSearchBar) ?? false
            if isHandled {
                clearSearchAfterSubmit()
            } else {
                error()
            }
            return
        }

        if let deeplinkURL = Self.deeplinkURLCandidate(from: trimmedText),
           Self.isDeeplinkURLCandidate(deeplinkURL) {
            let isHandled = WalletContextManager.delegate?.handleDeeplink(url: deeplinkURL, source: .exploreSearchBar) ?? false
            if isHandled {
                clearSearchAfterSubmit()
            } else {
                error()
            }
            return
        }

        var urlString = trimmedText
        if !urlString.contains("://") && !urlString.contains(".") {
            onGoogleSearch(urlString)
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
            saveRecentSearch(trimmedText)
            AppActions.openInBrowser(url, title: nil, injectDappConnect: true, historyTag: exploreHistoryTag)
        }
        clearSearchAfterSubmit()
    }

    private func saveRecentSearch(_ text: String) {
        guard let accountId = AccountStore.accountId else { return }
        RecentSearchStore.shared.saveSearch(accountId: accountId, text: text, tag: exploreHistoryTag)
    }
}
