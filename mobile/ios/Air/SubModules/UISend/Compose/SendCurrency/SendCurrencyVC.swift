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

class SendCurrencyVC: WViewController {
    
    var walletTokens = [MTokenBalance]()
    var showingWalletTokens = [MTokenBalance]()
    var keyword = String()
    
    var currentTokenSlug: String
    var onSelect: (ApiToken) -> ()
    
    public init(walletTokens: [MTokenBalance], currentTokenSlug: String, onSelect: @escaping (ApiToken) -> ()) {
        self.currentTokenSlug = currentTokenSlug
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.walletTokens = walletTokens
        self.showingWalletTokens = walletTokens
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
    private var tableViewBackgroundView: UIView!
    private func setupViews() {
        title = lang("Choose Currency")
        navigationController?.navigationBar.isTranslucent = false
        addCloseToNavBar()

        searchController.searchBar.delegate = self
        searchController.searchBar.isTranslucent = false
        searchController.searchResultsUpdater = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.searchBarStyle = .minimal
        searchController.searchBar.autocorrectionType = .no
        searchController.searchBar.spellCheckingType = .no
        searchController.searchBar.setShowsCancelButton(false, animated: false)
        searchController.searchBar.setCenteredPlaceholder()

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(CurrencyCell.self, forCellReuseIdentifier: "Currency")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 56
        tableViewBackgroundView = UIView()
        tableView.backgroundView = tableViewBackgroundView
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        updateTheme()
    }
    
    public override func updateTheme() {
        navigationController?.navigationBar.barTintColor = WTheme.sheetOpaqueBar
        navigationController?.navigationBar.backgroundColor = WTheme.sheetOpaqueBar
        searchController.searchBar.barTintColor = WTheme.sheetOpaqueBar
        searchController.searchBar.backgroundColor = WTheme.sheetOpaqueBar
        view.backgroundColor = WTheme.pickerBackground
        tableViewBackgroundView.backgroundColor = WTheme.pickerBackground
    }
    
    public override func closeButtonPressed() {
        searchController.isActive = false // to prevent searchController from blocking dismiss on vc
        super.closeButtonPressed()
    }
    
    @objc func hideKeyboard() {
        searchController.searchBar.endEditing(false)
    }
    
    func filterWalletTokens() {
        guard !keyword.isEmpty else {
            showingWalletTokens = walletTokens.sorted { lhs, rhs in
                return lhs.toBaseCurrency ?? 0 > rhs.toBaseCurrency ?? 0
            }
            tableView.reloadData()
            return
        }
        showingWalletTokens = walletTokens.filter({ it in
            it.tokenSlug.lowercased().contains(keyword.lowercased()) ||
            (TokenStore.tokens[it.tokenSlug]?.name.lowercased().contains(keyword.lowercased()) ?? false)
        }).sorted { lhs, rhs in
            return lhs.toBaseCurrency ?? 0 > rhs.toBaseCurrency ?? 0
        }
        tableView.reloadData()
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

extension SendCurrencyVC: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showingWalletTokens.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Currency", for: indexPath) as! CurrencyCell
        let walletToken = showingWalletTokens[indexPath.row]
        cell.configure(with: walletToken, currentTokenSlug: currentTokenSlug) { [weak self] in
            guard let self else { return }
            let tokenSlug = walletToken.tokenSlug
            if let token = TokenStore.tokens[tokenSlug] {
                searchController.isActive = false // to prevent ui animation glitch on push
                onSelect(token)
            }
        }
        return cell
    }

    public func balanceChanged() {
        walletTokens = BalanceStore.currentAccountBalances.map({ (key: String, value: BigInt) in
            MTokenBalance(tokenSlug: key, balance: value, isStaking: false)
        })
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
