//
//  AssetsAndActivityVC.swift
//  UISettings
//
//  Created by Sina on 7/4/24.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import OrderedCollections


public class AssetsAndActivityVC: WViewController {
    
    enum Section {
        case baseCurrency
        case hiddenNfts
        case hideNoCost
        case tokens
    }
    enum Item: Equatable, Hashable {
        case baseCurrency
        case hiddenNfts
        case hideNoCost
        case addToken
        case token(String)
    }
    
    // MARK: - Load and SetupView Functions
    private lazy var isModal = navigationController?.viewControllers.count ?? 1 == 1
    private let queue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background")
    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background_processor")
    private var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    public override var hideNavigationBar: Bool { true }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        WalletCoreData.add(eventObserver: self)
    }

    var tokensToDisplay: [String] {
        var tokens: OrderedSet<String> = []
        
        if let walletTokens = BalanceStore.currentAccountBalanceData?.walletTokens.map(\.tokenSlug) {
            tokens.formUnion(walletTokens)
        }

        let balanceTokens = BalanceStore.currentAccountBalances.keys    
        tokens.formUnion(balanceTokens)

        tokens.formUnion(DEFAULT_SLUGS)

        if let account = AccountStore.account {
            tokens = tokens.filter { slug in
                if let chain = TokenStore.tokens[slug]?.chain {
                    return account.supports(chain: chain)
                }
                return false
            }
        }
        
        tokens.sort(by: { slug1, slug2 in
            if let token1 = TokenStore.tokens[slug1], let token2 = TokenStore.tokens[slug2] {
                if token1.priority != token2.priority {
                    return token1.priority < token2.priority
                }
                let balance1 = Double(BalanceStore.currentAccountBalances[slug1] ?? 0) * (token1.price ?? 0)
                let balance2 = Double(BalanceStore.currentAccountBalances[slug2] ?? 0) * (token2.price ?? 0)
                if balance1 != balance2 {
                    return balance1 > balance2
                }
                return token1.name < token2.name
            }
            return slug1 < slug2
        })
        
        return Array(tokens)
    }
    
    private var baseCurrency: MBaseCurrency { TokenStore.baseCurrency ?? .USD }
    
    private func setupViews() {
        title = lang("Assets & Activity")
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        let tableViewBackgroundView = UIView()
        tableViewBackgroundView.backgroundColor = .clear
        tableView.backgroundView = tableViewBackgroundView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = WTheme.separator
        tableView.register(AssetsAndActivityBaseCurrencyCell.self, forCellReuseIdentifier: "baseCurrencyCell")
        tableView.register(AssetsAndActivityHideNoCostCell.self, forCellReuseIdentifier: "hideNoCostTokensCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(AssetsAndActivityTokenCell.self, forCellReuseIdentifier: "tokenCell")
        tableView.delegate = self
        
        self.dataSource = makeDataSource()
        tableView.dataSource = dataSource
        
        tableView.delaysContentTouches = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        
        addNavigationBar(navHeight: isModal ? 56 : 40,
                         topOffset: isModal ? 0 : -5,
                         title: title,
                         closeIcon: isModal, addBackButton: isModal ? nil : { [weak self] in
            guard let self else {return}
            navigationController?.popViewController(animated: true)
        })
        tableView.contentInset.top = navigationBarHeight
        tableView.verticalScrollIndicatorInsets.top = navigationBarHeight
        tableView.contentOffset = .init(x: 0, y: -navigationBarHeight)
        
        applySnapshot(makeSnapshot(), animated: false)
        
        updateTheme()
    }
    
    func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        let dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [unowned self] tableView, indexPath, item in
            
            switch item {
            case .baseCurrency:
                // Base currency and tiny tokens
                let cell = tableView.dequeueReusableCell(withIdentifier: "baseCurrencyCell",
                                                         for: indexPath) as! AssetsAndActivityBaseCurrencyCell
                cell.configure(isInModal: isModal, baseCurrency: baseCurrency, onBaseCurrencyTap: { [weak self] in
                    guard let self else { return }
                    navigationController?.pushViewController(BaseCurrencyVC(isModal: isModal), animated: true)
                })
                return cell
                
            case .hiddenNfts:
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                cell.configurationUpdateHandler = { cell, state in
                    cell.contentConfiguration = UIHostingConfiguration {
                        HStack(spacing: 0) {
                            Text(lang("Hidden NFTs"))
                            Spacer()
                            Text("\(NftStore.currentAccountHiddenNftsCount)")
                                .padding(.horizontal, 8)
                                .foregroundStyle(Color(WTheme.secondaryLabel))
                            Image.airBundle("RightArrowIcon")
                                .renderingMode(.template)
                                .foregroundStyle(Color(WTheme.secondaryLabel))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background {
                        ZStack {
                            Color(WTheme.groupedItem)
                            Color.clear
                                .highlightBackground(state.isHighlighted)
                        }
                    }
                }
                return cell
                
            case .hideNoCost:
                let cell = tableView.dequeueReusableCell(withIdentifier: "hideNoCostTokensCell",
                                                         for: indexPath) as! AssetsAndActivityHideNoCostCell
                cell.configure(isInModal: isModal) { [weak self] hideNoCost in
                    guard let self else { return }
                    processorQueue.async(flags: .barrier) {
                        guard let data = AccountStore.currentAccountAssetsAndActivityData else {return}
                        AccountStore.setAssetsAndActivityData(accountId: AccountStore.accountId!, value: data)
                    }
                }
                return cell
                
            case .addToken:
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                cell.configurationUpdateHandler = { cell, state in
                    cell.contentConfiguration = UIHostingConfiguration {
                        HStack(spacing: 0) {
                            Image(systemName: "plus")
                                .frame(width: 40)
                                .padding(.leading, 16)
                                .padding(.trailing, 12)
                            Text(lang("Add Token"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color(WTheme.tint))
                    }
                    .background {
                        ZStack {
                            Color(WTheme.groupedItem)
                            Color.clear
                                .highlightBackground(state.isHighlighted)
                        }
                    }
                    .margins(.leading, 0)
                }
                cell.separatorInset.left = 68
                return cell
                
            case .token(let tokenSlug):
                let token = TokenStore.tokens[tokenSlug]
                let cell = tableView.dequeueReusableCell(withIdentifier: "tokenCell",
                                                         for: indexPath) as! AssetsAndActivityTokenCell
                if let token {
                    cell.configure(with: token,
                                   balance: BalanceStore.currentAccountBalances[token.slug] ?? 0,
                                   importedSlug: AccountStore.currentAccountAssetsAndActivityData?.importedSlugs.contains(tokenSlug) == true) { tokenSlug, visibility in
                        guard var data = AccountStore.currentAccountAssetsAndActivityData else {return}
                        if visibility {
                            data.alwaysHiddenSlugs.remove(tokenSlug)
                            data.alwaysShownSlugs.insert(tokenSlug)
                        } else {
                            data.alwaysShownSlugs.remove(tokenSlug)
                            data.alwaysHiddenSlugs.insert(tokenSlug)
                        }
                        AccountStore.setAssetsAndActivityData(accountId: AccountStore.accountId!, value: data)
                    }
                }
                cell.separatorInset.left = 68
                return cell
            }
        }
        return dataSource
    }
    
    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.baseCurrency])
        snapshot.appendItems([.baseCurrency])
        if NftStore.currentAccountHasHiddenNfts {
            snapshot.appendSections([.hiddenNfts])
            snapshot.appendItems([.hiddenNfts])
        }
        snapshot.appendSections([.hideNoCost])
        snapshot.appendItems([.hideNoCost])
        snapshot.appendSections([.tokens])
        snapshot.appendItems([.addToken])
        let tokens = tokensToDisplay.map { Item.token($0) }
        snapshot.appendItems(tokens)
        snapshot.reconfigureItems(tokens)
        return snapshot
    }
    
    func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, animated: Bool) {
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
    
    public override func updateTheme() {
        let backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground
        view.backgroundColor = backgroundColor
        tableView.backgroundColor = backgroundColor
        tokensHeaderLabel.textColor = WTheme.secondaryLabel
        addTokenIcon.tintColor = WTheme.tint
        addTokenSeparator.backgroundColor = WTheme.separator
        addTokenView.highlightBackgroundColor = WTheme.highlight
        addTokenView.backgroundColor = WTheme.groupedItem
    }
    
    public override func scrollToTop(animated: Bool) {
        tableView?.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }
    
    private var tokensHeaderLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.text = lang("YOUR TOKENS")
        return lbl
    }()
    
    private var addTokenIcon: UIImageView = {
        let img = UIImageView(image: UIImage(systemName: "plus"))
        img.translatesAutoresizingMaskIntoConstraints = false
        img.contentMode = .center
        return img
    }()
    
    private var addTokenLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        lbl.text = lang("Add Token")
        return lbl
    }()
    
    private var addTokenSeparator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 0.33)
        ])
        return v
    }()
    
    private lazy var addTokenView: WHighlightView = {
        let v = WHighlightView()
        v.addSubview(addTokenIcon)
        v.addSubview(addTokenLabel)
        v.addSubview(addTokenSeparator)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 10
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        NSLayoutConstraint.activate([
            addTokenIcon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            addTokenIcon.widthAnchor.constraint(equalToConstant: 24),
            addTokenIcon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            addTokenLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            addTokenLabel.leadingAnchor.constraint(equalTo: addTokenIcon.trailingAnchor, constant: 20),
            addTokenSeparator.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            addTokenSeparator.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            addTokenSeparator.leadingAnchor.constraint(equalTo: addTokenLabel.leadingAnchor),
            v.heightAnchor.constraint(equalToConstant: 44)
        ])
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addTokenPressed)))
        return v
    }()
    
    private lazy var tokensHeaderView: UIView = {
        let v = UIView()
        v.addSubview(tokensHeaderLabel)
        NSLayoutConstraint.activate([
            tokensHeaderLabel.topAnchor.constraint(equalTo: v.topAnchor, constant: 21),
            tokensHeaderLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            tokensHeaderLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: 16),
            tokensHeaderLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }()
    
    @objc func addTokenPressed() {
        let tokenSelectionVC = TokenSelectionVC(
            showMyAssets: false,
            title: lang("Add Token"),
            delegate: self,
            isModal: isModal,
            onlyTonChain: true
        )
        navigationController?.pushViewController(tokenSelectionVC, animated: true)
    }
    
    func importedTokenRemoved(tokenSlug: String) {
        guard var data = AccountStore.currentAccountAssetsAndActivityData else { return }
        data.importedSlugs.remove(tokenSlug)
        AccountStore.setAssetsAndActivityData(accountId: AccountStore.accountId!, value: data)
        applySnapshot(makeSnapshot(), animated: true)
    }
}

extension AssetsAndActivityVC: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch section {
        case 2:
            return tokensHeaderView
        default:
            let v = UIView()
            v.backgroundColor = .clear
            return v
        }
    }
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let id = dataSource.sectionIdentifier(for: section)
        switch id {
        case .baseCurrency:
            return 16
        case .hiddenNfts:
            return 16
        case .hideNoCost:
            return 0
        case .tokens:
            return 16
        case nil:
            fatalError()
        }
    }
    
    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .addToken, .hiddenNfts:
            return indexPath
        case .baseCurrency, .hideNoCost, .token, nil:
            return nil
        }
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let identifier = dataSource.itemIdentifier(for: indexPath) {
            switch identifier {
            case .baseCurrency, .hideNoCost, .token:
                break
            case .hiddenNfts:
                AppActions.showHiddenNfts()
            case .addToken:
                addTokenPressed()
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
    }
    
    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .token(let tokenSlug) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        if let prefs = AccountStore.currentAccountAssetsAndActivityData, prefs.importedSlugs.contains(tokenSlug) {
            let deleteAction = UIContextualAction(style: .destructive, title: lang("Remove")) { [weak self] _, _, callback in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    callback(true)
                }
                if let cell = self?.tableView.cellForRow(at: indexPath) as? AssetsAndActivityTokenCell {
                    cell.ignoreFutureUpdatesForSlug(tokenSlug)
                }
                self?.importedTokenRemoved(tokenSlug: tokenSlug)
            }
            let actions = UISwipeActionsConfiguration(actions: [deleteAction])
            actions.performsFirstActionWithFullSwipe = true
            return actions
        }
        return nil
    }
}

extension AssetsAndActivityVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .baseCurrencyChanged:
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([.baseCurrency])
            applySnapshot(snapshot, animated: true)
        case .balanceChanged:
            if TokenStore.tokens[TONCOIN_SLUG]?.price?.nilIfZero != nil {
                applySnapshot(makeSnapshot(), animated: true)
            } else {
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(snapshot.itemIdentifiers)
                applySnapshot(snapshot, animated: true)
            }
        case .nftsChanged(let accountId):
            if accountId == AccountStore.accountId {
                applySnapshot(makeSnapshot(), animated: true)
            }
        default:
            break
        }
    }
}

extension AssetsAndActivityVC: TokenSelectionVCDelegate {
    public func didSelect(token: WalletCore.MTokenBalance) {
    }
    
    public func didSelect(token: WalletCore.ApiToken) {
        guard var data = AccountStore.currentAccountAssetsAndActivityData else {return}
        data.deletedSlugs = data.deletedSlugs.filter({ it in
            it != token.slug
        })
        if !tokensToDisplay.contains(token.slug) {
            // Token is not in the list, even after removing it from deleted tokens, so add it to manually added ones.
            data.importedSlugs.insert(token.slug)
        }
        AccountStore.setAssetsAndActivityData(accountId: AccountStore.accountId!, value: data)
        applySnapshot(makeSnapshot(), animated: true)
    }
}
