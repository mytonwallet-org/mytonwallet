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
    
    @Dependency(\.balanceStore) private var balanceStore
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
    private var tableView: UITableView!
    
    private enum Section: Hashable {
        case main
    }
    private struct Item: Hashable {
        let tokenSlug: String
    }
    
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
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

        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(CurrencyCell.self, forCellReuseIdentifier: "Currency")
        tableView.delegate = self
        tableView.allowsSelection = false
        tableView.sectionHeaderTopPadding = 0
        tableView.tableHeaderView = UIView()
        tableView.tableFooterView = UIView()
        tableView.separatorInset.left = 70
        tableView.separatorInset.right = IOS_26_MODE_ENABLED ? 16 : 0
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 56
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "Currency", for: indexPath) as! CurrencyCell
            guard let walletToken = self.walletTokensBySlug[item.tokenSlug] else {
                cell.configure(with: .init(tokenSlug: item.tokenSlug, balance: 0, isStaking: false), token: self.tokenStore.tokens[item.tokenSlug], isMultichain: self.isMultichain, currentTokenSlug: self.currentTokenSlug) {
                }
                return cell
            }
            cell.configure(with: walletToken, token: self.tokenStore.tokens[item.tokenSlug], isMultichain: self.isMultichain, currentTokenSlug: self.currentTokenSlug) { [weak self] in
                guard let self else { return }
                if let token = self.tokenStore.tokens[item.tokenSlug] {
                    self.searchController.isActive = false // to prevent ui animation glitch on push
                    self.onSelect(token)
                }
            }
            return cell
        }
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.pickerBackground
        tableView.backgroundColor = WTheme.pickerBackground
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
        let filtered = walletTokens.filter({ it in
            it.tokenSlug.lowercased().contains(keyword.lowercased()) ||
            (tokenStore.tokens[it.tokenSlug]?.name.lowercased().contains(keyword.lowercased()) ?? false)
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

extension SendCurrencyVC: UITableViewDelegate {
    public func balanceChanged() {
        walletTokens = balanceStore.getAccountBalances(accountId: accountId).map({ (key: String, value: BigInt) in
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
