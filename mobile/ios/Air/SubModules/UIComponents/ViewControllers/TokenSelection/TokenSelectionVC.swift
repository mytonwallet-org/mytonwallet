//
//  TokenSelectionVC.swift
//  UIComponents
//
//  Created by Sina on 5/10/24.
//

import Foundation
import UIKit
import WalletCore
import WalletContext

@MainActor public protocol TokenSelectionVCDelegate: AnyObject {
    func didSelect(token: MTokenBalance)
    func didSelect(token: ApiToken)
}

public class TokenSelectionVC: WViewController {
    public enum MyAssetsDisplayMode {
        case `default`
        case swap
    }
    
    // MARK: - Diffable Data Source Types
    
    private enum Section: Hashable {
        case myAssets
        case popular
        case allAssets

        var title: String {
            switch self {
            case .myAssets:
                lang("My")
            case .popular:
                lang("Popular")
            case .allAssets:
                lang("A ~ Z")
            }
        }
    }
    
    private enum Item: Hashable {
        case walletToken(MTokenBalance)
        case apiToken(ApiToken, Section)
        
        static func == (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
            case (.walletToken(let l), .walletToken(let r)):
                return l.tokenSlug == r.tokenSlug
            case (.apiToken(let lToken, let lSection), .apiToken(let rToken, let rSection)):
                return lToken.slug == rToken.slug && lSection == rSection
            default:
                return false
            }
        }
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .walletToken(let token):
                hasher.combine("wallet")
                hasher.combine(token.tokenSlug)
            case .apiToken(let token, let section):
                hasher.combine("api")
                hasher.combine(token.slug)
                hasher.combine(section)
            }
        }
    }
    
    // MARK: - Properties
    
    private weak var delegate: TokenSelectionVCDelegate?
    private var forceAvailable: String?
    private let extraWalletTokenSlugs: [String]
    private var otherSymbolOrMinterAddress: String?
    private let showMyAssets: Bool
    private let myAssetsDisplayMode: MyAssetsDisplayMode
    private let isModal: Bool
    private let onlySupportedChains: Bool
    private let chainFilter: ApiChain?
    private var availablePairs: [MPair]?
    private let log = Log()
    private var walletTokens = [MTokenBalance]()
    private var showingWalletTokens = [MTokenBalance]()
    private var showingPopularTokens = [ApiToken]()
    private var showingAllAssets = [ApiToken]()
    private var keyword = String()
    private var searchController: UISearchController?

    private var secondaryAmountMode: TokenCell.SecondaryAmountMode {
        myAssetsDisplayMode == .swap ? .tokenPrice : .balanceValue
    }
    
    private var shouldSaveSelectedApiToken: Bool {
        myAssetsDisplayMode != .swap
    }

    @AccountContext(source: .current) private var account: MAccount
    
    private var collectionView: UICollectionView!
    private var activityIndicatorView: WActivityIndicator!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    // MARK: - Init
    
    public init(forceAvailable: String? = nil,
                extraWalletTokenSlugs: [String] = [],
                otherSymbolOrMinterAddress: String? = nil,
                showMyAssets: Bool = true,
                myAssetsDisplayMode: MyAssetsDisplayMode = .default,
                title: String,
                delegate: TokenSelectionVCDelegate?,
                isModal: Bool,
                onlySupportedChains: Bool,
                chainFilter: ApiChain? = nil) {
        self.forceAvailable = forceAvailable
        self.extraWalletTokenSlugs = extraWalletTokenSlugs
        self.otherSymbolOrMinterAddress = otherSymbolOrMinterAddress
        self.showMyAssets = showMyAssets
        self.myAssetsDisplayMode = myAssetsDisplayMode
        self.delegate = delegate
        self.isModal = isModal
        self.onlySupportedChains = onlySupportedChains
        self.chainFilter = chainFilter
        super.init(nibName: nil, bundle: nil)
        self.title = title
        updateWalletTokens()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        configureDataSource()
        WalletCoreData.add(eventObserver: self)
        
        if onlySupportedChains {
            filterTokens()
        } else {
            Task { [weak self] in
                do {
                    _ = try await TokenStore.updateSwapAssets()
                    self?.filterTokens()
                } catch {}
            }
        }
        
        if let otherSymbolOrMinterAddress {
            activityIndicatorView.startAnimating(animated: true)
            collectionView.alpha = 0
            Task {
                do {
                    let pairs = try await Api.swapGetPairs(symbolOrMinter: otherSymbolOrMinterAddress)
                    availablePairs = pairs
                } catch {
                    log.error("failed to load swap pairs \(error, .public)")
                }
                activityIndicatorView.stopAnimating(animated: true)
                applySnapshot()
                UIView.animate(withDuration: 0.2) { [weak self] in
                    guard let self else { return }
                    collectionView.alpha = 1
                    activityIndicatorView.alpha = 0
                } completion: { [weak self] _ in
                    guard let self else { return }
                    activityIndicatorView.stopAnimating(animated: true)
                }
            }
        }
    }
    
    // MARK: - Setup
    
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.showsSeparators = true
            listConfig.headerMode = .supplementary

            let separatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 62, bottom: 0, trailing: IOS_26_MODE_ENABLED ? 12 : 0)
            var separatorConfig = UIListSeparatorConfiguration(listAppearance: .plain)
            separatorConfig.topSeparatorInsets = separatorInsets
            separatorConfig.bottomSeparatorInsets = separatorInsets
            listConfig.separatorConfiguration = separatorConfig

            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.contentInsets.bottom = 12
            return section
        }
    }
    
    private func setupViews() {
        if isModal {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })
        }
        
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.autocorrectionType = .no
        sc.searchBar.spellCheckingType = .no
        sc.searchBar.placeholder = lang("Search")
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            if !isModal {
                navigationItem.preferredSearchBarPlacement = .integratedButton
            }
        }
        definesPresentationContext = true
        self.searchController = sc
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delaysContentTouches = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        view.addStretchedToSafeArea(subview: collectionView,
                                    top: \.topAnchor,
                                    bottom: \.bottomAnchor)
        
        activityIndicatorView = WActivityIndicator()
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicatorView)
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])

        updateTheme()
    }
    
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<TokenCell, Item> { [weak self] cell, indexPath, item in
            guard let self else { return }
            self.configure(cell: cell, for: item, at: indexPath)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self else { return }
            let sectionIdentifiers = self.dataSource.snapshot().sectionIdentifiers
            guard indexPath.section < sectionIdentifiers.count else { return }
            var content = UIListContentConfiguration.plainHeader()
            content.text = sectionIdentifiers[indexPath.section].title
            content.directionalLayoutMargins.leading += 54
            headerView.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }
    
    private func configure(cell: TokenCell, for item: Item, at indexPath: IndexPath) {
        switch item {
        case .walletToken(let token):
            let isAvailable = isTokenAvailable(slug: token.tokenSlug)
            cell.configure(
                with: token,
                isAvailable: isAvailable,
                secondaryAmountMode: secondaryAmountMode
            ) { [weak self] in
                guard let self, isTokenAvailable(slug: token.tokenSlug) else { return }
                delegate?.didSelect(token: token)
                navigationController?.popViewController(animated: true)
            }
            
        case .apiToken(let token, _):
            let isAvailable = isTokenAvailable(slug: token.slug)
            let tokenSlug = token.slug
            cell.configure(
                with: token,
                balance: $account.balances[token.slug] ?? 0,
                isAvailable: isAvailable,
                secondaryAmountMode: secondaryAmountMode
            ) { [weak self] in
                guard let self, isTokenAvailable(slug: token.slug) else { return }
                if shouldSaveSelectedApiToken {
                    AssetsAndActivityDataStore.update(accountId: account.id, update: { settings in
                        settings.saveImportedToken(slug: tokenSlug)
                    })
                }
                delegate?.didSelect(token: token)
                navigationController?.popViewController(animated: true)
            }
        }
    }
    
    private func isTokenAvailable(slug: String) -> Bool {
        if slug == forceAvailable {
            return true
        }
        if otherSymbolOrMinterAddress == nil {
            return true
        }
        return availablePairs?.contains { $0.slug == slug } ?? false
    }
    
    private func updateTheme() {
        collectionView?.backgroundColor = .air.pickerBackground
    }
        
    @objc private func hideKeyboard() {
        view.endEditing(false)
    }
        
    private func updateWalletTokens() {
        walletTokens = showMyAssets ? $account.walletTokens ?? [] : []
        guard showMyAssets else { return }
        for slug in extraWalletTokenSlugs where walletTokens.contains(where: { $0.tokenSlug == slug }) == false {
            guard TokenStore.getToken(slug: slug) != nil else { continue }
            walletTokens.append(MTokenBalance(tokenSlug: slug, balance: 0, isStaking: false))
        }
    }
    
    private func filterTokens() {
        let keyword = self.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shouldIncludeChain = { [account, onlySupportedChains, chainFilter] (chain: ApiChain) -> Bool in
            if let chainFilter, chain != chainFilter {
                return false
            }
            return !onlySupportedChains || account.supports(chain: chain)
        }
        
        showingWalletTokens = walletTokens.filter { token in
            guard let apiToken = TokenStore.tokens[token.tokenSlug] else { return false }
            guard shouldIncludeChain(apiToken.chain) && apiToken.matchesSearch(keyword) else { return false }
            if myAssetsDisplayMode == .swap, (apiToken.price ?? 0) == 0 {
                return false
            }
            return true
        }
        
        if myAssetsDisplayMode == .swap {
            showingWalletTokens.sort { lhs, rhs in
                let lhsAmount = lhs.toBaseCurrency ?? 0
                let rhsAmount = rhs.toBaseCurrency ?? 0
                if lhsAmount != rhsAmount {
                    return lhsAmount > rhsAmount
                }
                let lhsName = lhs.token?.name ?? lhs.tokenSlug
                let rhsName = rhs.token?.name ?? rhs.tokenSlug
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
        }

        let sourceAssets: [ApiToken] = if onlySupportedChains {
            TokenStore.tokens.values.map { $0 }
        } else {
            TokenStore.swapAssets ?? []
        }
        let filteredAssets = sourceAssets
            .filter { shouldIncludeChain($0.chain) && $0.matchesSearch(keyword) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        showingPopularTokens = filteredAssets.filter { $0.isPopular == true }
        showingAllAssets = filteredAssets
        
        applySnapshot()
    }
    
    private func applySnapshot() {
        // Don't show anything if waiting for pairs to load
        guard otherSymbolOrMinterAddress == nil || availablePairs != nil else {
            let snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            dataSource?.apply(snapshot, animatingDifferences: false)
            return
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        if !showingWalletTokens.isEmpty {
            snapshot.appendSections([.myAssets])
            snapshot.appendItems(showingWalletTokens.map { .walletToken($0) }, toSection: .myAssets)
        }
        
        if !showingPopularTokens.isEmpty {
            snapshot.appendSections([.popular])
            snapshot.appendItems(showingPopularTokens.map { .apiToken($0, .popular) }, toSection: .popular)
        }
        
        if !showingAllAssets.isEmpty {
            snapshot.appendSections([.allAssets])
            snapshot.appendItems(showingAllAssets.map { .apiToken($0, .allAssets) }, toSection: .allAssets)
        }
        
        dataSource?.apply(snapshot, animatingDifferences: false)
    }
}

extension TokenSelectionVC: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        keyword = searchController.searchBar.text ?? ""
        filterTokens()
    }
}

extension TokenSelectionVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            updateWalletTokens()
            filterTokens()
        default:
            break
        }
    }
}
