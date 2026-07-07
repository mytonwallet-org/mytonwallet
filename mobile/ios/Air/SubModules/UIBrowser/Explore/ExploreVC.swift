import Combine
import SwiftUI
import UIComponents
import UIInAppBrowser
import WalletContext
import WalletCore

let exploreHistoryTag = "explore"

public final class ExploreVC: WViewController {
    let exploreVM: ExploreVM = .init()
    var onSelectAny: () -> () = {}
    var onSubmitSearch: (String) -> () = { _ in }
    var onGoogleSearch: (String) -> () = { _ in }
    var onInsertToSearchString: (String) -> () = { _ in }
    var onScrollOffsetChange: ((CGFloat) -> Void)?

    private let viewOutput = ViewOutput()
    private let externalEvents = ExternalEvents()
    private let observedViewState = ObservedViewState()

    private var trimmedSearchString: String = ""
    private var isSearchActive: Bool = false

    private var searchCoordinator: ExploreSearchCoordinator?
    private var currentSearchResult: ComposedSearchResult?
    private var lastSearchQuery: SearchQuery?

    private var cancelBag = Set<AnyCancellable>()

    public init() {
        super.init(nibName: nil, bundle: nil)
        exploreVM.delegate = self

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self = self else { return }
            if !isViewLoaded {
                exploreVM.loadExploreSites()             }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialSetup()
        bind()

        exploreVM.refresh()
    }

    public override func scrollToTop(animated: Bool) {
        observedViewState.scrollToTop(animated: animated)
    }

    private func initialSetup() {
        let rootView = ScreenView(viewState: observedViewState, viewOutput: viewOutput)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false

        view.addStretchedToBounds(subview: hostingController.view)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
    }

    private func bind() {
        setupSearchCoordinator()
        bindViewOutput()

        BrowserHistoryStore.shared.onLoaded
            .sink(withUnretained: self) { uSelf, _ in uSelf.updateViewState(forceSearch: true) }
            .store(in: &cancelBag)
        RecentSearchStore.shared.onLoaded
            .sink(withUnretained: self) { uSelf, _ in uSelf.updateViewState(forceSearch: true) }
            .store(in: &cancelBag)

        externalEvents.searchStringDidChange
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink(withUnretained: self) { uSelf, searchText in
                uSelf.trimmedSearchString = searchText
                uSelf.updateViewState()
            }.store(in: &cancelBag)

        externalEvents.searchActiveDidChange
            .removeDuplicates()
            .sink(withUnretained: self) { uSelf, isActive in
                uSelf.isSearchActive = isActive
                uSelf.updateViewState(forceSearch: true, animated: false)
                uSelf.observedViewState.scrollToTop(animated: false)
            }.store(in: &cancelBag)
    }

    private func bindViewOutput() {
        cancelBag.formUnion([
            viewOutput.connectedDappDidTap.sink { [exploreVM] connectedDappURL in
                if let connected = exploreVM.connectedDapps[connectedDappURL], let url = URL(string: connected.url) {
                    AppActions.openInBrowser(url, title: connected.name, injectDappConnect: true, historyTag: exploreHistoryTag)
                } else {
                    Log.shared.error("Data is inconsistent for connectedDappURL \(connectedDappURL)")
                }
            },

            viewOutput.connectedDappSettingsDidTap.sink {
                AppActions.showConnectedDapps(push: false)
            },

            viewOutput.trendingDappDidTap
                .merge(with: viewOutput.dappFromFolderDidTap)
                .sink(withUnretained: self) { uSelf, apiSite in
                    uSelf.commitSelection()
                    
                    if uSelf.exploreVM.exploreSites[apiSite.url] == nil {
                        Log.shared.error("inconsistency between UI and data ")
                    }
                    guard let url = URL(string: apiSite.url) else {
                        return Log.shared.error("URL from string failed: \(apiSite.url)")
                    }

                    if apiSite.shouldOpenExternally {
                        UIApplication.shared.open(url)
                    } else {
                        AppActions.openInBrowser(url, title: apiSite.name, injectDappConnect: true, historyTag: exploreHistoryTag)
                    }
                },

            viewOutput.dappCategoryDidTap.sink(withUnretained: self) { uSelf, categoryId in
                let exploreVC = ExploreCategoryVC(exploreVM: uSelf.exploreVM, categoryId: categoryId)
                uSelf.navigationController?.pushViewController(exploreVC, animated: true)
            },

            viewOutput.scrollOffsetDidChange
                .sink { [weak self] offset in self?.onScrollOffsetChange?(offset) },
        ])
    }

    private func updateViewState(forceSearch: Bool = false, animated: Bool = true) {
        let shouldRestrictSites = ConfigStore.shared.shouldRestrictSites
        
        if isSearchActive {
            let query = SearchQuery(text: trimmedSearchString, shouldRestrictSites: shouldRestrictSites)
            if forceSearch || query != lastSearchQuery {
                lastSearchQuery = query
                searchCoordinator?.search(query)
            }
            return
        }
        
        searchCoordinator?.cancel()
        lastSearchQuery = nil
        currentSearchResult = nil
        
        let sections = Self.makeBrowsingSections(
            connectedDapps: Array(exploreVM.connectedDapps.values.apply(Array.init)),
            featuredTitle: exploreVM.featuredTitle,
            exploreSites: exploreVM.exploreSites.values.apply(Array.init),
            siteCategories: exploreVM.exploreCategories.values.apply(Array.init),
            shouldRestrictSites: shouldRestrictSites,
            isLockdownModeEnabled: WalletCoreData.isLockdownModeEnabled
        )
        observedViewState.updateBrowsing(sections: sections, animated: animated)
    }
    
    private func commitSelection() {
        view.window?.endEditing(true)
        onSelectAny()
    }
    
    private func setupSearchCoordinator() {
        let actions = ExploreSearchActions(
            openSite: { [weak self] site in
                self?.openSearchURL(site.url, title: site.name, externally: site.shouldOpenExternally)
            },
            openDapp: { [weak self] dapp in
                self?.openSearchURL(dapp.url, title: dapp.name)
            },
            openHistory: { [weak self] item in
                self?.openSearchURL(item.url, title: item.title)
            },
            openWallet: { [weak self] account in
                self?.commitSelection()
                
                Task {
                    do {
                        _ = try await AccountStore.activateAccount(accountId: account.id)
                        AppActions.showHome(popToRoot: true)
                    } catch {
                        AppActions.showError(error: error)
                    }
                }
            },
            submitSearch: { [weak self] text in
                self?.onSubmitSearch(text)
            },
            openUrl: { [weak self] openableUrl in
                switch openableUrl.kind {
                case .deeplink:
                    let isHandled = WalletContextManager.delegate?.handleDeeplink(url: openableUrl.url, source: .exploreSearchBar)
                    if isHandled != true {
                        Haptics.play(.error)
                        return
                    }
                case .regular:
                    AppActions.openInBrowser(openableUrl.url, title: nil, injectDappConnect: true, historyTag: exploreHistoryTag)
                }
                self?.commitSelection()
            },
            openExternalURL: { [weak self] url, appUrl in
                self?.openSearchURL(url, appUrlString: appUrl, title: nil, externally: true)
            },
            showTemporaryViewAccount: { [weak self] network, addressOrDomainByChain in
                self?.commitSelection()
                AppActions.showTemporaryViewAccount(network: network, addressOrDomainByChain: addressOrDomainByChain)
            },
            insertToSearchString: { [weak self] text in
                self?.onInsertToSearchString(text)
            },
            searchGoogle: { [weak self] text in
                self?.onGoogleSearch(text)
            },
            clearRecentSearches: { [weak self] tag in
                self?.clearRecentSearches(tag: tag)
            }
        )

        searchCoordinator = ExploreSearchCoordinator(
            providers: [
                SuggestedSearchProvider(actions: actions),
                WalletSearchProvider(actions: actions),
                SitesAndDappsSearchProvider(exploreVM: exploreVM, actions: actions),
                HistorySearchProvider(tag: exploreHistoryTag, actions: actions),
            ],
            actions: actions,
            recentSearchTag: exploreHistoryTag
        )
            
        searchCoordinator?.onUpdate = { [weak self] result in
            self?.currentSearchResult = result
            self?.observedViewState.updateSearch(result)
        }
    }

    func performTopMatchActionIfPresent() -> Bool {
        guard isSearchActive, let topMatch = currentSearchResult?.topMatch else { return false }
        topMatch.performDefaultAction()
        return true
    }

    private func clearRecentSearches(tag: String) {
        guard let accountId = AccountStore.accountId else { return }
        RecentSearchStore.shared.clear(accountId: accountId, tag: tag)
        updateViewState(forceSearch: true)
    }

    private func openSearchURL(_ urlString: String, appUrlString: String? = nil, title: String?, externally: Bool = false) {
        commitSelection()
        
        // trying to open installed app, if requested and available
        if let appUrlString, let appUrl = URL(string: appUrlString), UIApplication.shared.canOpenURL(appUrl) {
            UIApplication.shared.open(appUrl)
            return 
        }
        
        guard let url = URL(string: urlString) else {
            return Log.shared.error("URL from string failed: \(urlString)")
        }
        if externally {
            UIApplication.shared.open(url)
        } else {
            AppActions.openInBrowser(url, title: title, injectDappConnect: true, historyTag: exploreHistoryTag)
        }
    }
}

// MARK: - External Events

extension ExploreVC {
    func searchTextDidChange(_ searchString: String) { externalEvents.searchStringDidChange.send(searchString) }
    func searchActiveDidChange(_ isActive: Bool) { externalEvents.searchActiveDidChange.send(isActive) }
}

extension ExploreVC: ExploreVMDelegate {
    func didUpdateViewModelData() { updateViewState() }
}

extension ExploreVC {
    /// Events from parent / child screens
    private struct ExternalEvents {
        let searchStringDidChange = PassthroughSubject<String, Never>()
        let searchActiveDidChange = PassthroughSubject<Bool, Never>()
    }
}
