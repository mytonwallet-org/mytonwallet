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
import Kingfisher
import Dependencies

private let log = Log("NftsVC")

@MainActor
protocol NftsViewControllerDelegate: AnyObject {
    func nftsViewControllerDidChangeHeightAnimated(_ animated: Bool)
    func nftsViewControllerRequestReordering(_ vc: NftsVC) // this is only for Mode.compact
    func nftsViewControllerDidChangeReorderingState(_ vc: NftsVC)
}

extension NftsViewControllerDelegate {
    func nftsViewControllerRequestReordering(_ vc: NftsVC) { }
    func nftsViewControllerDidChangeHeightAnimated(_ animated: Bool) { }
}

@MainActor
public class NftsVC: WViewController, WSegmentedControllerContent, Sendable, UIAdaptivePresentationControllerDelegate {
    private enum Section {
        case main
        case placeholder
        case actions
    }
    
    private enum Action {
        case showAll
    }
    
    private enum Row: Hashable {
        case placeholder
        case nft(String)
        case action(Action)
    }
    
    public enum Mode {
        /// External reordering management (`WalletAssetsVC`), no self.walletAssetsViewModel is used
        case compact
        /// Fullscreen, own reordering management, navigation item (back + favorites), filter != .none
        case fullScreenFiltered
        /// a child of other controller (`AssetsTabVC`), own reordering management, filter == .none
        case embedded
        
        var isCompact: Bool { self == .compact }
    }
    
    @Dependency(\.accountStore) private var accountStore
    @Dependency(\.accountSettings) var _accountSettings
    @Dependency(\.domains) private var domainsStore
    
    private let accountIdProvider: AccountIdProvider
    
    private var accountSource: AccountSource { accountIdProvider.source }
    private var accountId: String { accountIdProvider.accountId }
    
    private let walletAssetsViewModel: WalletAssetsViewModel // for modes .fullScreenFiltered, .embedded.
    
    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?
    
    var isReordering: Bool { reorderController.isReordering }
    weak var delegate: (any NftsViewControllerDelegate)?
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?
    private var reorderController: ReorderableCollectionViewController!
    
    private let filter: NftCollectionFilter
    private let mode: Mode
    
    private var layoutChangeID: LayoutGeometry.LayoutChangeID?
    private let layoutGeometry: LayoutGeometry
    
    private var contextMenuExtraBlurView: UIView?
    private var navigationBarStarItem: WNavigationBarButton?
        
    public init(accountSource: AccountSource, mode: Mode, filter: NftCollectionFilter) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.filter = filter

        self.mode = mode
        switch mode {
        case .fullScreenFiltered:
            assert(filter != .none)
        case .embedded:
            assert(filter == .none)
        case .compact:
            break
        }
        
        self.walletAssetsViewModel = WalletAssetsViewModel(accountSource: accountSource)
        self.layoutGeometry = LayoutGeometry(compactMode: mode.isCompact)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        WalletCoreData.add(eventObserver: self)
        walletAssetsViewModel.delegate = self
    }
            
    private var displayNfts: OrderedDictionary<String, DisplayNft>?
    private var allShownNftsCount: Int = 0
    
    private func setupViews() {
        title = filter.displayTitle
        let compactMode = mode.isCompact

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        if compactMode {
            collectionView.isScrollEnabled = false
        } else {
            collectionView.alwaysBounceVertical = true
        }
        
        let nftCellRegistration = UICollectionView.CellRegistration<NftCell, String> { [weak self] cell, indexPath, nftId in
            guard let self else { return }
            let displayNft = displayNfts?[nftId] ?? NftStore.getAccountNfts(accountId: accountId)?[nftId]
            cell.configure(nft: displayNft?.nft, compactMode: compactMode)
            cell.configurationUpdateHandler = { nftCell, state in
                nftCell.isHighlighted = state.isHighlighted
            }
            reorderController.updateCell(cell, indexPath: indexPath)
        }
        let placeholderCellRegistration = UICollectionView.CellRegistration<CollectiblesEmptyView, String> {  cell, indexPath, itemIdentifier in
        }
        let compactPlaceholderCellRegistration = UICollectionView.CellRegistration<WalletCollectiblesEmptyView, String> {  cell, indexPath, itemIdentifier in
            cell.config()
        }
        let actionCellRegistration = UICollectionView.CellRegistration<ActionCell, Action> { [filter] cell, indexPath, itemIdentifier in
            cell.highlightBackgroundColor = WTheme.highlight
            switch itemIdentifier {
            case .showAll:
                if filter == .none {
                    cell.configure(with: lang("Show All Collectibles"))
                } else {
                    cell.configure(with: lang("Show All %1$@", arg1: filter.displayTitle))
                }
            }
        }
        
        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .nft(let nftId):
                collectionView.dequeueConfiguredReusableCell(using: nftCellRegistration, for: indexPath, item: nftId)
            case .action(let actionId):
                collectionView.dequeueConfiguredReusableCell(using: actionCellRegistration, for: indexPath, item: actionId)
            case .placeholder:
                if compactMode {
                    collectionView.dequeueConfiguredReusableCell(using: compactPlaceholderCellRegistration, for: indexPath, item: "")
                } else {
                    collectionView.dequeueConfiguredReusableCell(using: placeholderCellRegistration, for: indexPath, item: "")
                }
            }
        }
        self.dataSource = dataSource

        reorderController = ReorderableCollectionViewController(collectionView: collectionView)
        reorderController.scrollDirection = .vertical
        reorderController.delegate = self

        updateNavigationItem()

        UIView.performWithoutAnimation {
            updateNfts()
        }
        
        updateTheme()
    }
                    
    private func updateNavigationItem() {
        guard mode == .fullScreenFiltered else { return }
                
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        
        if reorderController.isReordering {
            let doneItem = UIBarButtonItem.doneButtonItem { [weak self] in self?.walletAssetsViewModel.stopReordering(isCanceled: false) }
            let cancelItem = UIBarButtonItem.cancelTextButtonItem { [weak self] in self?.walletAssetsViewModel.stopReordering(isCanceled: true) }
            leadingItemGroups += cancelItem.asSingleItemGroup()
            trailingItemGroups += doneItem.asSingleItemGroup()
        } else {
            let isFavorited = walletAssetsViewModel.isFavorited(filter: filter)
            let item = UIBarButtonItem(image: UIImage(systemName: isFavorited ? "star.fill" : "star"),
                                       primaryAction: UIAction { [weak self] _ in self?.onFavorite() })
            trailingItemGroups += item.asSingleItemGroup()
        }
        
        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups
    }
    
    private func applyLayoutIfNeeded() {
        let layoutChangeID = layoutGeometry.calcLayoutChangeID(itemCount: allShownNftsCount, collectionView: collectionView)
        if layoutChangeID != self.layoutChangeID {
            self.layoutChangeID = layoutChangeID
            collectionView.setCollectionViewLayout(makeLayout(), animated: true)
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
            case .main:
                let itemCount = dataSource.snapshot().numberOfItems(inSection: .main)
                let (cellSize, contentInsets) = layoutGeometry.calcNftItemGeometry(itemCount: itemCount, collectionView: collectionView)
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
                let (height, contentInsets) = layoutGeometry.calcPlaceholderItemGeometry(collectionView: collectionView)
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
    
    public override func updateTheme() {
        view.backgroundColor = mode.isCompact ? WTheme.groupedItem : WTheme.pickerBackground
        collectionView.backgroundColor = mode.isCompact ? WTheme.groupedItem : WTheme.pickerBackground
    }
    
    public var scrollingView: UIScrollView? {
        return collectionView
    }
    
    private func updateNfts() {
        guard dataSource != nil else { return }
        if var nfts = NftStore.getAccountShownNfts(accountId: accountId) {
            nfts = filter.apply(to: nfts)
            self.allShownNftsCount = nfts.count
            if mode.isCompact {
                nfts = OrderedDictionary(uncheckedUniqueKeysWithValues: nfts.prefix(layoutGeometry.compactModeMaxVisibleItemCount))
            }
            self.displayNfts = nfts
        } else {
            self.displayNfts = nil
            self.allShownNftsCount = 0
        }
        
        applySnapshot(makeSnapshot(), animated: true)
        applyLayoutIfNeeded()
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        
        if let displayNfts {
            if displayNfts.isEmpty {
                snapshot.appendSections([.placeholder])
                snapshot.appendItems([.placeholder])
            } else {
                snapshot.appendSections([.main])
                snapshot.appendItems(displayNfts.keys.map { Row.nft($0) }, toSection: .main)
            }
            if mode.isCompact && layoutGeometry.shouldShowShowAllAction(itemCount: allShownNftsCount) {
                snapshot.appendSections([.actions])
                snapshot.appendItems([Row.action(.showAll)], toSection: .actions)
            }
        }
        return snapshot
    }
        
    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool) {
        guard let dataSource else { return }
        dataSource.apply(snapshot, animatingDifferences: animated)
        delegate?.nftsViewControllerDidChangeHeightAnimated(animated)
    }

    private func persistNftOrder(from snapshot: NSDiffableDataSourceSnapshot<Section, Row>) {
        let orderedIds = OrderedSet(snapshot.itemIdentifiers(inSection: .main).compactMap { row -> String? in
            if case .nft(let id) = row { return id }
            return nil
        })
        NftStore.reorderNfts(accountId: accountId, orderedIdsHint: orderedIds)
    }
    
    public var calculatedHeight: CGFloat {
        layoutGeometry.calculateHeight(itemCount: allShownNftsCount, collectionView: collectionView)
    }
        
    private func onFavorite() {
        if filter != .none {
            Task {
                do {
                    let newIsFavorited = !self.walletAssetsViewModel.isFavorited(filter: filter)
                    try await self.walletAssetsViewModel.setIsFavorited(filter: filter, isFavorited: newIsFavorited)
                    
                    if newIsFavorited {
                        Haptics.play(.success)
                    } else {
                        Haptics.play(.lightTap)
                    }
                    
                    updateNavigationItem()
                } catch {
                    log.error("failed to favorite collection: \(filter, .public) \(accountId, .public)")
                }
            }
        }
    }
        
    /// This is called internally - using menu or from the controller's system drag. See also `startReordering`
    private func startReorderingInternally() {
        switch mode {
        case .fullScreenFiltered, .embedded:
            walletAssetsViewModel.startOrdering()
        case .compact:
            guard let delegate else {
                assertionFailure("An assigned delegate is assumed for this mode")
                return
            }
            delegate.nftsViewControllerRequestReordering(self)
        }
        delegate?.nftsViewControllerDidChangeReorderingState(self)
    }
    
    /// This is called outside. Not for all modes
    public func startReordering() {
        guard !reorderController.isReordering else { return }
        switch mode {
        case .compact:
            reorderController.isReordering = true
        case .embedded:
            walletAssetsViewModel.startOrdering() 
        case .fullScreenFiltered:
            assertionFailure("No external reordering management is assumed for this mode")
        }
    }
    
    /// This is called outside. Not for all modes
    public func stopReordering(isCanceled: Bool) {
        guard reorderController.isReordering else { return }
        switch mode {
        case .compact:
            reorderController.isReordering = false
        case .fullScreenFiltered:
            assertionFailure("No external reordering management is assumed for this mode")
        case .embedded:
            walletAssetsViewModel.stopReordering(isCanceled: isCanceled)
        }
    }
}

// These are internal (self.walletAssetsViewModel) notifications
extension NftsVC: WalletAssetsViewModelDelegate {
    private func updateUIForReordering(_ isReordering: Bool) {
        reorderController.isReordering = isReordering
        updateNavigationItem()
        
        navigationController?.allowBackSwipeToDismiss(!isReordering)
        navigationController?.isModalInPresentation = isReordering
    }

    func walletAssetModelDidStartReordering() {
        updateUIForReordering(true)
    }
        
    func walletAssetModelDidStopReordering(isCanceled: Bool) {
        updateUIForReordering(false)
    }
    
    func walletAssetModelDidChangeDisplayTabs() {
        updateNavigationItem()
    }
}

extension NftsVC: ReorderableCollectionViewControllerDelegate {
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
        case .nft(let nftId):
            if let nft = displayNfts?[nftId]?.nft {
                let assetVC = NftDetailsVC(accountId: accountId, nft: nft, listContext: filter)
                navigationController?.pushViewController(assetVC, animated: true)
            }
        case .action(let actionId):
            if actionId == .showAll {
                AppActions.showAssets(accountSource: accountSource, selectedTab: 1, collectionsFilter: filter)
            }
        case .placeholder:
            if mode.isCompact {
                guard let url = URL(string: NFT_MARKETPLACE_URL) else {
                    assertionFailure()
                    break
                }
                AppActions.openInBrowser(url)
            }
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrollStart?()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onScrollEnd?()
    }
        
    public func reorderController(_ controller: ReorderableCollectionViewController, contextMenuConfigurationForItemAt indexPath: IndexPath,
                                  point: CGPoint) -> UIContextMenuConfiguration? {
        guard let row = dataSource?.itemIdentifier(for: indexPath) else { return nil }
        guard case .nft(let nftId) = row, let nft = displayNfts?[nftId]?.nft else { return nil }
        
        let menu = UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [accountId] _ in
            return self.makeMenu(accountId: accountId, nft: nft)
        }
        return menu
    }
    
    private func makeMenu(accountId: String, nft: ApiNft) -> UIMenu {
        
        let accountSettings = _accountSettings.for(accountId: accountId)
        let account = accountStore.get(accountId: accountId)
        let domains = domainsStore.for(accountId: accountId)

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
                items += UIAction(title: lang("Send"), image: .airBundle("MenuSend26")) { _ in
                    AppActions.showSend(prefilledValues: .init(nfts: [nft], nftSendMode: .send))
                }
            }
            items += UIAction(title: lang("Share"), image: .airBundle("MenuShare26")) { _ in
                AppActions.shareUrl(ExplorerHelper.nftUrl(nft))
            }
            if account.type == .mnemonic, nft.isTonDns {
                if domains.expirationByAddress[nft.address] != nil {
                    items += UIAction(title: lang("Renew"), image: .airBundle("MenuRenew26")) { _ in
                        AppActions.showRenewDomain(accountSource: .accountId(accountId), nftsToRenew: [nft.address])
                    }
                }
                if !nft.isOnSale {
                    let linkedAddress = domains.linkedAddressByAddress[nft.address]?.nilIfEmpty
                    let title = linkedAddress == nil
                        ? lang("Link to Wallet")
                        : lang("Change Linked Wallet")
                    items += UIAction(title: title, image: .airBundle("MenuLinkToWallet26")) { _ in
                        AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: nft.address)
                    }
                }
            }
            items += UIAction(title: lang("Hide"), image: .airBundle("MenuHide26")) { _ in
                NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
            }
            if account.supportsBurn {
                items += UIAction(title: lang("Burn"), image: .airBundle("MenuBurn26"), attributes: .destructive) { _ in
                    AppActions.showSend(prefilledValues: .init(nfts: [nft], nftSendMode: .burn))
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
            if !ConfigStore.shared.shouldRestrictBuyNfts {
                items += UIAction(title: "Getgems", image: .airBundle("MenuGetgems26")) { _ in
                    let url = ExplorerHelper.nftUrl(nft)
                    AppActions.openInBrowser(url)
                }
            }
            items += UIAction(title: ExplorerHelper.selectedExplorerName(for: .ton), image: .airBundle(ExplorerHelper.selectedExplorerMenuIconName(for: .ton))) { _ in
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
            if allShownNftsCount > 1 || mode == .compact {
                items += UIAction(title: lang("Reorder"), image: .airBundle("MenuReorder26")) { [weak self] _ in
                    self?.startReorderingInternally()
                }
            }
            if let collection = nft.collection {
                if mode == .fullScreenFiltered {
                    // we are already in the collection view, there is nowhere to go
                } else {
                    let collectionAction = UIAction(title: lang("Collection"), image: .airBundle("MenuCollection26")) { [weak self] _ in
                        guard let self else { return }
                        AppActions.showAssets(accountSource: accountSource, selectedTab: 1, collectionsFilter: .collection(collection))
                    }
                    items.append(collectionAction)
                }
            }
            if !openInSection.children.isEmpty {
                items.append(openInSection)
            }
            otherSection = UIMenu(title: "", options: .displayInline, children: items)
        }
                    
        let sections = [detailsSection, installSection, actionsSection, otherSection].filter { !$0.children.isEmpty }
        return UIMenu(title: "", children: sections)
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview? {
        guard let cell = cell as? NftCell else { return nil }
        return .init(view: cell.imageContainerView, cornerRadius: NftCell.getCornerRadius(compactMode: mode.isCompact))
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        guard let window = view.window else { return }
        let blurView = WBlurView()
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.frame = window.bounds
        blurView.isUserInteractionEnabled = false
        window.addSubview(blurView)
        self.contextMenuExtraBlurView = blurView
        blurView.alpha = 0
        animator?.addAnimations {
            blurView.alpha = 1
        }
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        animator?.addAnimations {
            self.contextMenuExtraBlurView?.alpha = 0
        }
        animator?.addCompletion {
            self.contextMenuExtraBlurView?.removeFromSuperview()
            self.contextMenuExtraBlurView = nil
        }
    }
}

extension NftsVC: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task { @MainActor in
            switch event {
            case .nftsChanged(let accountId):
                if accountId == self.accountId {
                    updateNfts()
                }
            case .accountChanged:
                if accountSource == .current {
                    updateNfts()
                }
            default:
                break
            }
        }
    }
}

@MainActor
private class LayoutGeometry {
    private let horizontalMargins: CGFloat = 16
    
    private let compactMode: Bool
    private let compactModeMinColumnCount: Int = 2 // occupy place as if at least 2 items are here
    private let compactModeMaxColumnCount: Int = 3
    private let compactModeMaxRowCount: Int = 2
    
    var compactModeMaxVisibleItemCount: Int { compactModeMaxColumnCount * compactModeMaxRowCount } // 6
    
    let spacing: CGFloat
    
    init(compactMode: Bool) {
        self.compactMode = compactMode
        self.spacing = compactMode ? 8 : 16
    }
    
    /// Just an opaque marker to indicate that the layout must be recreated
    /// In fact this is the number of columns in the first row
    struct LayoutChangeID: Equatable {
        private let columnCount: Int
        
        init(columnCount: Int) {
            self.columnCount = columnCount
        }
    }
    
    func calcLayoutChangeID(itemCount: Int, collectionView: UICollectionView) -> LayoutChangeID {
        let columnCount: Int
        if compactMode {
            columnCount = min(compactModeMaxColumnCount, itemCount) // 0 is fine too for change id
        } else {
            columnCount = calcColumnCountInNonCompactMode(collectionView: collectionView)
        }
        return .init(columnCount: columnCount)
    }
        
    func shouldShowShowAllAction(itemCount: Int) -> Bool {
        return compactMode && itemCount > compactModeMaxVisibleItemCount
    }
    
    /// Height of whole collection view in compact mode
    func calculateHeight(itemCount: Int, collectionView: UICollectionView) -> CGFloat {
        guard compactMode else {
            assertionFailure("For compact mode only")
            return 0
        }
        
        var result: CGFloat = 0
        if shouldShowShowAllAction(itemCount: itemCount) {
            let (height, contentInsets) = calcActionsItemGeometry()
            result += height + contentInsets.top + contentInsets.bottom
        } else {
            result += 12 // just padding
        }
        if itemCount == 0 {
            let (height, contentInsets) = calcPlaceholderItemGeometry(collectionView: collectionView)
            result += height + contentInsets.top + contentInsets.bottom
        } else {
            let (cellSize, contentInsets) = calcNftItemGeometry(itemCount: itemCount, collectionView: collectionView)
            let rowCount = min(compactModeMaxRowCount, (itemCount + compactModeMaxColumnCount - 1) / compactModeMaxColumnCount)
            result += (cellSize.height + spacing) * CGFloat(rowCount) - spacing + contentInsets.top + contentInsets.bottom
        }
        return result
    }
    
    func calcActionsItemGeometry() -> (height: CGFloat,  contentInsets: NSDirectionalEdgeInsets) {
        return (height: 44, contentInsets: .init(top: 8, leading: 0, bottom: 0, trailing: 0))
    }
    
    func calcPlaceholderItemGeometry(collectionView: UICollectionView) -> (height: CGFloat, contentInsets: NSDirectionalEdgeInsets) {
        // in compact mode we use a single nft item height (which is the same as width)
        if compactMode {
            let (cellSize, contentInsets) = calcNftItemGeometry(itemCount: 1, collectionView: collectionView)
            return (height: cellSize.height, contentInsets: contentInsets)
        }
        
        // In non-compact mode we take whole viewport height (full-screen Lottie animation with a duck)
        let viewportHeight = collectionView.bounds.height - collectionView.adjustedContentInset.vertical
        return (height: viewportHeight, contentInsets: .init(top: 10, leading: horizontalMargins, bottom: 0, trailing: horizontalMargins))
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

    func calcNftItemGeometry(itemCount: Int, collectionView: UICollectionView) -> (cellSize: CGSize, contentInsets: NSDirectionalEdgeInsets) {
        let containerWidth = getContainerWidth(collectionView: collectionView)
        let usableWidth: CGFloat = containerWidth - 2 * horizontalMargins
        
        if compactMode {
            let columnCount = min(compactModeMaxColumnCount, max(1, itemCount))
            let layoutColumnCount = min(compactModeMaxColumnCount, max(compactModeMinColumnCount, itemCount))
            let cellWidth = floor((usableWidth + spacing)/CGFloat(layoutColumnCount)) - spacing
            let occupiedSpace = (cellWidth + spacing) * CGFloat(columnCount) - spacing
            let sideInset = floor(containerWidth - occupiedSpace) / 2
            return (
                cellSize: CGSize(width: cellWidth, height: cellWidth),
                contentInsets: .init(top: 8, leading: sideInset, bottom: 0, trailing: sideInset)
            )
        }
        
        // in non-compact mode we lay out the stuff similar to flow layout.
        let layoutColumnCount = calcColumnCountInNonCompactMode(collectionView: collectionView)
        let cellWidth = floor((usableWidth + spacing)/CGFloat(layoutColumnCount)) - spacing
        return (
            cellSize: CGSize(width: cellWidth, height: cellWidth),
            contentInsets: .init(top: 10, leading: horizontalMargins, bottom: 0, trailing: horizontalMargins)
        )
    }
}
