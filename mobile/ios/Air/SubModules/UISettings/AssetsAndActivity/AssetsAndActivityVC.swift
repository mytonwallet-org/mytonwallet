//
//  AssetsAndActivityVC.swift
//  UISettings
//
//  Created by Sina on 7/4/24.
//

import Foundation
import OrderedCollections
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

// <<<<<<< HEAD
public class AssetsAndActivityVC: WViewController {
    @AccountContext(source: .current)
    private var account: MAccount
    private var assetsAndActivityData: MAssetsAndActivityData {
        AccountStore.assetsAndActivityData(forAccountID: account.id) ?? .empty
// =======
// public class AssetsAndActivityVC: SettingsBaseVC {
//     
//     enum Section {
//         case baseCurrency
//         case hiddenNfts
//         case hideNoCost
//         case tokens
// >>>>>>> master
    }
    private var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }

    private let tableView: UITableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var dataSource: UITableViewDiffableDataSource<Section, Item> = makeDataSource()
    
    private let tokensHeaderLabel: UILabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = .systemFont(ofSize: 13)
        $0.text = lang("My Tokens")
    }

    private let addTokenIcon: UIImageView = configured(object: UIImageView(image: UIImage(systemName: "plus"))) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.contentMode = .center
    }

    private let addTokenLabel: UILabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = .systemFont(ofSize: 17)
        $0.text = lang("Add Token")
    }

    private let addTokenSeparator: UIView = configured(object: UIView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([$0.heightAnchor.constraint(equalToConstant: 0.33)])
    }
    
    private lazy var addTokenView: WHighlightView = {
        let v = WHighlightView()
        v.addSubview(addTokenIcon)
        v.addSubview(addTokenLabel)
        v.addSubview(addTokenSeparator)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = S.insetSectionCornerRadius
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
            v.heightAnchor.constraint(equalToConstant: S.sectionItemHeight),
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

    private lazy var isModal = navigationController?.viewControllers.count ?? 1 == 1
    private let queue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background")
    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background_processor")

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        WalletCoreData.add(eventObserver: self)
    }
    
    private var tokensToDisplay: OrderedDictionary<TokenID, ApiToken> {
        let account = account
        let balances = $account.balances
        
        let tokenIDs = mutate(value: Set<TokenID>()) { ids in
            let balanceIDs = balances.keys.lazy.map { TokenID(slug: $0, isStaking: false) }
            ids.formUnion(balanceIDs)
            
            let stakings = StakingStore.stakingData(forAccountID: account.id)?.stateById.values.lazy
                .filter { stakingState in getFullStakingBalance(state: stakingState) > 0 }
                .map { stakingState in  stakingState.tokenSlug }
            
            if let stakings {
                let walletTokenBalanceIDs = stakings.map { TokenID(slug: $0, isStaking: true) }
                ids.formUnion(walletTokenBalanceIDs)
            }
            
            assetsAndActivityData.importedSlugs.forEach {
                ids.insert(TokenID(slug: $0, isStaking: false))
            }
        }
        
        let tokenStoreTokens = TokenStore.tokens
        var apiTokens = tokenIDs.compactMap { tokenID -> (TokenID, ApiToken)? in
            if let apiToken = tokenStoreTokens[tokenID.slug] {
                return account.supports(chain: apiToken.chain) ? (tokenID, apiToken) : nil
            } else {
                Log.shared.fault("Token with id \(tokenID) not found in TokenStore")
                return nil
            }
        }
        
        MTokenBalance.sortForUI(apiTokens: &apiTokens, balances: balances)
        let dict = OrderedDictionary<TokenID, ApiToken>(uniqueKeysWithValues: apiTokens)
        return dict
    }

    private func setupViews() {
        title = lang("Assets & Activity")

        let tableViewBackgroundView = UIView()
        tableViewBackgroundView.backgroundColor = .clear
        tableView.backgroundView = tableViewBackgroundView
        tableView.backgroundColor = .clear
        tableView.separatorColor = WTheme.separator
        tableView.register(AssetsAndActivityBaseCurrencyCell.self, forCellReuseIdentifier: "baseCurrencyCell")
        tableView.register(AssetsAndActivityHideNoCostCell.self, forCellReuseIdentifier: "hideNoCostTokensCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(AssetsAndActivityTokenCell.self, forCellReuseIdentifier: "tokenCell")
        tableView.delegate = self

        tableView.dataSource = dataSource
        tableView.delaysContentTouches = false

        view.addStretchedToBounds(subview: tableView, insets: UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0))

        addNavigationBar(navHeight: isModal ? 56 : 40,
                         topOffset: isModal ? 0 : -5,
                         title: title,
                         closeIcon: isModal,
                         addBackButton: isModal ? nil : { [weak self] in
                             guard let self else { return }
                             navigationController?.popViewController(animated: true)
                         })
        tableView.contentInset.top = navigationBarHeight
        tableView.verticalScrollIndicatorInsets.top = navigationBarHeight
        tableView.contentOffset = .init(x: 0, y: -navigationBarHeight)

        applySnapshot(makeSnapshot(), animated: false)

        updateTheme()
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        let dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [unowned self] tableView, indexPath, item in
            let accountId = self.account.id
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
                            Text("\(NftStore.getAccountHiddenNftsCount(accountId: accountId))")
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
                cell.configure(isInModal: isModal) { [weak self] _ in
                    guard let self else { return }
                    processorQueue.async(flags: .barrier) {
//                        let data = self.assetsAndActivityData
//                        AccountStore.updateAssetsAndActivityData(data, forAccountID: accountId)
                        // WalletCoreData.notify(event: .assetsAndActivityDataUpdated) ?
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

            case let .token(tokenID, token):
                let token = token.wrappedValue
                let cell = tableView.dequeueReusableCell(withIdentifier: "tokenCell",
                                                         for: indexPath) as! AssetsAndActivityTokenCell
                let isHidden = assetsAndActivityData.isTokenHidden(slug: tokenID.slug, isStaking: tokenID.isStaking)
                cell.configure(with: token,
                               isStaking: tokenID.isStaking,
                               balance: $account.balances[token.slug] ?? 0,
                               importedSlug: assetsAndActivityData.importedSlugs.contains(token.slug),
                               isHidden: isHidden) { tokenSlug, isVisible in
                    AccountStore.updateAssetsAndActivityData(forAccountID: accountId, update: { settings in
                        settings.saveTokenHidden(slug: tokenSlug, isStaking: tokenID.isStaking, isHidden: !isVisible)
                    })
                }
                cell.separatorInset.left = 68
                return cell
            }
        }
        return dataSource
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.baseCurrency])
        snapshot.appendItems([.baseCurrency])
        if NftStore.getAccountHasHiddenNfts(accountId: account.id) {
            snapshot.appendSections([.hiddenNfts])
            snapshot.appendItems([.hiddenNfts])
        }
        snapshot.appendSections([.hideNoCost])
        snapshot.appendItems([.hideNoCost])
        snapshot.appendSections([.tokens])
        snapshot.appendItems([.addToken])
        let tokens = tokensToDisplay.map { Item.token(tokenID: $0, token: HashableExcluded($1)) }
        snapshot.appendItems(tokens)
        snapshot.reconfigureItems(tokens)
        return snapshot
    }

    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, animated: Bool) {
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

    public override func viewWillLayoutSubviews() {
        // prevent unwanted animation on iOS 26
        UIView.performWithoutAnimation {
            tableView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }

    public override func scrollToTop(animated: Bool) {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }

    @objc private func addTokenPressed() {
        let tokenSelectionVC = TokenSelectionVC(showMyAssets: false,
                                                title: lang("Add Token"),
                                                delegate: self,
                                                isModal: isModal,
                                                onlySupportedChains: true)
        navigationController?.pushViewController(tokenSelectionVC, animated: true)
    }

    private func removeImportedToken(tokenSlug: String) {
        AccountStore.updateAssetsAndActivityData(forAccountID: account.id, update: { settings in
            settings.removeImportedToken(slug: tokenSlug)
        })
        applySnapshot(makeSnapshot(), animated: true)
    }
}

extension AssetsAndActivityVC: UITableViewDelegate {
    public func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch section {
        case 2: tokensHeaderView
        default: configured(object: UIView()) { $0.backgroundColor = .clear }
        }
    }

    public func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let id = dataSource.sectionIdentifier(for: section)
        return switch id {
        case .baseCurrency: 16
        case .hiddenNfts: 16
        case .hideNoCost: 0
        case .tokens: 16
        case nil: 0
        }
    }

    public func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .hiddenNfts: S.sectionItemHeight
        default: UITableView.automaticDimension
        }
    }

    public func tableView(_: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
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
                AppActions.showHiddenNfts(accountSource: .current)
            case .addToken:
                addTokenPressed()
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
    }

    public func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case let .token(_, wrappedToken) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let token = wrappedToken.wrappedValue
        
        if assetsAndActivityData.importedSlugs.contains(token.slug), ($account.balances[token.slug] ?? .zero) == 0 {
            let deleteAction = UIContextualAction(style: .destructive, title: lang("Remove")) { [weak self] _, _, callback in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { callback(true) }
                if let cell = self?.tableView.cellForRow(at: indexPath) as? AssetsAndActivityTokenCell {
                    cell.ignoreFutureUpdatesForSlug(token.slug)
                }
                self?.removeImportedToken(tokenSlug: token.slug)
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
            if accountId == account.id {
                applySnapshot(makeSnapshot(), animated: true)
            }
        default:
            break
        }
    }
}

extension AssetsAndActivityVC: TokenSelectionVCDelegate {
    public func didSelect(token _: WalletCore.MTokenBalance) {}

    public func didSelect(token selectedToken: WalletCore.ApiToken) {
        applySnapshot(makeSnapshot(), animated: true)
    }
}

extension AssetsAndActivityVC {
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
        case token(tokenID: TokenID, token: HashableExcluded<ApiToken>)
    }
}
