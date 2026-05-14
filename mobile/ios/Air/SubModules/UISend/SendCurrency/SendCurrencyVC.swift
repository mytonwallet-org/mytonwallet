//
//  SendCurrencyVC.swift
//  UISend
//
//  Created by Sina on 4/18/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Dependencies

class SendCurrencyVC: WViewController {
    
    var walletTokens = [MTokenBalance]()
    private var walletTokensBySlug: [String: MTokenBalance] = [:]
    private var showingTokenSlugs: [String] = []
    var keyword = String()
    
    let accountId: String
    let isMultichain: Bool
    var currentTokenSlug: String
    var onSelect: (ApiToken) -> ()
    
    @Dependency(\.balancesStore) private var balancesStore
    @Dependency(\.tokenStore) private var tokenStore
    
    public init(accountId: String, isMultichain: Bool, walletTokens: [MTokenBalance], currentTokenSlug: String, onSelect: @escaping (ApiToken) -> ()) {
        self.accountId = accountId
        self.isMultichain = isMultichain
        self.currentTokenSlug = currentTokenSlug
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.walletTokens = walletTokens
        self.walletTokensBySlug = Dictionary(uniqueKeysWithValues: walletTokens.map { ($0.tokenSlug, $0) })
        self.showingTokenSlugs = walletTokens.map(\.tokenSlug)
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
    }
    private struct Item: Hashable {
        let tokenSlug: String
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.showsSeparators = true
            listConfig.headerMode = .none

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
        title = lang("Choose Currency")
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
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
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
                if let token = self.tokenStore.tokens[item.tokenSlug] {
                    self.searchController.isActive = false // to prevent ui animation glitch on push
                    self.onSelect(token)
                }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
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
        guard !keyword.isEmpty else {
            let sorted = walletTokens.sorted { lhs, rhs in
                return lhs.toBaseCurrency ?? 0 > rhs.toBaseCurrency ?? 0
            }
            showingTokenSlugs = sorted.map(\.tokenSlug)
            applySnapshot(animated: false)
            return
        }
        let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = walletTokens.filter({ it in
            if it.tokenSlug.lowercased().contains(normalizedKeyword) {
                return true
            }
            return tokenStore.tokens[it.tokenSlug]?.matchesSearch(normalizedKeyword) == true
        }).sorted { lhs, rhs in
            return lhs.toBaseCurrency ?? 0 > rhs.toBaseCurrency ?? 0
        }
        showingTokenSlugs = filtered.map(\.tokenSlug)
        applySnapshot(animated: false)
    }
    
    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(showingTokenSlugs.map { Item(tokenSlug: $0) }, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}

extension SendCurrencyVC: UISearchBarDelegate, UISearchResultsUpdating {
    
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

extension SendCurrencyVC {
    func balanceChanged() {
        walletTokens = balancesStore.getAccountBalances(accountId: accountId).map({ (key: String, value: BigInt) in
            MTokenBalance(tokenSlug: key, balance: value, isStaking: false)
        })
        walletTokensBySlug = Dictionary(uniqueKeysWithValues: walletTokens.map { ($0.tokenSlug, $0) })
        filterWalletTokens()
    }
}

extension SendCurrencyVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged:
            balanceChanged()
            break
        default:
            break
        }
    }
}
