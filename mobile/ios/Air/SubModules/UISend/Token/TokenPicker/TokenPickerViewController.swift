//
//  TokenPickerViewController.swift
//  UISend
//
//  Created by Sina on 4/18/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class TokenPickerViewController: WViewController {
    
    var walletTokens = [MTokenBalance]()
    private var hiddenWalletTokens = [MTokenBalance]()
    private var walletTokensBySlug: [String: MTokenBalance] = [:]
    private var showingTokenSlugs = [String]()
    private var showingHiddenTokenSlugs = [String]()
    var keyword = String()
    
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
    
    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!

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

    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.showsSeparators = true
            listConfig.headerMode = sectionIndex == 1 ? .supplementary : .none

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

        searchController.searchBar.delegate = self
        searchController.searchBar.isTranslucent = false
        searchController.searchResultsUpdater = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.searchBarStyle = .minimal
        searchController.searchBar.autocorrectionType = .no
        searchController.searchBar.spellCheckingType = .no
        searchController.searchBar.setShowsCancelButton(false, animated: false)

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDismissMode = .onDrag
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

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
                    self.searchController.isActive = false // to prevent ui animation glitch on push
                    self.onSelect(token)
                }
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self,
                  let section = dataSource?.sectionIdentifier(for: indexPath.section) else {
                return
            }
            var content = UIListContentConfiguration.plainHeader()
            content.text = section.title
            content.directionalLayoutMargins.leading += 54
            headerView.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }

        updateTheme()
    }

    private func updateTheme() {
        view.backgroundColor = .air.pickerBackground
        collectionView?.backgroundColor = .air.pickerBackground
    }
    
    @objc func hideKeyboard() {
        searchController.searchBar.endEditing(false)
    }
    
    func filterWalletTokens() {
        let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty else {
            showingTokenSlugs = selectableWalletTokens(walletTokens).map(\.tokenSlug)
            showingHiddenTokenSlugs = []
            applySnapshot(animated: false)
            return
        }
        showingTokenSlugs = matchingTokenSlugs(
            in: selectableWalletTokens(walletTokens),
            keyword: normalizedKeyword
        )
        showingHiddenTokenSlugs = matchingTokenSlugs(
            in: selectableWalletTokens(hiddenWalletTokens),
            keyword: normalizedKeyword
        )
        applySnapshot(animated: false)
    }

    private func matchingTokenSlugs(
        in tokens: [MTokenBalance],
        keyword: String
    ) -> [String] {
        tokens.compactMap { walletToken in
            if walletToken.tokenSlug.lowercased().contains(keyword)
                || TokenStore.tokens[walletToken.tokenSlug]?.matchesSearch(keyword) == true {
                walletToken.tokenSlug
            } else {
                nil
            }
        }
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
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(showingTokenSlugs.map { Item(tokenSlug: $0) }, toSection: .main)
        if !showingHiddenTokenSlugs.isEmpty {
            snapshot.appendSections([.hidden])
            snapshot.appendItems(
                showingHiddenTokenSlugs.map { Item(tokenSlug: $0) },
                toSection: .hidden
            )
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}

extension TokenPickerViewController: UISearchBarDelegate, UISearchResultsUpdating {
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchController.searchBar.setPositionAdjustment(.init(horizontal: 8, vertical: 0), for: .search)
        return true
    }
    
    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        guard searchController.searchBar.text?.isEmpty != false else {
            return true
        }
        searchController.searchBar.setCenteredPlaceholder()
        return true
    }
    
    public func updateSearchResults(for searchController: UISearchController) {
        keyword = searchController.searchBar.text ?? ""
        filterWalletTokens()
    }
}

extension TokenPickerViewController {
    func balanceChanged() {
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
        case .balanceChanged, .tokensChanged:
            balanceChanged()
        default:
            break
        }
    }
}
