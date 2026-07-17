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

public class AssetsAndActivityVC: WViewController {
    @AccountContext(source: .current)
    private var account: MAccount
    private var assetsAndActivityData: MAssetsAndActivityData {
        AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty
    }
    private var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }
    
    private enum Section: Sendable {
        case baseCurrency
        case hiddenNfts
        case hideNoCost
        case tokens
    }

    private enum Item: Equatable, Hashable, Sendable {
        case baseCurrency
        case hideTinyTransfers
        case hiddenNfts
        case hideNoCost
        case addToken
        case token(tokenID: TokenID, token: HashableExcluded<ApiToken>)
    }

    private lazy var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, Item> = makeDataSource()

    private lazy var isModal = navigationController?.viewControllers.count ?? 1 == 1
    private let queue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background")
    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.assetsAndActivity_vc_background_processor")

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }

    private var tokensToDisplay: OrderedDictionary<TokenID, ApiToken> {
        let account = account
        let balances = $account.balances

        let tokenIDs = mutate(value: Set<TokenID>()) { ids in
            let balanceIDs = balances.keys.lazy.map { TokenID(slug: $0, isStaking: false) }
            ids.formUnion(balanceIDs)

            if let walletTokenIDs = $account.walletTokens?.map({ TokenID(slug: $0.tokenSlug, isStaking: false) }) {
                ids.formUnion(walletTokenIDs)
            }

            let stakings = StakingStore.stakingData(accountId: account.id)?.stateById.values.lazy
                .filter { stakingState in getFullStakingBalance(state: stakingState) > 0 }
                .map { stakingState in stakingState.tokenSlug }

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

        MTokenBalance.sortForUI(apiTokens: &apiTokens,
                                balances: balances,
                                defaultTokenSlugs: ApiToken.defaultSlugs(forNetwork: account.network, account: account),
                                importedTokenSlugs: assetsAndActivityData.importedSlugs)
        let dict = OrderedDictionary<TokenID, ApiToken>(uniqueKeysWithValues: apiTokens)
        return dict
    }

    private func setupViews() {
        title = lang("Assets & Activity")
        addCloseNavigationItemIfNeeded()
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = dataSource
        collectionView.delaysContentTouches = false
        view.addStretchedToBounds(subview: collectionView, insets: UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0))
        applySnapshot(makeSnapshot(), animated: false)
        updateTheme()
    }

    private func makeLayout() -> UICollectionViewLayout {
        var tokensListConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        tokensListConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActionsConfiguration(for: indexPath)
        }

        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else { return nil }
            let sectionId = self.dataSource.sectionIdentifier(for: sectionIndex)
            var listConfig = sectionId == .tokens
                ? tokensListConfig
                : UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            if sectionId == .baseCurrency || sectionId == .hideNoCost {
                listConfig.footerMode = .supplementary
            }
            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.contentInsets.top = 16
            return section
        }
    }

    private func swipeActionsConfiguration(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case let .token(_, wrappedToken) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let token = wrappedToken.wrappedValue
        guard assetsAndActivityData.importedSlugs.contains(token.slug),
              ($account.balances[token.slug] ?? .zero) == 0 else { return nil }
        let deleteAction = UIContextualAction(style: .destructive, title: lang("Remove")) { [weak self] _, _, callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { callback(true) }
            if let cell = self?.collectionView.cellForItem(at: indexPath) as? AssetsAndActivityTokenCell {
                cell.ignoreFutureUpdatesForSlug(token.slug)
            }
            self?.removeImportedToken(tokenSlug: token.slug)
        }
        let config = UISwipeActionsConfiguration(actions: [deleteAction])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let baseCurrencyReg = UICollectionView.CellRegistration<SimpleGroupCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.title = lang("Base Currency")
            cell.accessoryView = SimpleGroupCell.TitledDisclosureAccessory(text: baseCurrency.symbol)
        }

        let hideTinyTransfersReg = UICollectionView.CellRegistration<SimpleGroupCell, Item> { cell, _, _ in
            cell.title = lang("Hide Tiny Transfers")
            cell.isSelectable = false
            cell.configureSwitchAccessory(isOn: AppStorageHelper.hideTinyTransfers) { isOn in
                AppStorageHelper.hideTinyTransfers = isOn
                WalletCoreData.notify(event: .hideTinyTransfersChanged)
            }
        }

        let hideNoCostReg = UICollectionView.CellRegistration<SimpleGroupCell, Item> { cell, _, _ in
            cell.title = lang("Hide Tokens With No Cost")
            cell.isSelectable = false
            cell.configureSwitchAccessory(isOn: AppStorageHelper.hideNoCostTokens) { isOn in
                AppStorageHelper.hideNoCostTokens = isOn
            }
        }

        let hiddenNftsReg = UICollectionView.CellRegistration<SimpleGroupCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            let accountId = account.id
            let count = NftStore.getAccountHiddenNftsCount(accountId: accountId)
            cell.title = lang("Hidden NFTs")
            cell.accessoryView = SimpleGroupCell.TitledDisclosureAccessory(text: count > 0 ? "\(count)" : nil)
        }

        let tokenReg = UICollectionView.CellRegistration<AssetsAndActivityTokenCell, Item> { [weak self] cell, _, item in
            guard let self, case let .token(tokenID, wrappedToken) = item else { return }
            let token = wrappedToken.wrappedValue
            let accountId = self.account.id
            let tokenSlug = tokenID.slug
            let isStaking = tokenID.isStaking
            let isHidden = assetsAndActivityData.isTokenHidden(slug: tokenSlug, isStaking: isStaking)
            cell.configure(with: token,
                           isStaking: isStaking,
                           balance: $account.balances[token.slug] ?? 0,
                           importedSlug: assetsAndActivityData.importedSlugs.contains(token.slug),
                           isHidden: isHidden) { tokenSlug, isVisible in
                AssetsAndActivityDataStore.update(accountId: accountId, update: { settings in
                    settings.saveTokenHidden(slug: tokenSlug, isStaking: isStaking, isHidden: !isVisible)
                })
            }
        }

        let listCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            switch item {
            case .addToken:
                cell.configurationUpdateHandler = { cell, state in
                    cell.contentConfiguration = UIHostingConfiguration {
                        HStack(spacing: 0) {
                            Image(systemName: "plus")
                                .frame(width: 40)
                                .padding(.leading, 12)
                                .padding(.trailing, 10)
                            Text(lang("Add Token"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.tint)
                    }
                    .background {
                        ZStack {
                            Color.air.groupedItem
                            Color.clear.highlightBackground(state.isHighlighted)
                        }
                    }
                    .margins(.leading, 0)
                }
            default:
                break
            }
        }

        let ds = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .baseCurrency:
                return collectionView.dequeueConfiguredReusableCell(using: baseCurrencyReg, for: indexPath, item: item)
            case .hideTinyTransfers:
                return collectionView.dequeueConfiguredReusableCell(using: hideTinyTransfersReg, for: indexPath, item: item)
            case .hiddenNfts:
                return collectionView.dequeueConfiguredReusableCell(using: hiddenNftsReg, for: indexPath, item: item)
            case .addToken:
                return collectionView.dequeueConfiguredReusableCell(using: listCellReg, for: indexPath, item: item)
            case .hideNoCost:
                return collectionView.dequeueConfiguredReusableCell(using: hideNoCostReg, for: indexPath, item: item)
            case .token:
                return collectionView.dequeueConfiguredReusableCell(using: tokenReg, for: indexPath, item: item)
            }
        }
        
        let baseCurrencyFooterReg = UICollectionView.SupplementaryRegistration<SimpleGroupSectionFooter>(elementKind: UICollectionView.elementKindSectionFooter) { view, _, _ in
            view.text = lang("Don’t show transactions of less than $0.01. Such small transactions are often used for spam and scam.")
        }
        
        let hideNoCostFooterReg = UICollectionView.SupplementaryRegistration<SimpleGroupSectionFooter>(elementKind: UICollectionView.elementKindSectionFooter) { view, _, _ in
            view.text = lang("Don’t show tokens on your account with value less than $0.01. You can also selectively enable and disable particular tokens using the list below.")
        }
        
        ds.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionFooter else { return nil }
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .baseCurrency:
                return collectionView.dequeueConfiguredReusableSupplementary(using: baseCurrencyFooterReg, for: indexPath)
            case .hideNoCost:
                return collectionView.dequeueConfiguredReusableSupplementary(using: hideNoCostFooterReg, for: indexPath)
            default:
                return nil
            }
        }
        return ds
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.baseCurrency])
        snapshot.appendItems([.baseCurrency, .hideTinyTransfers])
        if NftStore.getAccountHasHiddenNfts(accountId: account.id) {
            snapshot.appendSections([.hiddenNfts])
            snapshot.appendItems([.hiddenNfts])
            snapshot.reconfigureItems([.hiddenNfts])
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

    private func updateTheme() {
        let backgroundColor = isModal ? UIColor.air.sheetBackground : UIColor.air.groupedBackground
        view.backgroundColor = backgroundColor
        collectionView.backgroundColor = backgroundColor
    }

    public override func viewWillLayoutSubviews() {
        // prevent unwanted animation on iOS 26
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }

    public override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    @objc private func addTokenPressed() {
        let tokenSelectionVC = TokenSelectionVC(showMyAssets: false,
                                                title: lang("Add Token"),
                                                delegate: nil,
                                                isModal: isModal,
                                                onlySupportedChains: true)
        navigationController?.pushViewController(tokenSelectionVC, animated: true)
    }

    private func removeImportedToken(tokenSlug: String) {
        AssetsAndActivityDataStore.update(accountId: account.id, update: { settings in
            settings.removeImportedToken(slug: tokenSlug)
        })
    }
}

extension AssetsAndActivityVC: UICollectionViewDelegate {
    public func collectionView(_: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .hideNoCost, .hideTinyTransfers: return false
        case .baseCurrency, .addToken, .hiddenNfts, .token, nil: return true
        }
    }

    public func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .baseCurrency, .addToken, .hiddenNfts: return true
        case .hideNoCost, .hideTinyTransfers, .token, nil: return false
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let identifier = dataSource.itemIdentifier(for: indexPath) {
            switch identifier {
            case .hideNoCost, .hideTinyTransfers, .token:
                break
            case .baseCurrency:
                navigationController?.pushViewController(BaseCurrencyVC(isModal: isModal), animated: true)
            case .hiddenNfts:
                AppActions.showHiddenNfts(accountSource: .current)
            case .addToken:
                addTokenPressed()
            }
        }
        collectionView.deselectItem(at: indexPath, animated: true)
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
            applySnapshot(makeSnapshot(), animated: true)
        case .nftsChanged(let accountId):
            if accountId == account.id {
                applySnapshot(makeSnapshot(), animated: true)
            }
        case .assetsAndActivityDataUpdated:
            applySnapshot(makeSnapshot(), animated: true)
        default:
            break
        }
    }
}
