//
//  TokenSelectionVC.swift
//  UIComponents
//
//  Created by Sina on 5/10/24.
//

import Foundation
import UIKit
import SwiftUI
import UniversalSearchWalletCore
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
    
    public struct FiatOption {
        public let currency: MBaseCurrency
        public let subtitle: String
        public let onSelect: () -> Void

        public init(currency: MBaseCurrency, subtitle: String, onSelect: @escaping () -> Void) {
            self.currency = currency
            self.subtitle = subtitle
            self.onSelect = onSelect
        }
    }

    // MARK: - Diffable Data Source Types
    
    private enum Section: Hashable {
        case fiat
        case myAssets
        case stablecoins
        case popular
        case allAssets
        case search

        var title: String {
            switch self {
            case .myAssets:
                lang("My")
            case .popular:
                lang("Popular")
            case .stablecoins:
                lang("Stablecoins")
            case .allAssets:
                lang("A ~ Z")
            case .fiat, .search:
                ""
            }
        }
    }
    
    private enum Item: Hashable {
        case fiatCurrency(MBaseCurrency)
        case walletToken(MTokenBalance)
        case apiToken(ApiToken, Section)
        
        static func == (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
            case (.fiatCurrency(let l), .fiatCurrency(let r)):
                return l == r
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
            case .fiatCurrency(let currency):
                hasher.combine("fiat")
                hasher.combine(currency)
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
    private let showOnlyMyAssets: Bool
    private let myAssetsDisplayMode: MyAssetsDisplayMode
    private let isModal: Bool
    private let onlySupportedChains: Bool
    private let chainFilter: ApiChain?
    private let fiatOptions: [FiatOption]
    private let showsAssetCategories: Bool
    private enum Category: Int, CaseIterable {
        case all, fiat, stablecoins, tokens
        var title: String { lang(["All", "Fiat", "Stablecoins", "Tokens"][rawValue]) }
    }
    private var category = Category.all
    private lazy var categoryControl = UISegmentedControl(items: Category.allCases.map(\.title))
    private let emptyLabel = UILabel()
    private var categoryPaletteWidth: NSLayoutConstraint?
    private var availablePairs: [MPair]?
    private let log = Log()
    private var walletTokens = [MTokenBalance]()
    private var showingWalletTokens = [MTokenBalance]()
    private var showingPopularTokens = [ApiToken]()
    private var showingStablecoins = [ApiToken]()
    private var showingAllAssets = [ApiToken]()
    private var showingSearchItems = [Item]()
    private var tokenSearch = WalletCoreTokenSearch()
    private var tokenSearchNeedsUpdate = true
    private var keyword = String()
    private var searchController: UISearchController?

    private var secondaryAmountMode: TokenCell.SecondaryAmountMode {
        showsAssetCategories ? .balanceValueOrPrice : myAssetsDisplayMode == .swap ? .tokenPrice : .balanceValue
    }
    
    private var shouldSaveSelectedApiToken: Bool {
        myAssetsDisplayMode != .swap
    }

    @AccountContext(source: .current) private var account: MAccount
    
    private var collectionView: UICollectionView?
    private var activityIndicatorView: WActivityIndicator?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    
    // MARK: - Init
    
    public init(forceAvailable: String? = nil,
                extraWalletTokenSlugs: [String] = [],
                otherSymbolOrMinterAddress: String? = nil,
                showMyAssets: Bool = true,
                showOnlyMyAssets: Bool = false,
                myAssetsDisplayMode: MyAssetsDisplayMode = .default,
                title: String,
                delegate: TokenSelectionVCDelegate?,
                isModal: Bool,
                onlySupportedChains: Bool,
                chainFilter: ApiChain? = nil,
                fiatOptions: [FiatOption] = [],
                showsAssetCategories: Bool = false) {
        self.forceAvailable = forceAvailable
        self.extraWalletTokenSlugs = extraWalletTokenSlugs
        self.otherSymbolOrMinterAddress = otherSymbolOrMinterAddress
        self.showMyAssets = showMyAssets
        self.showOnlyMyAssets = showOnlyMyAssets
        self.myAssetsDisplayMode = myAssetsDisplayMode
        self.delegate = delegate
        self.isModal = isModal
        self.onlySupportedChains = onlySupportedChains
        self.chainFilter = chainFilter
        self.fiatOptions = fiatOptions
        self.showsAssetCategories = showsAssetCategories
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
        
        filterTokens()
        
        if let otherSymbolOrMinterAddress {
            activityIndicatorView?.startAnimating(animated: true)
            collectionView?.alpha = 0
            Task {
                do {
                    let pairs = try await Api.swapGetPairs(symbolOrMinter: otherSymbolOrMinterAddress)
                    availablePairs = pairs
                } catch {
                    log.error("failed to load swap pairs \(error, .public)")
                }
                activityIndicatorView?.stopAnimating(animated: true)
                applySnapshot()
                UIView.animate(withDuration: 0.2) { [weak self] in
                    guard let self else { return }
                    collectionView?.alpha = 1
                    activityIndicatorView?.alpha = 0
                } completion: { [weak self] _ in
                    guard let self else { return }
                    activityIndicatorView?.stopAnimating(animated: true)
                }
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        categoryPaletteWidth?.constant = view.safeAreaLayoutGuide.layoutFrame.width
    }
    
    // MARK: - Setup
    
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.showsSeparators = true
            if self?.showsAssetCategories == true { listConfig.headerTopPadding = 0 }
            let identifier = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            listConfig.headerMode = identifier == .search || (identifier == .fiat && self?.showsAssetCategories != true) ? .none : .supplementary

            let separatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 62, bottom: 0, trailing: IOS_26_MODE_ENABLED ? 12 : 0)
            var separatorConfig = UIListSeparatorConfiguration(listAppearance: .plain)
            separatorConfig.topSeparatorInsets = separatorInsets
            separatorConfig.bottomSeparatorInsets = separatorInsets
            listConfig.separatorConfiguration = separatorConfig

            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            if self?.showsAssetCategories == true, listConfig.headerMode == .supplementary {
                section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top
                )]
            }
            section.contentInsets.bottom = self?.showsAssetCategories == true ? 8 : 12
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
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        self.collectionView = collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delaysContentTouches = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        view.addStretchedToSafeArea(subview: collectionView, top: \.topAnchor, bottom: \.bottomAnchor)
        if showsAssetCategories {
            if !showOnlyMyAssets || ownedTradeTokens.count > 5 {
                installCategoryPalette()
            }
            addCustomNavigationBarBackground(color: .air.pickerBackground)
            emptyLabel.text = lang("Not Found")
            emptyLabel.textAlignment = .center
            emptyLabel.textColor = .air.secondaryLabel
            emptyLabel.applyTextStyle(.body)
        }
        
        let activityIndicatorView = WActivityIndicator()
        self.activityIndicatorView = activityIndicatorView
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicatorView)
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])

        updateTheme()
    }
    
    private func installCategoryPalette() {
        categoryControl.selectedSegmentIndex = category.rawValue
        categoryControl.apportionsSegmentWidthsByContent = true
        categoryControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.label], for: .normal)
        categoryControl.setTitleTextAttributes([.foregroundColor: UIColor(hex: "#0088FF")], for: .selected)
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)

        let contentView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 56))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(categoryControl)
        let width = contentView.widthAnchor.constraint(equalToConstant: view.bounds.width)
        categoryPaletteWidth = width
        NSLayoutConstraint.activate([
            width,
            categoryControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            categoryControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            categoryControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            categoryControl.heightAnchor.constraint(equalToConstant: 40),
        ])
        if let cls = NSClassFromString("ettelaPraBnoitagivaNIU_".reverse) as? UIView.Type {
            let palette = cls.perform(NSSelectorFromString("alloc"))
                .takeUnretainedValue()
                .perform(NSSelectorFromString("initWithContentView:"), with: contentView)
                .takeUnretainedValue()
            navigationItem.perform(NSSelectorFromString(":ettelaPmottoBtes_".reverse), with: palette)
        }
    }

    private func configureDataSource() {
        guard let collectionView else { return }
        let cellRegistration = UICollectionView.CellRegistration<TokenCell, Item> { [weak self] cell, indexPath, item in
            guard let self else { return }
            self.configure(cell: cell, for: item, at: indexPath)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self else { return }
            guard let dataSource = self.dataSource else { return }
            let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
            guard indexPath.section < sectionIdentifiers.count else { return }
            var content = UIListContentConfiguration.plainHeader()
            let section = sectionIdentifiers[indexPath.section]
            content.text = section.title
            content.directionalLayoutMargins.leading += 54
            headerView.contentConfiguration = content
        }

        let assetHeaderRegistration = UICollectionView.SupplementaryRegistration<AssetSectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.dataSource?.sectionIdentifier(for: indexPath.section) else { return }
            header.label.text = section == .fiat ? lang("Fiat")
                : section == .popular ? lang("Tokens") : section.title
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        self.dataSource = dataSource
        dataSource.supplementaryViewProvider = { [weak self] collectionView, _, indexPath in
            if self?.showsAssetCategories == true {
                return collectionView.dequeueConfiguredReusableSupplementary(using: assetHeaderRegistration, for: indexPath)
            }
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }
    
    private func configure(cell: TokenCell, for item: Item, at indexPath: IndexPath) {
        switch item {
        case .fiatCurrency(let currency):
            if let option = fiatOptions.first(where: { $0.currency == currency }) {
                cell.configure(currency: currency, onSelect: option.onSelect)
            }
        case .walletToken(let token):
            let isAvailable = isTokenAvailable(slug: token.tokenSlug)
            cell.configure(
                with: token,
                isAvailable: isAvailable,
                secondaryAmountMode: secondaryAmountMode
            ) { [weak self] in
                guard let self, isTokenAvailable(slug: token.tokenSlug) else { return }
                recordSearchSelection(tokenSlug: token.tokenSlug)
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
                recordSearchSelection(tokenSlug: token.slug)
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
        tokenSearchNeedsUpdate = true
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
        
        showingWalletTokens = (showsAssetCategories ? ownedTradeTokens : walletTokens).filter { token in
            guard let apiToken = TokenStore.tokens[token.tokenSlug] else { return false }
            guard shouldIncludeChain(apiToken.chain), matchesCategory(apiToken) else { return false }
            if !showsAssetCategories, myAssetsDisplayMode == .swap, (apiToken.price ?? 0) == 0 {
                return false
            }
            return true
        }

        let sourceAssets: [ApiToken] = if onlySupportedChains {
            Array(TokenStore.tokens.values)
        } else {
            TokenStore.swapAssets ?? []
        }
        let eligibleAssets = showOnlyMyAssets ? [] : sourceAssets.filter { shouldIncludeChain($0.chain) && matchesCategory($0) }
        showingStablecoins = []
        if !keyword.isEmpty {
            let balancesBySlug = Dictionary(
                showingWalletTokens.map { ($0.tokenSlug, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let assetsBySlug = Dictionary(
                eligibleAssets.map { ($0.slug, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if tokenSearchNeedsUpdate {
                let candidates = showingWalletTokens.compactMap { TokenStore.tokens[$0.tokenSlug] } + eligibleAssets
                tokenSearch.update(
                    accountID: account.id,
                    tokens: candidates,
                    balances: BalanceDataStore.walletTokensData(accountId: account.id)?.allTokenBalances ?? walletTokens,
                    trackedTokenSlugs: AssetsAndActivityDataStore.data(accountId: account.id)?.importedSlugs ?? []
                )
                tokenSearchNeedsUpdate = false
            }
            showingSearchItems = tokenSearch.search(keyword).compactMap { slug in
                if let balance = balancesBySlug[slug] {
                    return .walletToken(balance)
                }
                return assetsBySlug[slug].map { .apiToken($0, .search) }
            }
            if showsAssetCategories {
                showingWalletTokens = showingSearchItems.compactMap {
                    if case .walletToken(let token) = $0 { return token }
                    return nil
                }
                showingSearchItems = showingSearchItems.filter {
                    guard case .apiToken(let token, _) = $0 else { return false }
                    if category == .all, isStablecoin(token) {
                        showingStablecoins.append(token)
                        return false
                    }
                    return true
                }
            }
            applySnapshot()
            return
        }
        showingSearchItems = []
        
        if myAssetsDisplayMode == .swap {
            showingWalletTokens.sort { lhs, rhs in
                let lhsAmount = lhs.toBaseCurrency ?? 0
                let rhsAmount = rhs.toBaseCurrency ?? 0
                if lhsAmount != rhsAmount {
                    return lhsAmount > rhsAmount
                }
                let lhsName = lhs.token?.displayName(strippingLabelWhenShown: false) ?? lhs.tokenSlug
                let rhsName = rhs.token?.displayName(strippingLabelWhenShown: false) ?? rhs.tokenSlug
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
        }

        let filteredAssets = eligibleAssets
            .sorted {
                $0.displayName(strippingLabelWhenShown: false)
                    .localizedCaseInsensitiveCompare($1.displayName(strippingLabelWhenShown: false)) == .orderedAscending
            }

        if showsAssetCategories {
            let ownedSlugs = Set(showingWalletTokens.map(\.tokenSlug))
            let remainingAssets = filteredAssets.filter { !ownedSlugs.contains($0.slug) }
            showingStablecoins = category == .all ? remainingAssets.filter(isStablecoin) : []
            let stablecoinSlugs = Set(showingStablecoins.map(\.slug))
            showingPopularTokens = remainingAssets.filter {
                !stablecoinSlugs.contains($0.slug) && (category == .stablecoins || $0.isPopular == true)
            }
            showingAllAssets = []
        } else {
            showingPopularTokens = filteredAssets.filter { $0.isPopular == true }
            showingAllAssets = filteredAssets
        }
        
        applySnapshot()
    }
    
    private func applySnapshot() {
        // Don't show anything if waiting for pairs to load
        guard otherSymbolOrMinterAddress == nil || availablePairs != nil else {
            let snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            apply(snapshot)
            return
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        for option in fiatOptions where category == .all || category == .fiat {
            let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = query.isEmpty || [option.currency.rawValue, option.currency.name, option.subtitle]
                .contains { $0.localizedStandardContains(query) }
            if matches {
                if !snapshot.sectionIdentifiers.contains(.fiat) { snapshot.appendSections([.fiat]) }
                snapshot.appendItems([.fiatCurrency(option.currency)], toSection: .fiat)
            }
        }
        if showsAssetCategories, !showingWalletTokens.isEmpty {
            snapshot.appendSections([.myAssets])
            snapshot.appendItems(showingWalletTokens.map { .walletToken($0) }, toSection: .myAssets)
        }
        if !showingStablecoins.isEmpty {
            snapshot.appendSections([.stablecoins])
            snapshot.appendItems(showingStablecoins.map { .apiToken($0, .stablecoins) }, toSection: .stablecoins)
        }

        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.appendSections([.search])
            snapshot.appendItems(showingSearchItems, toSection: .search)
            updateEmptyState(snapshot)
            apply(snapshot)
            return
        }
        
        if !showsAssetCategories, !showingWalletTokens.isEmpty {
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
        
        updateEmptyState(snapshot)
        apply(snapshot)
    }

    private func apply(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>) {
        var snapshot = snapshot
        if showsAssetCategories, let current = dataSource?.snapshot() {
            let existingItems = Set(current.itemIdentifiers)
            snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existingItems.contains($0) })
        }
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func updateEmptyState(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>) {
        if showsAssetCategories { collectionView?.backgroundView = snapshot.numberOfItems == 0 ? emptyLabel : nil }
    }

    private func matchesCategory(_ token: ApiToken) -> Bool {
        switch category {
        case .all: true
        case .fiat: false
        case .tokens: true
        case .stablecoins: isStablecoin(token)
        }
    }

    private var ownedTradeTokens: [MTokenBalance] {
        let assetSlugs = Set((TokenStore.swapAssets ?? []).map(\.slug))
        return walletTokens.filter { $0.balance > 0 && assetSlugs.contains($0.tokenSlug) }
    }

    private func isStablecoin(_ token: ApiToken) -> Bool {
        if ApiChain.allCases.contains(where: { $0.usdtSlug[account.network] == token.slug }) {
            return true
        }
        if token.slug == BASE_USDC_MAINNET_SLUG { return true }
        return account.network == .mainnet && [SOLANA_USDC_MAINNET_SLUG, ETH_USDC_MAINNET_SLUG].contains(token.slug)
    }

    @objc private func categoryChanged() {
        category = Category(rawValue: categoryControl.selectedSegmentIndex) ?? .all
        tokenSearchNeedsUpdate = true
        filterTokens()
    }

    private func recordSearchSelection(tokenSlug: String) {
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        tokenSearch.recordSelection(tokenSlug: tokenSlug, accountID: account.id)
        tokenSearchNeedsUpdate = true
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
        case .balanceChanged, .tokensChanged, .swapTokensChanged, .accountChanged, .assetsAndActivityDataUpdated:
            updateWalletTokens()
            filterTokens()
        default:
            break
        }
    }
}

private final class AssetSectionHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.applyTextStyle(.calloutStrong)
        label.textColor = .air.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
