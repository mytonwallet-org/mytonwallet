//
//  NftsVC.swift
//  UIAssets
//
//  Created by Sina on 3/27/24.
//

import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import OrderedCollections

private let log = Log("NftsVC")

@MainActor
public class NftsVC: WViewController, WSegmentedControllerContent, Sendable, UIAdaptivePresentationControllerDelegate {
    
    private enum Section {
        case renewalWarning
        case main
        case placeholder
        case actions
    }
    
    private enum Action: Hashable {
        case showAll(title: String, count: Int)
    }
    
    private enum Row: Hashable {
        case renewalWarning(NftRenewDomainWarningContent)
        case placeholder
        case nft(String)
        case action(Action)
    }

    private enum DomainRenewalWarningSessionState {
        @MainActor static var ignoredAddresses = Set<String>()
    }
    
    public enum LayoutMode {
        /// Compact 2x3-like layout used inside wallet card sections.
        case compact
        /// Large compact layout used in split-home card sections.
        case compactLarge
        /// Full-height scrolling grid used by embedded/fullscreen screens.
        case regular

        var isCompact: Bool { self != .regular }
    }
    
    @AccountContext internal var account: MAccount
        
    public var onScroll: ((CGFloat) -> Void)?
        
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?
    private var reorderController: ReorderableCollectionViewController!
    
    internal let filter: NftCollectionFilter
    
    private let layoutMode: LayoutMode
    private let canOpenCollection: Bool
    private weak var manager: NftsVCManager?

    private var layoutChangeID: LayoutGeometry.LayoutChangeID?
    private let layoutGeometry: LayoutGeometry
    private var isWalletAssetsEmptyStateAnimationActive = false
    private var walletAssetsEmptyStateAnimationSessionID = 0
    private var pendingInteractiveSwitchAccountId: String?
    
    private var contextMenuExtraBlurView: UIView?
    
    var inSelectionMode: Bool { selectedIds != nil }
    private var selectedIds: Set<String>?
    private var selectionToolbar: NftMultiSelectToolbar?
    private var selectionToolbarBottomConstraint: NSLayoutConstraint?
        
    public init(accountSource: AccountSource, manager: NftsVCManager?, layoutMode: LayoutMode, canOpenCollection: Bool = true, filter: NftCollectionFilter) {
        self._account = AccountContext(source: accountSource)
        self.filter = filter
        self.layoutMode = layoutMode
        self.manager = manager
        self.layoutGeometry = LayoutGeometry(layoutMode: layoutMode)
        self.canOpenCollection = canOpenCollection

        super.init(nibName: nil, bundle: nil)
        
        manager?.addController(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
            
    private func resolveTonDomain(for nft: ApiNft) -> NftDetailsItem.TonDomain? {
        guard let expirationDays = $account.domains.expirationWarningDays(for: nft) else {
            return nil
        }
        return .init(
            expirationDays: expirationDays,
            canRenew: account.type == .mnemonic
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayoutIfNeeded()
    }
    
    private var displayNfts: OrderedDictionary<String, DisplayNft>?
    private var domainRenewalWarning: NftRenewDomainWarningContent?
    private(set) internal var allShownNftsCount: Int = 0

    private func setupViews() {
        title = filter.displayTitle
        let compactMode = layoutMode.isCompact
        
        let collectionViewClass = compactMode ? _NoInsetsCollectionView.self : UICollectionView.self
        collectionView = collectionViewClass.init(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let constraints: [NSLayoutConstraint] = [
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        if compactMode {
            collectionView.isScrollEnabled = false
            collectionView.showsVerticalScrollIndicator = false
            collectionView.showsHorizontalScrollIndicator = false
        } else {
            collectionView.alwaysBounceVertical = true
        }
        
        let nftCellRegistration = UICollectionView.CellRegistration<NftCell, String> { [weak self] cell, indexPath, nftId in
            guard let self else { return }
            let displayNft = displayNfts?[nftId] ?? NftStore.getAccountNfts(accountId: self.account.id)?[nftId]
            let tonDomain = displayNft.flatMap { self.resolveTonDomain(for: $0.nft) }
            cell.configure(
                nft: displayNft?.nft,
                compactMode: compactMode,
                domainExpirationText: tonDomain?.expirationText,
                isSelected: selectedIds?.contains(nftId)
            )
            cell.configurationUpdateHandler = { nftCell, state in
                nftCell.isHighlighted = state.isHighlighted
            }
            reorderController.updateCell(cell, indexPath: indexPath)
        }
        let placeholderCellRegistration = UICollectionView.CellRegistration<WalletAssetsEmptyCell, String> { [weak self] cell, _, _ in
            let shouldShowMarketplace = !ConfigStore.shared.shouldRestrictBuyNfts
            cell.configure(
                animationName: "animation_happy",
                title: lang("No NFTs yet"),
                description: shouldShowMarketplace ? lang("$nft_explore_offer") : nil,
                actionTitle: shouldShowMarketplace ? lang("Open %nft_marketplace%", arg1: NFT_MARKETPLACE_TITLE) : nil,
                height: WalletAssetsEmptyCell.collectiblesHeight,
                descriptionNumberOfLines: 3
            ) { [weak self] in
                self?.didTapOpenNftMarketplace()
            }
            self?.applyEmptyStateAnimation(to: cell)
        }
        let renewalWarningCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, NftRenewDomainWarningContent> { [weak self] cell, indexPath, itemIdentifier in
            guard let self else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                NftRenewDomainWarningView(
                    content: itemIdentifier,
                    onTap: { [weak self] in
                        self?.handleTap(on: itemIdentifier)
                    },
                    onClose: { [weak self] in
                        self?.handleClose(on: itemIdentifier)
                    }
                )
            }
            .background(Color.clear)
            .margins(.all, 0)
            cell.backgroundColor = .clear
        }
        let actionCellRegistration = UICollectionView.CellRegistration<WalletSeeAllCell, Action> { cell, _, itemIdentifier in
            switch itemIdentifier {
            case .showAll(let title, let count):
                cell.configureCollectibles(title: title, collectiblesCount: count)
            }
            cell.configurationUpdateHandler = { seeAllCell, state in
                seeAllCell.isHighlighted = state.isHighlighted
            }
        }
        
        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .renewalWarning(let content):
                collectionView.dequeueConfiguredReusableCell(using: renewalWarningCellRegistration, for: indexPath, item: content)
            case .nft(let nftId):
                collectionView.dequeueConfiguredReusableCell(using: nftCellRegistration, for: indexPath, item: nftId)
            case .action(let actionId):
                collectionView.dequeueConfiguredReusableCell(using: actionCellRegistration, for: indexPath, item: actionId)
            case .placeholder:
                collectionView.dequeueConfiguredReusableCell(using: placeholderCellRegistration, for: indexPath, item: "")
            }
        }
        self.dataSource = dataSource

        reorderController = ReorderableCollectionViewController(collectionView: collectionView)
        reorderController.scrollDirection = .vertical
        reorderController.delegate = self

        UIView.performWithoutAnimation {
            updateNfts(animated: false)
        }
        
        updateTheme()
    }
    
    private func applyLayoutIfNeeded() {
        let layoutChangeID = layoutGeometry.calcLayoutChangeID(
            itemCount: displayNfts?.count ?? 0,
            hasRenewalWarning: domainRenewalWarning != nil,
            collectionView: collectionView
        )
        if layoutChangeID != self.layoutChangeID {
            let shouldAnimate = self.layoutChangeID != nil && view.window != nil
            self.layoutChangeID = layoutChangeID
            collectionView.setCollectionViewLayout(makeLayout(), animated: shouldAnimate)
        }
    }
        
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let actionsSection: NSCollectionLayoutSection
        do {
            let (height, contentInsets) = layoutGeometry.calcActionsItemGeometry()
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            actionsSection = NSCollectionLayoutSection(group: group)
            actionsSection.contentInsets = contentInsets
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] idx, env in
            guard let self, let dataSource else { return nil }

            switch dataSource.sectionIdentifier(for: idx) {
            case .renewalWarning:
                let (height, contentInsets) = layoutGeometry.calcRenewalWarningGeometry(collectionView: collectionView)
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = contentInsets
                return section
            case .main:
                let itemCount = dataSource.snapshot().numberOfItems(inSection: .main)
                let (cellSize, contentInsets) = layoutGeometry.calcNftItemGeometry(
                    itemCount: itemCount,
                    collectionView: collectionView,
                    isRenewalWarningShown: domainRenewalWarning != nil
                )
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(cellSize.width), heightDimension: .estimated(cellSize.height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                group.interItemSpacing = .fixed(layoutGeometry.spacing)
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = contentInsets
                section.interGroupSpacing = layoutGeometry.spacing
                return section
            case .actions:
                return actionsSection
            case .placeholder:
                let (height, contentInsets) = layoutGeometry.calcPlaceholderItemGeometry(
                    collectionView: collectionView,
                    isRenewalWarningShown: domainRenewalWarning != nil
                )
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                let section3 = NSCollectionLayoutSection(group: group)
                section3.contentInsets = contentInsets
                return section3
            default:
                return nil
            }
        }
        return layout
    }
            
    public override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
    
    private func updateTheme() {
        view.backgroundColor = layoutMode.isCompact ? .air.groupedItem : .air.pickerBackground
        collectionView.backgroundColor = layoutMode.isCompact ? .air.groupedItem : .air.pickerBackground
    }
    
    public var scrollingView: UIScrollView? {
        return collectionView
    }
    
    private func updateNfts(animated: Bool = true) {
        guard dataSource != nil else { return }
        domainRenewalWarning = makeRenewalWarning()
        if var nfts = NftStore.getAccountShownNfts(accountId: account.id) {
            nfts = filter.apply(to: nfts)
            self.allShownNftsCount = nfts.count
            if layoutMode.isCompact {
                nfts = OrderedDictionary(uncheckedUniqueKeysWithValues: nfts.prefix(layoutGeometry.compactMaxVisibleItemCount))
            }
            self.displayNfts = nfts
        } else {
            self.displayNfts = nil
            self.allShownNftsCount = 0
        }

        applySnapshot(makeSnapshot(), animated: animated)
        updateVisibleEmptyStateAnimations()
        applyLayoutIfNeeded()
        
        if inSelectionMode, let selectedIds {
            let allIds = Set(displayNfts?.keys ?? [])
            let newSelection = selectedIds.filter { allIds.contains($0)}
            self.selectedIds = newSelection
        }
                
        notifyStateChange()
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()

        if let domainRenewalWarning {
            snapshot.appendSections([.renewalWarning])
            snapshot.appendItems([.renewalWarning(domainRenewalWarning)], toSection: .renewalWarning)
        }
        
        if let displayNfts {
            if displayNfts.isEmpty {
                snapshot.appendSections([.placeholder])
                snapshot.appendItems([.placeholder])
            } else {
                snapshot.appendSections([.main])
                snapshot.appendItems(displayNfts.keys.map { Row.nft($0) }, toSection: .main)
            }
            if layoutMode.isCompact && layoutGeometry.shouldShowShowAllAction(itemCount: allShownNftsCount) {
                snapshot.appendSections([.actions])
                let title = filter == .none
                    ? lang("Show All Collectibles")
                    : lang("Show All %1$@", arg1: filter.displayTitle)
                snapshot.appendItems([Row.action(.showAll(title: title, count: allShownNftsCount))], toSection: .actions)
            }
        }
        return snapshot
    }
        
    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool) {
        guard let dataSource else { return }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func persistNftOrder(from snapshot: NSDiffableDataSourceSnapshot<Section, Row>) {
        let orderedIds = OrderedSet(snapshot.itemIdentifiers(inSection: .main).compactMap { row -> String? in
            if case .nft(let id) = row { return id }
            return nil
        })
        NftStore.reorderNfts(accountId: account.id, orderedIdsHint: orderedIds)
    }
    
    public func calculateHeight(isHosted: Bool) -> CGFloat {
        loadViewIfNeeded()
    
        let displayedItemCount = displayNfts?.count ?? 0
        let isPlaceholderShown = displayNfts?.isEmpty == true
        let isActionShown = layoutMode.isCompact && layoutGeometry.shouldShowShowAllAction(itemCount: allShownNftsCount)

        if isHosted {
            guard layoutMode.isCompact else {
                return max(collectionView.bounds.height, view.bounds.height, 1)
            }
            if isPlaceholderShown {
                return layoutGeometry.calculateHeight(
                    itemCount: displayedItemCount,
                    isPlaceholderShown: isPlaceholderShown,
                    isActionShown: isActionShown,
                    isRenewalWarningShown: domainRenewalWarning != nil,
                    collectionView: collectionView
                )
            }
            return layoutGeometry.calculateHeight(
                itemCount: layoutGeometry.compactMaxVisibleItemCount,
                isPlaceholderShown: false,
                isActionShown: true,
                isRenewalWarningShown: domainRenewalWarning != nil,
                collectionView: collectionView
            )
        }

        return layoutGeometry.calculateHeight(
            itemCount: displayedItemCount,
            isPlaceholderShown: isPlaceholderShown,
            isActionShown: isActionShown,
            isRenewalWarningShown: domainRenewalWarning != nil,
            collectionView: collectionView
        )
    }
    public func switchAccountTo(accountId: String, animated: Bool) {
        pendingInteractiveSwitchAccountId = accountId
        $account.accountId = accountId
        updateNfts(animated: animated)
    }
    
    private func notifyStateChange() {
        manager?.notifyStateChange()
    }
        
    private func startSelectionInternally(preselected: Set<String>? = nil) {
        guard !inSelectionMode else { return }
        selectedIds = preselected ?? []
        collectionView.reloadData()
        manager?.startSelection(in: self)
    }

    internal func startSelection() {
        guard !inSelectionMode else { return }
        selectedIds = []
        collectionView.reloadData()
        notifyStateChange()
    }

    internal func stopSelection() {
        guard inSelectionMode else { return }
        selectedIds = nil
        collectionView.reloadData()
        notifyStateChange()
    }

    internal func toggleSelectAllNfts() {
        guard let allIds = displayNfts?.keys, let selectedIds else {
            assertionFailure()
            return
        }
        if selectedIds.count == allIds.count {
            self.selectedIds = []
        } else {
            self.selectedIds = Set(allIds)
        }
        collectionView.reloadData()
        notifyStateChange()
    }

    private func toggleSelection(nftId: String) {
        guard let selectedIds else {
            assertionFailure()
            return
        }
        
        if selectedIds.contains(nftId) {
            self.selectedIds?.remove(nftId)
        } else {
            self.selectedIds?.update(with: nftId)
        }
        
        if let dataSource {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([.nft(nftId)])
            dataSource.apply(snapshot, animatingDifferences: true)
        }
        
        notifyStateChange()
    }
    
    private func startReorderingInternally() {
        manager?.startReordering()
    }
    
    internal func startReordering() {
        guard !reorderController.isReordering else { return }
        reorderController.isReordering = true
        notifyStateChange()
    }
    
    internal func stopReordering(isCanceled: Bool) {
        guard isViewLoaded, let reorderController, reorderController.isReordering else { return }
        reorderController.isReordering = false
        notifyStateChange()
    }
    
    private func canStartDragOrOpenMenu() -> Bool {
        !inSelectionMode && manager?.state.editingState == nil
    }
}

extension NftsVC: ReorderableCollectionViewControllerDelegate {
    public func reorderController(_ controller: ReorderableCollectionViewController, canStartSystemDragForItemAt indexPath: IndexPath) -> Bool {
        return canStartDragOrOpenMenu()
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, canMoveItemAt indexPath: IndexPath) -> Bool {
        return dataSource?.sectionIdentifier(for: indexPath.section) == .main
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, moveItemAt sourceIndexPath: IndexPath,
                                  to destinationIndexPath: IndexPath) -> Bool {
        guard let dataSource, let displayNfts, !displayNfts.isEmpty,
              dataSource.sectionIdentifier(for: sourceIndexPath.section) == .main,
              dataSource.sectionIdentifier(for: destinationIndexPath.section) == .main else {
            return false
        }
        var snapshot = dataSource.snapshot()
        let mainItems = snapshot.itemIdentifiers(inSection: .main)
        guard sourceIndexPath.item < mainItems.count, destinationIndexPath.item <= mainItems.count, sourceIndexPath.item != destinationIndexPath.item else {
            return false
        }
        var reordered = Array(mainItems)
        let moved = reordered.remove(at: sourceIndexPath.item)
        reordered.insert(moved, at: destinationIndexPath.item)

        snapshot.deleteItems(mainItems)
        snapshot.appendItems(reordered, toSection: .main)

        let orderedIds = reordered.compactMap { row -> String? in
            if case .nft(let id) = row { return id }
            return nil
        }
        var newDisplayNfts: OrderedDictionary<String, DisplayNft> = [:]
        for id in orderedIds {
            if let value = displayNfts[id] {
                newDisplayNfts[id] = value
            }
        }
        self.displayNfts = newDisplayNfts
        persistNftOrder(from: snapshot)
        applySnapshot(snapshot, animated: true)
        return true
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, didChangeReorderingStateByExternalActor externalActor: Bool) {
        if !externalActor {
            startReorderingInternally()
        }
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
        
        switch id {
        case .renewalWarning:
            break
        case .nft(let nftId):
            if let nft = displayNfts?[nftId]?.nft {
                if inSelectionMode {
                    toggleSelection(nftId: nftId)
                } else {
                    let assetVC = NftDetailsVC(accountId: account.id, nft: nft, listContext: filter)
                    navigationController?.pushViewController(assetVC, animated: true)
                }
            }
        case .action(let actionId):
            if case .showAll = actionId {
                AppActions.showAssets(accountSource: $account.source, selectedTab: 1, collectionsFilter: filter)
            }
        case .placeholder:
            break
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
    }
            
    public func reorderController(_ controller: ReorderableCollectionViewController, contextMenuConfigurationForItemAt indexPath: IndexPath,
                                  point: CGPoint) -> UIContextMenuConfiguration? {
        guard canStartDragOrOpenMenu() else { return nil }
        guard let row = dataSource?.itemIdentifier(for: indexPath) else { return nil }
        guard case .nft(let nftId) = row, let nft = displayNfts?[nftId]?.nft else { return nil }
        
        let menu = UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
            return self.makeNftCellMenu(nft: nft)
        }
        return menu
    }
    
    private func makeNftCellMenu(nft: ApiNft) -> UIMenu {
        let accountId = account.id
        
        let accountSettings = $account.settings
        let domains = $account.domains

        let detailsSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            items += UIAction(title: lang("Details"), image: UIImage(systemName: "info.circle")) { [filter] _ in
                let assetVC = NftDetailsVC(accountId: accountId, nft: nft, listContext: filter)
                self.navigationController?.pushViewController(assetVC, animated: true)
            }
            detailsSection = UIMenu(title: "", options: .displayInline, children: items)
        }
            
        let installSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if let mtwCardId = nft.metadata?.mtwCardId {
                let isCurrent = mtwCardId == accountSettings.backgroundNft?.metadata?.mtwCardId
                if isCurrent {
                    items += UIAction(title: lang("Reset Card"), image: UIImage(systemName: "xmark.rectangle")) { _ in
                        accountSettings.setBackgroundNft(nil)
                    }
                } else {
                    items += UIAction(title: lang("Install Card"), image: .airBundle("MenuInstallCard26")) { _ in
                        accountSettings.setBackgroundNft(nft)
                        accountSettings.setAccentColorNft(nft)
                    }
                }
                let isCurrentAccent = mtwCardId == accountSettings.accentColorNft?.metadata?.mtwCardId
                if isCurrentAccent {
                    items += UIAction(title: lang("Reset Palette"), image: .airBundle("custom.paintbrush.badge.xmark")) { _ in
                        accountSettings.setAccentColorNft(nil)
                    }
                } else {
                    items += UIAction(title: lang("Apply Palette"), image: .airBundle("MenuBrush26")) { _ in
                        accountSettings.setAccentColorNft(nft)
                    }
                }
            }
            installSection = UIMenu(title: "", options: .displayInline, children: items)
        }
        
        let actionsSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if account.supportsSend {
                if nft.isOnSale {
                    items += UIAction(title: lang("Cannot be sent"), image: .airBundle("MenuSend26"), attributes: .disabled) { _ in
                    }
                } else {
                    items += UIAction(title: lang("Send"), image: .airBundle("MenuSend26")) { _ in
                        AppActions.showSend(accountContext: self.$account, prefilledValues: .init(mode: .sendNft, nfts: [nft]))
                    }
                }
            }
            if account.type == .mnemonic, nft.isTonDns, !nft.isOnSale {
                if domains.expirationByAddress[nft.address] != nil {
                    items += UIAction(title: lang("Renew"), image: .airBundle("MenuRenew26")) { _ in
                        AppActions.showRenewDomain(accountSource: .accountId(accountId), nftsToRenew: [nft.address])
                    }
                }
                let linkedAddress = domains.linkedAddressByAddress[nft.address]?.nilIfEmpty
                let title = linkedAddress == nil
                    ? lang("Link to Wallet")
                    : lang("Change Linked Wallet")
                items += UIAction(title: title, image: .airBundle("MenuLinkToWallet26")) { _ in
                    AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: nft.address)
                }
            }
            items += UIAction(title: lang("Hide"), image: .airBundle("MenuHide26")) { _ in
                NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
            }
            if account.supportsBurn, !nft.isOnSale {
                items += UIAction(title: lang("Burn"), image: .airBundle("MenuBurn26"), attributes: .destructive) { _ in
                    AppActions.showSend(accountContext: self.$account, prefilledValues: .init(mode: .burnNft, nfts: [nft]))
                }
            }
            actionsSection = UIMenu(title: "", options: .displayInline, children: items)
        }
        
        // Open-In section (currently nested into otherSection)
        let openInSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if nft.isOnFragment == true, let string = nft.metadata?.fragmentUrl?.nilIfEmpty, let url = URL(string: string) {
                items += UIAction(title: "Fragment", image: .airBundle("MenuFragment26")) { _ in
                    AppActions.openInBrowser(url)
                }
            }
            if nft.chain == .ton, !ConfigStore.shared.shouldRestrictBuyNfts {
                items += UIAction(title: "Getgems", image: .airBundle("MenuGetgems26")) { _ in
                    let url = ExplorerHelper.nftUrl(nft)
                    AppActions.openInBrowser(url)
                }
            }
            items += UIAction(title: ExplorerHelper.selectedExplorerName(for: nft.chain), image: .airBundle(ExplorerHelper.selectedExplorerMenuIconName(for: nft.chain))) { _ in
                let url = ExplorerHelper.explorerNftUrl(nft)
                AppActions.openInBrowser(url)
            }
            if let url = ExplorerHelper.tonDnsManagementUrl(nft) {
                items += UIAction(title: "TON Domains", image: .airBundle("MenuTonDomains26")) { _ in
                    AppActions.openInBrowser(url)
                }
            }
            openInSection = UIMenu(title: lang("Open in..."), image: UIImage(systemName: "globe"), children: items)
        }
                
        let otherSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if let collection = nft.collection, canOpenCollection {
                let collectionAction = UIAction(title: lang("Collection"), image: .airBundle("MenuCollection26")) { [weak self] _ in
                    guard let self else { return }
                    AppActions.showAssets(accountSource: self.$account.source, selectedTab: 1, collectionsFilter: .collection(collection))
                }
                items.append(collectionAction)
            }
            items += UIAction(title: lang("Share"), image: .airBundle("MenuShare26")) { _ in
                AppActions.shareUrl(ExplorerHelper.nftUrl(nft))
            }
            if !openInSection.children.isEmpty {
                items.append(openInSection)
            }
            otherSection = UIMenu(title: "", options: .displayInline, children: items)
        }
        
        let organizeSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if allShownNftsCount > 1 || layoutMode.isCompact {
                items += UIAction(title: lang("Reorder"), image: .airBundle("MenuReorder26")) { [weak self] _ in
                    self?.startReorderingInternally()
                }
            }
            
            items += UIAction(title: lang("Select"), image: .airBundle("MenuSelect26")) { [weak self] _ in
                self?.startSelectionInternally(preselected: [nft.id])
            }
            
            organizeSection = UIMenu(title: "", options: .displayInline, children: items)
        }
                    
        let sections = [detailsSection, installSection, actionsSection, otherSection, organizeSection].filter { !$0.children.isEmpty }
        return UIMenu(title: "", children: sections)
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview? {
        guard let cell = cell as? NftCell else { return nil }
        return .init(view: cell.imageContainerView, cornerRadius: NftCell.getCornerRadius(compactMode: layoutMode.isCompact))
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        contextMenuExtraBlurView?.removeFromSuperview()
        contextMenuExtraBlurView = ContextMenuBackdropBlur.show(in: view.window, animator: animator)
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        let blurView = contextMenuExtraBlurView
        contextMenuExtraBlurView = nil
        ContextMenuBackdropBlur.hide(blurView, animator: animator)
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, adjustPreviewFrame previewFrame: CGRect) -> CGRect {
        var result = previewFrame
        
        // In compact modes, the tiles are sandboxed within their own section.
        switch layoutMode {
        case .compact, .compactLarge:
            let insets = layoutGeometry.calcCompactModeNftInsets(
                itemCount: displayNfts?.count ?? 0,
                isRenewalWarningShown: domainRenewalWarning != nil,
                collectionView: collectionView
            )
            let bounds = collectionView.bounds.inset(by: insets)
            result = result.clamped(to: bounds)
        case .regular:
            break
        }
        
        return result
    }
}

extension NftsVC: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task { @MainActor in
            switch event {
            case .nftsChanged(let accountId):
                if accountId == self.account.id {
                    updateNfts()
                }
            case .updateAccountDomainData(let update):
                if update.accountId == self.account.id {
                    updateNfts()
                }
            case .accountChanged:
                if self.$account.source == .current {
                    let shouldSkipUpdate = pendingInteractiveSwitchAccountId == self.account.id
                    pendingInteractiveSwitchAccountId = nil
                    if !shouldSkipUpdate {
                        updateNfts()
                    }
                }
            default:
                break
            }
        }
    }
}

extension NftsVC {
    private var isShowingEmptyState: Bool {
        displayNfts?.isEmpty == true
    }

    private func applyEmptyStateAnimation(to cell: WalletAssetsEmptyCell) {
        cell.updateAnimationPlayback(
            isPlaying: isWalletAssetsEmptyStateAnimationActive && isShowingEmptyState,
            playbackSessionID: walletAssetsEmptyStateAnimationSessionID
        )
    }

    private func updateVisibleEmptyStateAnimations() {
        guard isViewLoaded, collectionView != nil else {
            return
        }
        collectionView.layoutIfNeeded()
        for case let cell as WalletAssetsEmptyCell in collectionView.visibleCells {
            applyEmptyStateAnimation(to: cell)
        }
    }

    func setWalletAssetsEmptyStateAnimationActive(_ isActive: Bool) {
        isWalletAssetsEmptyStateAnimationActive = isActive
        if isActive {
            walletAssetsEmptyStateAnimationSessionID += 1
        }
        updateVisibleEmptyStateAnimations()
    }

    private func didTapOpenNftMarketplace() {
        guard let url = URL(string: NFT_MARKETPLACE_URL) else {
            assertionFailure()
            return
        }
        AppActions.openInBrowser(url)
    }

    private var shouldShowRenewalWarning: Bool {
        guard !account.isView else {
            return false
        }

        switch filter {
        case .collection(let collection):
            return collection.address == ApiNft.TON_DNS_COLLECTION_ADDRESS
        case .none, .telegramGifts:
            return true
        }
    }

    private func makeRenewalWarning() -> NftRenewDomainWarningContent? {
        guard shouldShowRenewalWarning else {
            return nil
        }

        let domains = $account.domains
        let nftsForRenewal = domains.expiringForRenewalWarning(
            ignoredAddresses: DomainRenewalWarningSessionState.ignoredAddresses
        )
        guard !nftsForRenewal.isEmpty,
              let expireInDays = domains.renewalWarningExpirationDays(for: nftsForRenewal) else {
            return nil
        }

        let text: String
        if nftsForRenewal.count == 1 {
            let domainName = nftsForRenewal[0].displayName
            if expireInDays < 0 {
                text = lang("$domain_was_expired", arg1: domainName)
            } else {
                text = lang("$domain_expire", arg1: domainName, arg2: lang("$in_days", arg1: expireInDays))
            }
        } else if expireInDays < 0 {
            let expiredCount = domains.expiredForRenewalWarning(in: nftsForRenewal).count
            text = lang("$domains_was_expired", arg1: expiredCount)
        } else {
            text = lang("$domains_expire", arg1: lang("$in_days", arg1: expireInDays), arg2: nftsForRenewal.count)
        }

        return .init(
            addresses: nftsForRenewal.map(\.address),
            text: text
        )
    }

    private func handleTap(on renewalWarning: NftRenewDomainWarningContent) {
        AppActions.showRenewDomain(accountSource: $account.source, nftsToRenew: renewalWarning.addresses)
    }

    private func handleClose(on renewalWarning: NftRenewDomainWarningContent) {
        DomainRenewalWarningSessionState.ignoredAddresses.formUnion(renewalWarning.addresses)
        updateNfts()
    }
    
    internal func collectMultiSelectedNfts() -> [ApiNft]? {
        guard inSelectionMode, let selectedIds, let displayNfts else {
            assertionFailure()
            return nil
        }
        let result = displayNfts.keys.compactMap { id in
            selectedIds.contains(id) ? displayNfts[id]?.nft : nil
        }
        
        return result.isEmpty ? nil : result
    }
    
    internal func canSendOrBurnItems(nfts: [ApiNft]) -> Bool {
        guard !nfts.isEmpty else {
            assertionFailure()
            return false
        }
        
        // Single chain only
        let chains = Set(nfts.map(\.chain))
        if chains.count > 1 {
            AppActions.showToast(message: lang("$nft_batch_different_chains"))
            return false
        }
        
        // No onSale
        let hasOnSale = nfts.contains(where: \.isOnSale)
        if hasOnSale {
            AppActions.showToast(message: lang("$nft_batch_on_sale"))
            return false
        }
        
        return true
    }
}

extension NftsVC: WalletAssetsEmptyStateAnimationControlling { }

@MainActor
private class LayoutGeometry {
    private let horizontalMargins: CGFloat = 16
    
    private let layoutMode: NftsVC.LayoutMode
    private let compactModeMinColumnCount: Int = 2 // occupy place as if at least 2 items are here
    private let compactModeMaxColumnCount: Int = 3
    private let compactModeMaxRowCount: Int = 2
    private let compactModeTopInset: CGFloat = 8
    private let compactModeBottomInset: CGFloat = 12

    private let compactLargeReferenceContainerWidth: CGFloat = 368
    private let compactLargeHorizontalPadding: CGFloat = 16
    private let compactLargeTopPadding: CGFloat = 16
    private let compactLargeBottomPadding: CGFloat = 8
    private let compactLargeMaxColumnCount: Int = 3
    private let compactLargeMaxRowCount: Int = 3
    
    var compactMaxVisibleItemCount: Int {
        switch layoutMode {
        case .compact:
            compactModeMaxColumnCount * compactModeMaxRowCount
        case .compactLarge:
            compactLargeMaxColumnCount * compactLargeMaxRowCount
        case .regular:
            0
        }
    }
    
    var selectionToolbarMargin: CGFloat { horizontalMargins * 2 }
    
    let spacing: CGFloat

    init(layoutMode: NftsVC.LayoutMode) {
        self.layoutMode = layoutMode
        self.spacing = layoutMode.isCompact ? 8 : 16
    }
    
    /// Just an opaque marker to indicate that the layout must be recreated
    /// In fact this is the number of columns in the first row
    struct LayoutChangeID: Equatable {
        private let columnCount: Int
        private let containerWidth: Int
        private let hasRenewalWarning: Bool

        init(columnCount: Int, containerWidth: CGFloat, hasRenewalWarning: Bool) {
            self.columnCount = columnCount
            self.containerWidth = Int(containerWidth.rounded(.down))
            self.hasRenewalWarning = hasRenewalWarning
        }
    }
    
    func calcLayoutChangeID(itemCount: Int, hasRenewalWarning: Bool, collectionView: UICollectionView) -> LayoutChangeID {
        let containerWidth = max(0, getContainerWidth(collectionView: collectionView))

        let columnCount: Int
        if layoutMode.isCompact {
            switch layoutMode {
            case .compact:
                columnCount = min(compactModeMaxColumnCount, itemCount) // 0 is fine too for change id
            case .compactLarge:
                columnCount = compactLargeLayoutColumnCount(itemCount: itemCount)
            case .regular:
                assertionFailure("Unexpected layout mode")
                columnCount = 0
            }
        } else {
            columnCount = calcColumnCountInNonCompactMode(collectionView: collectionView)
        }
        return .init(columnCount: columnCount, containerWidth: containerWidth, hasRenewalWarning: hasRenewalWarning)
    }
        
    func shouldShowShowAllAction(itemCount: Int) -> Bool {
        return layoutMode.isCompact && itemCount > compactMaxVisibleItemCount
    }
    
    /// Height of whole collection view in compact mode
    func calculateHeight(itemCount: Int, isPlaceholderShown: Bool, isActionShown: Bool, isRenewalWarningShown: Bool, collectionView: UICollectionView) -> CGFloat {
        guard layoutMode.isCompact else {
            return 0 // we do not care about non-compact height variations
        }
        
        var result: CGFloat = 0
        if isRenewalWarningShown {
            let (height, contentInsets) = calcRenewalWarningGeometry(collectionView: collectionView)
            result += height + contentInsets.vertical
        }
        if isActionShown {
            let (height, contentInsets) = calcActionsItemGeometry()
            result += height + contentInsets.vertical
        } else if isPlaceholderShown || itemCount > 0 {
            result += compactModeBottomInset // just padding
        }
        if isPlaceholderShown {
            let (height, contentInsets) = calcPlaceholderItemGeometry(collectionView: collectionView, isRenewalWarningShown: isRenewalWarningShown)
            result += height + contentInsets.vertical
        } else if itemCount > 0 {
            let (cellSize, contentInsets) = calcNftItemGeometry(
                itemCount: itemCount,
                collectionView: collectionView,
                isRenewalWarningShown: isRenewalWarningShown
            )
            let rowCount: Int
            switch layoutMode {
            case .compact:
                rowCount = min(compactModeMaxRowCount, (itemCount + compactModeMaxColumnCount - 1) / compactModeMaxColumnCount)
            case .compactLarge:
                let layoutColumnCount = max(1, compactLargeLayoutColumnCount(itemCount: itemCount))
                rowCount = min(compactLargeMaxRowCount, (itemCount + layoutColumnCount - 1) / layoutColumnCount)
            case .regular:
                rowCount = 0
            }
            result += (cellSize.height + spacing) * CGFloat(rowCount) - spacing + contentInsets.vertical
        }
        return result
    }

    func calcRenewalWarningGeometry(collectionView: UICollectionView) -> (height: CGFloat, contentInsets: NSDirectionalEdgeInsets) {
        let height: CGFloat = 44
        switch layoutMode {
        case .compact:
            return (height: height, contentInsets: .init(top: compactModeTopInset, leading: horizontalMargins, bottom: 14, trailing: horizontalMargins))
        case .compactLarge:
            let containerWidth = max(CGFloat(1), getContainerWidth(collectionView: collectionView))
            let compactContainerWidth = min(containerWidth, compactLargeReferenceContainerWidth)
            let outerInset = max(CGFloat(0), floor((containerWidth - compactContainerWidth) / 2))
            let sideInset = outerInset + compactLargeHorizontalPadding
            return (height: height, contentInsets: .init(top: compactLargeTopPadding, leading: sideInset, bottom: 14, trailing: sideInset))
        case .regular:
            return (height: height, contentInsets: .init(top: 10, leading: horizontalMargins, bottom: 14, trailing: horizontalMargins))
        }
    }
    
    func calcActionsItemGeometry() -> (height: CGFloat,  contentInsets: NSDirectionalEdgeInsets) {
        let topInset: CGFloat
        switch layoutMode {
        case .compact:
            topInset = 8
        case .compactLarge:
            topInset = 0
        case .regular:
            topInset = 8
        }
        return (height: WalletSeeAllCell.defaultHeight, contentInsets: .init(top: topInset, leading: 0, bottom: 0, trailing: 0))
    }
    
    func calcCompactModeNftInsets(itemCount: Int, isRenewalWarningShown: Bool, collectionView: UICollectionView) -> UIEdgeInsets {
        var result = UIEdgeInsets(
            top: isRenewalWarningShown ? 0 : compactModeTopInset,
            left: horizontalMargins,
            bottom: compactModeBottomInset,
            right: horizontalMargins
        )
        if isRenewalWarningShown {
            let renewalWarningGeometry = calcRenewalWarningGeometry(collectionView: collectionView)
            result.top += renewalWarningGeometry.height + renewalWarningGeometry.contentInsets.vertical
        }
        if shouldShowShowAllAction(itemCount: itemCount) {
            let ag = calcActionsItemGeometry()
            result.bottom = ag.height + ag.contentInsets.vertical
        }
        return result
    }
    
    func calcPlaceholderItemGeometry(collectionView: UICollectionView, isRenewalWarningShown: Bool) -> (height: CGFloat, contentInsets: NSDirectionalEdgeInsets) {
        switch layoutMode {
        case .compact:
            return (
                height: WalletAssetsEmptyCell.collectiblesHeight,
                contentInsets: .init(
                    top: isRenewalWarningShown ? 0 : compactModeTopInset,
                    leading: horizontalMargins,
                    bottom: compactModeBottomInset,
                    trailing: horizontalMargins
                )
            )
        case .compactLarge:
            let containerWidth = max(CGFloat(1), getContainerWidth(collectionView: collectionView))
            let compactContainerWidth = min(containerWidth, compactLargeReferenceContainerWidth)
            let outerInset = max(CGFloat(0), floor((containerWidth - compactContainerWidth) / 2))
            let sideInset = outerInset + compactLargeHorizontalPadding
            return (
                height: WalletAssetsEmptyCell.collectiblesHeight,
                contentInsets: .init(
                    top: isRenewalWarningShown ? 0 : compactLargeTopPadding,
                    leading: sideInset,
                    bottom: compactLargeBottomPadding,
                    trailing: sideInset
                )
            )
        case .regular:
            return (
                height: WalletAssetsEmptyCell.collectiblesHeight,
                contentInsets: .init(
                    top: isRenewalWarningShown ? 0 : 10,
                    leading: horizontalMargins,
                    bottom: 0,
                    trailing: horizontalMargins
                )
            )
        }
    }
    
    private func getContainerWidth(collectionView: UICollectionView) -> CGFloat {
        return collectionView.bounds.width - collectionView.adjustedContentInset.horizontal
    }
    
    private func calcColumnCountInNonCompactMode(collectionView: UICollectionView) -> Int {
        let containerWidth = getContainerWidth(collectionView: collectionView)
        let usableWidth: CGFloat = containerWidth - 2 * horizontalMargins

        let layoutColumnCount: Int
        if containerWidth < 450 {
            layoutColumnCount = 2
        } else {
            let estimatedCellWidth: CGFloat = 180
            layoutColumnCount = max(1, Int((usableWidth + spacing) / (estimatedCellWidth + spacing)))
        }
        return layoutColumnCount
    }

    func calcNftItemGeometry(itemCount: Int, collectionView: UICollectionView, isRenewalWarningShown: Bool = false) -> (cellSize: CGSize, contentInsets: NSDirectionalEdgeInsets) {
        let containerWidth = max(CGFloat(1), getContainerWidth(collectionView: collectionView))
        
        switch layoutMode {
        case .compact:
            let usableWidth: CGFloat = containerWidth - 2 * horizontalMargins
            let columnCount = min(compactModeMaxColumnCount, max(1, itemCount))
            let layoutColumnCount = min(compactModeMaxColumnCount, max(compactModeMinColumnCount, itemCount))
            let cellWidth = floor((usableWidth + spacing)/CGFloat(layoutColumnCount)) - spacing
            let occupiedSpace = (cellWidth + spacing) * CGFloat(columnCount) - spacing
            let sideInset = floor(containerWidth - occupiedSpace) / 2
            return (
                cellSize: CGSize(width: cellWidth, height: cellWidth),
                contentInsets: .init(top: isRenewalWarningShown ? 0 : compactModeTopInset, leading: sideInset, bottom: 0, trailing: sideInset)
            )
        case .compactLarge:
            let compactContainerWidth = min(containerWidth, compactLargeReferenceContainerWidth)
            let outerInset = max(CGFloat(0), floor((containerWidth - compactContainerWidth) / 2))
            let compactUsableWidth = compactContainerWidth - 2 * compactLargeHorizontalPadding
            let layoutColumnCount = max(1, compactLargeLayoutColumnCount(itemCount: itemCount))
            let cellWidth = floor((compactUsableWidth + spacing) / CGFloat(layoutColumnCount)) - spacing
            let sideInset = outerInset + compactLargeHorizontalPadding
            return (
                cellSize: CGSize(width: cellWidth, height: cellWidth),
                contentInsets: .init(
                    top: isRenewalWarningShown ? 0 : compactLargeTopPadding,
                    leading: sideInset,
                    bottom: compactLargeBottomPadding,
                    trailing: sideInset
                )
            )
        case .regular:
            // in non-compact mode we lay out the stuff similar to flow layout.
            let usableWidth: CGFloat = containerWidth - 2 * horizontalMargins
            let layoutColumnCount = calcColumnCountInNonCompactMode(collectionView: collectionView)
            let cellWidth = floor((usableWidth + spacing)/CGFloat(layoutColumnCount)) - spacing
            return (
                cellSize: CGSize(width: cellWidth, height: cellWidth),
                contentInsets: .init(top: isRenewalWarningShown ? 0 : 10, leading: horizontalMargins, bottom: 0, trailing: horizontalMargins)
            )
        }
    }

    private func compactLargeLayoutColumnCount(itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        if itemCount == 1 {
            return 1
        }
        if itemCount <= 4 {
            return 2
        }
        return compactLargeMaxColumnCount
    }
}

// MARK: - Collection View iPad fixup

final class _NoInsetsCollectionView: UICollectionView {
    
    override var safeAreaInsets: UIEdgeInsets { .zero }
    
}
