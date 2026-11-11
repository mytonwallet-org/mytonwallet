//
//  TokenPickerViewController.swift
//  UISend
//
//  Created by Sina on 4/18/24.
//

import Foundation
import UIKit
import UIComponents
import UniversalSearchWalletCore
import WalletCore
import WalletContext

final class TokenPickerViewController: WViewController {
    
    var walletTokens = [MTokenBalance]()
    private var hiddenWalletTokens = [MTokenBalance]()
    private var walletTokensBySlug: [String: MTokenBalance] = [:]
    private var showingTokenSlugs = [String]()
    private var showingHiddenTokenSlugs = [String]()
    var keyword = String()
    private var tokenSearch = WalletCoreTokenSearch()
    private var tokenSearchNeedsUpdate = true
    
    let accountId: String
    let isMultichain: Bool
    var currentTokenSlug: String
    var onSelect: (ApiToken) -> ()
    
    public init(accountId: String,
                isMultichain: Bool,
                presentation: MTokenBalance.Presentation,
                currentTokenSlug: String,
                onSelect: @escaping (ApiToken) -> ()) {
        self.accountId = accountId
        self.isMultichain = isMultichain
        self.currentTokenSlug = currentTokenSlug
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        updateWalletTokens(with: presentation)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
        balanceChanged()
    }

    private var contentView: TokenPickerContentView!

    private enum Section: Hashable {
        case main
        case hidden

        var title: String? {
            switch self {
            case .main:
                nil
            case .hidden:
                lang("$token_picker_hidden")
            }
        }
    }
    private struct Item: Hashable {
        let tokenSlug: String
    }

    private var dataSources: [TokenPickerCategory: UICollectionViewDiffableDataSource<Section, Item>] = [:]

    private func makeLayout(for category: TokenPickerCategory) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.showsSeparators = true
            listConfig.headerMode = self?.dataSources[category]?.sectionIdentifier(for: sectionIndex) == .hidden ? .supplementary : .none

            let separatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 62, bottom: 0, trailing: IOS_26_MODE_ENABLED ? 12 : 0)
            var separatorConfig = UIListSeparatorConfiguration(listAppearance: .plain)
            separatorConfig.topSeparatorInsets = separatorInsets
            separatorConfig.bottomSeparatorInsets = separatorInsets
            listConfig.separatorConfiguration = separatorConfig
            listConfig.itemSeparatorHandler = { indexPath, config in
                var config = config
                if indexPath.item == 0 {
                    config.topSeparatorVisibility = .hidden
                }
                return config
            }

            return NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
        }
    }

    private func setupViews() {
        title = lang("Select Token")
        addCloseNavigationItemIfNeeded()

        contentView = TokenPickerContentView(parent: self) { [unowned self] category in
            makeCollectionView(for: category)
        }
        contentView.searchBar.onTextChange = { [weak self] text in
            guard let self else { return }
            keyword = text
            filterWalletTokens()
        }
        view.backgroundColor = .air.pickerBackground
        addCustomNavigationBarBackground(color: .air.pickerBackground)
    }

    private func makeCollectionView(for category: TokenPickerCategory) -> UICollectionView {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout(for: category))
        let cellRegistration = UICollectionView.CellRegistration<TokenCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            guard let walletToken = self.walletTokensBySlug[item.tokenSlug] else {
                cell.configure(
                    with: .init(tokenSlug: item.tokenSlug, balance: 0, isStaking: false),
                    isAvailable: true,
                    isCurrentSelection: item.tokenSlug == self.currentTokenSlug
                ) {}
                return
            }
            cell.configure(
                with: walletToken,
                isAvailable: true,
                isCurrentSelection: item.tokenSlug == self.currentTokenSlug
            ) { [weak self] in
                guard let self else { return }
                if let token = TokenStore.tokens[item.tokenSlug] {
                    if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        tokenSearch.recordSelection(tokenSlug: token.slug, accountID: accountId)
                    }
                    self.view.endEditing(true)
                    self.onSelect(token)
                }
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self,
                  let section = dataSources[category]?.sectionIdentifier(for: indexPath.section) else {
                return
            }
            var content = UIListContentConfiguration.plainHeader()
            content.text = section.title
            content.directionalLayoutMargins.leading += 54
            headerView.contentConfiguration = content
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSources[category] = dataSource
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }

        return collectionView
    }

    func filterWalletTokens() {
        contentView.updateCategories(TokenPickerCategory.getAvailableCategories(
            tokenSlugs: selectableWalletTokens(walletTokens + hiddenWalletTokens).map(\.tokenSlug)
        ))
        let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty else {
            showingTokenSlugs = selectableWalletTokens(walletTokens).map(\.tokenSlug)
            showingHiddenTokenSlugs = []
            applySnapshot(animated: false)
            return
        }
        let visibleSlugs = Set(selectableWalletTokens(walletTokens).map(\.tokenSlug))
        let hiddenSlugs = Set(selectableWalletTokens(hiddenWalletTokens).map(\.tokenSlug))
        if tokenSearchNeedsUpdate {
            let candidates = visibleSlugs.union(hiddenSlugs).compactMap { TokenStore.tokens[$0] }
            tokenSearch.update(
                accountID: accountId,
                tokens: candidates,
                balances: BalanceDataStore.walletTokensData(accountId: accountId)?.allTokenBalances
                    ?? walletTokens + hiddenWalletTokens,
                trackedTokenSlugs: AssetsAndActivityDataStore.data(accountId: accountId)?.importedSlugs ?? []
            )
            tokenSearchNeedsUpdate = false
        }
        let rankedSlugs = tokenSearch.search(normalizedKeyword)
        showingTokenSlugs = rankedSlugs.filter { visibleSlugs.contains($0) }
        showingHiddenTokenSlugs = rankedSlugs.filter { hiddenSlugs.contains($0) && !visibleSlugs.contains($0) }
        applySnapshot(animated: false)
    }

    private func selectableWalletTokens(_ tokens: [MTokenBalance]) -> [MTokenBalance] {
        tokens.filter { walletToken in
            guard TokenStore.tokens[walletToken.tokenSlug]?.type == .lp_token else {
                return true
            }
            return walletToken.balance > 0 || walletToken.tokenSlug == currentTokenSlug
        }
    }
    
    private func applySnapshot(animated: Bool) {
        for category in contentView.categories {
            guard let dataSource = dataSources[category] else { continue }
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            let visibleSlugs = showingTokenSlugs.filter { category.shouldInclude(tokenSlug: $0) }
            let hiddenSlugs = showingHiddenTokenSlugs.filter { category.shouldInclude(tokenSlug: $0) }
            snapshot.appendSections([.main])
            snapshot.appendItems(visibleSlugs.map { Item(tokenSlug: $0) }, toSection: .main)
            if !hiddenSlugs.isEmpty {
                snapshot.appendSections([.hidden])
                snapshot.appendItems(hiddenSlugs.map { Item(tokenSlug: $0) }, toSection: .hidden)
            }
            let existingItems = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existingItems.contains($0) })
            dataSource.apply(snapshot, animatingDifferences: animated)
            contentView.updateEmptyState(snapshot.numberOfItems == 0, for: category)
        }
    }
}

extension TokenPickerViewController {
    func balanceChanged() {
        tokenSearchNeedsUpdate = true
        if let presentation = BalanceDataStore.walletTokensData(accountId: accountId)?.presentation {
            updateWalletTokens(with: presentation)
        }
        filterWalletTokens()
    }

    private func updateWalletTokens(with presentation: MTokenBalance.Presentation) {
        walletTokens = presentation.visible.filter { !$0.isStaking }
        hiddenWalletTokens = presentation.hidden.filter { !$0.isStaking }
        walletTokensBySlug = Dictionary(
            uniqueKeysWithValues: (walletTokens + hiddenWalletTokens).map {
                ($0.tokenSlug, $0)
            }
        )
        showingTokenSlugs = selectableWalletTokens(walletTokens).map(\.tokenSlug)
        showingHiddenTokenSlugs = []
    }
}

extension TokenPickerViewController: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged, .assetsAndActivityDataUpdated:
            balanceChanged()
        default:
            break
        }
    }
}
