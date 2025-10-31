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
    
    private weak var delegate: TokenSelectionVCDelegate? = nil
    private var forceAvailable: String? = nil
    private var otherSymbolOrMinterAddress: String? = nil
    private let showMyAssets: Bool
    private let isModal: Bool
    private let onlyTonChain: Bool
    private var availablePairs: [MPair]? = nil
    private let log = Log()
    var walletTokens = [MTokenBalance]()
    var showingWalletTokens = [MTokenBalance]()
    var showingPopularTokens = [ApiToken]()
    var showingAllAssets = [ApiToken]()
    var keyword = String()
    private var searchController: UISearchController? = nil
    
    public init(
        forceAvailable: String? = nil,
        otherSymbolOrMinterAddress: String? = nil,
        showMyAssets: Bool = true,
        title: String,
        delegate: TokenSelectionVCDelegate?,
        isModal: Bool,
        onlyTonChain: Bool) {
            self.forceAvailable = forceAvailable
            self.otherSymbolOrMinterAddress = otherSymbolOrMinterAddress
            self.showMyAssets = showMyAssets
            self.delegate = delegate
            self.isModal = isModal
            self.onlyTonChain = onlyTonChain
            super.init(nibName: nil, bundle: nil)
            self.title = title
            balanceChanged()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
        Task { [weak self] in
            do {
                _ = try await TokenStore.updateSwapAssets()
                self?.filterTokens()
            } catch {
            }
        }
        if let otherSymbolOrMinterAddress {
            activityIndicatorView.startAnimating(animated: true)
            tableView.alpha = 0
            Task {
                do {
                    let pairs = try await Api.swapGetPairs(symbolOrMinter: otherSymbolOrMinterAddress)
                    availablePairs = pairs
                } catch {
                    log.error("failed to load swap pairs \(error, .public)")
                }
                activityIndicatorView.stopAnimating(animated: true)
                tableView.reloadData()
                UIView.animate(withDuration: 0.2) { [weak self] in
                    guard let self else {return}
                    tableView.alpha = 1
                    activityIndicatorView.alpha = 0
                } completion: { [weak self] _ in
                    guard let self else {return}
                    activityIndicatorView.stopAnimating(animated: true)
                }
            }
        }
    }
    
    var tableView: UITableView!
    var activityIndicatorView: WActivityIndicator!
    
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
        
        tableView = UITableView()
        tableView.allowsSelection = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(TokenCell.self, forCellReuseIdentifier: "Token")
        tableView.register(TokenHeaderCell.self, forCellReuseIdentifier: "TokenHeader")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 56
        tableView.delaysContentTouches = false
        tableView.sectionHeaderTopPadding = 0
        
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
        
        activityIndicatorView = WActivityIndicator()
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicatorView)
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
        
        bringNavigationBarToFront()

        updateTheme()
    }
    
    public override func updateTheme() {
        tableView.backgroundColor = WTheme.pickerBackground
    }
    
    @objc func hideKeyboard() {
        view.endEditing(false)
    }
    
    func filterTokens() {
        let keyword = self.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        showingWalletTokens = walletTokens.filter { token in
            if let token = TokenStore.tokens[token.tokenSlug] {
                return (!onlyTonChain || token.chain == TON_CHAIN) && token.matchesSearch(keyword)
            }
            return false
        }
        showingPopularTokens = TokenStore.swapAssets?.filter { swapAsset in
            guard swapAsset.isPopular == true else { return false }
            return (!onlyTonChain || swapAsset.chain == TON_CHAIN) && swapAsset.matchesSearch(keyword)
        } ?? []
        showingAllAssets = TokenStore.swapAssets?.filter { swapAsset in
            return (!onlyTonChain || swapAsset.chain == TON_CHAIN) && swapAsset.matchesSearch(keyword)
        } ?? []
        tableView?.reloadData()
    }
}

extension TokenSelectionVC: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        keyword = searchController.searchBar.text ?? ""
        filterTokens()
    }
}

extension TokenSelectionVC: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        // otherSymbolOrMinterAddress: nil when selling token is selected and no filters are required.
        // availablePairs: nil when buying token is selected and should filter, but nothing received yet!
        otherSymbolOrMinterAddress == nil || availablePairs != nil ? 3 : 0
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return showingWalletTokens.count > 0 ? 1 + showingWalletTokens.count : 0
        case 1:
            return showingPopularTokens.count > 0 ? 1 + showingPopularTokens.count : 0
        case 2:
            return showingAllAssets.count > 0 ? 1 + showingAllAssets.count : 0
        default:
            fatalError()
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TokenHeader", for: indexPath) as! TokenHeaderCell
            // Headers
            switch indexPath.section {
            case 0:
                cell.configure(title: lang("My assets"))
            case 1:
                cell.configure(title: lang("Popular"))
            case 2:
                cell.configure(title: lang("A ~ Z"))
            default:
                break
            }
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Token", for: indexPath) as! TokenCell
        switch indexPath.section {
        case 0:
            let token = showingWalletTokens[indexPath.row - 1]
            let isAvailable = otherSymbolOrMinterAddress == nil || (
                availablePairs?.contains(where: { pair in
                    pair.slug == token.tokenSlug
                }) ?? false
            )
            cell.configure(with: token,
                           isAvailable: isAvailable || token.tokenSlug == forceAvailable) { [weak self] in
                guard let self else { return }
                let isAvailable = otherSymbolOrMinterAddress == nil || (
                    availablePairs?.contains(where: { pair in
                        pair.slug == token.tokenSlug
                    }) ?? false
                )
                if !isAvailable && token.tokenSlug != forceAvailable {
                    return
                }
                delegate?.didSelect(token: token)
                navigationController?.popViewController(animated: true)
            }
        case 1:
            let token = showingPopularTokens[indexPath.row - 1]
            let isAvailable = otherSymbolOrMinterAddress == nil || (
                availablePairs?.contains(where: { pair in
                    pair.slug == token.slug
                }) ?? false
            )
            cell.configure(with: token, isAvailable: isAvailable || token.slug == forceAvailable) { [weak self] in
                guard let self else { return }
                let isAvailable = otherSymbolOrMinterAddress == nil || (
                    availablePairs?.contains(where: { pair in
                        pair.slug == token.slug
                    }) ?? false
                )
                if !isAvailable && token.slug != forceAvailable {
                    return
                }
                delegate?.didSelect(token: token)
                navigationController?.popViewController(animated: true)
            }
        case 2:
            let token = showingAllAssets[indexPath.row - 1]
            let isAvailable = otherSymbolOrMinterAddress == nil || (
                availablePairs?.contains(where: { pair in
                    pair.slug == token.slug
                }) ?? false
            )
            cell.configure(with: token, isAvailable: isAvailable || token.slug == forceAvailable) { [weak self] in
                guard let self else { return }
                let isAvailable = otherSymbolOrMinterAddress == nil || (
                    availablePairs?.contains(where: { pair in
                        pair.slug == token.slug
                    }) ?? false
                )
                if !isAvailable && token.slug != forceAvailable {
                    return
                }
                delegate?.didSelect(token: token)
                navigationController?.popViewController(animated: true)
            }
            break
        default:
            fatalError()
        }
        return cell
    }
    
    public func balanceChanged() {
        walletTokens = showMyAssets ? BalanceStore.currentAccountBalanceData?.walletTokens ?? [] : []
        filterTokens()
    }
}

extension TokenSelectionVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            balanceChanged()
            break
        default:
            break
        }
    }
}
