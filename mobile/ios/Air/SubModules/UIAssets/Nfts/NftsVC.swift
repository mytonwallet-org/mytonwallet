//
//  AssetsVC.swift
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

private let log = Log("NftsVC")


@MainActor
public class NftsVC: WViewController, WSegmentedControllerContent, WalletAssetsViewModelDelegate, Sendable {
    
    enum Section {
        case main
        case placeholder
        case actions
    }
    enum Row: Hashable {
        case placeholder
        case nft(String)
        case action(String)
        
        var stringValue: String {
            switch self {
            case .action(let string), .nft(let string):
                return string
            case .placeholder:
                return ""
            }
        }
    }
    
    private var walletAssetsViewModel = WalletAssetsViewModel()
    
    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?
    
    public var onHeightChanged: ((_ animated: Bool) -> ())?
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?
    
    private var animateIfPossible: Bool = false // { isAppActive && isVisible }
    private var isAppActive: Bool = true
    private var isVisible: Bool = true
    
    public private(set) var filter: NftCollectionFilter
    
    private let compactMode: Bool
    private var columnCount: Int?
    private var cornerRadius: CGFloat { compactMode ? 8 : 12 }

    private let topInset: CGFloat
    private let horizontalMargins: CGFloat = 16
    private let spacing: CGFloat = 16
    private let compactSpacing: CGFloat = 8
    
    private var contextMenuExtraBlurView: UIView?
    private var navigationBarStarItem: WNavigationBarButton?
    
    var scrollingContext = ScrollingContext()
    
    public init(compactMode: Bool, filter: NftCollectionFilter, topInset: CGFloat = 0) {
        self.compactMode = compactMode
        self.filter = filter
        self.topInset = topInset
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
        setupNotifications()
        walletAssetsViewModel.delegate = self
    }
    
    public func displayTabsChanged() {
        let isFavorited = walletAssetsViewModel.isFavorited(filter: filter)
        (self.navigationBarStarItem?.view as? WButton)?.setImage(UIImage(systemName: isFavorited ? "star.fill" : "star"), for: .normal)
    }
    
    private var displayNfts: OrderedDictionary<String, DisplayNft>?
    private var allShownNftsCount: Int = 0
    public var showAllVisible: Bool {
        allShownNftsCount > 6
    }
    
    func setupViews() {
        title = filter.displayTitle
        let compactMode = self.compactMode
        
        let columns = calculateColumns()
        columnCount = columns
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout(columnCount: columns))
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        if compactMode {
            collectionView.isScrollEnabled = false
        } else {
            collectionView.alwaysBounceVertical = true
        }
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        collectionView.contentInset.top = topInset
        collectionView.verticalScrollIndicatorInsets.top = topInset
        collectionView.contentOffset.y = -topInset
        collectionView.clipsToBounds = false

        let nftCellRegistration = UICollectionView.CellRegistration<CollectionViewCellIgnoringSafeArea, String> { [weak self, scrollingContext] cell, indexPath, itemIdentifier in
            guard let self else { return }
            let displayNft: DisplayNft? = displayNfts?[itemIdentifier] ?? NftStore.currentAccountNfts?[itemIdentifier]
            cell.configurationUpdateHandler = { [weak self] cell, state in
                let animateIfPossible = self?.animateIfPossible ?? false
                cell.contentConfiguration = UIHostingConfiguration {
                    NftCell(nft: displayNft?.nft, compactMode: compactMode, isHighlighted: state.isHighlighted, animateIfPossible: animateIfPossible, scrollingContext: scrollingContext)
                }
                .margins(.all, 0)
            }
        }
        let placeholderCellRegistration = UICollectionView.CellRegistration<CollectiblesEmptyView, String> {  cell, indexPath, itemIdentifier in
        }
        let compactPlaceholderCellRegistration = UICollectionView.CellRegistration<WalletCollectiblesEmptyView, String> {  cell, indexPath, itemIdentifier in
            cell.config()
        }
        let actionCellRegistration = UICollectionView.CellRegistration<ActionCell, String> { [filter] cell, indexPath, itemIdentifier in
            cell.highlightBackgroundColor = WTheme.highlight
            if itemIdentifier == "showAll" {
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
        dataSource.reorderingHandlers.canReorderItem = { [weak self] identifier in
            if self?.displayNfts?.count == 1 { return false }
            if case .nft = identifier { return true }
            return false
        }
        dataSource.reorderingHandlers.didReorder = { transaction in
            let changes = transaction.difference.toNftIds()
            if let accountId = AccountStore.accountId {
                NftStore.reorderNfts(accountId: accountId, changes: changes)
            }
        }
        
        if !compactMode, filter != .none {
            
            let isFavorited = walletAssetsViewModel.isFavorited(filter: filter)
            let starButton = WNavigationBarButton(icon: UIImage(systemName: isFavorited ? "star.fill" : "star"), onPress: { [weak self] in self?.onFavorite() })
            self.navigationBarStarItem = starButton
            addNavigationBar(
                title: title,
                trailingItem: starButton,
                addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) }
            )
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                navigationItem.trailingItemGroups = makeToolbarItemGroups()
            }
            collectionView.contentInset.top = navigationBarHeight
            collectionView.verticalScrollIndicatorInsets.top = navigationBarHeight
        }
        
        UIView.performWithoutAnimation {
            updateNfts()
        }
        
        updateTheme()
    }
    
    func applyLayoutIfNeeded() {
        let newColumnCount = calculateColumns()
        if newColumnCount != self.columnCount {
            self.columnCount = newColumnCount
            collectionView.setCollectionViewLayout(makeLayout(columnCount: newColumnCount), animated: true)
        }
    }
    
    func calculateColumns() -> Int {
        let columnCount: Int
        if compactMode {
            columnCount = min(3, max(1, displayNfts?.count ?? 0))
        } else {
            let screenWidth = UIScreen.main.bounds.width
            let usableWidth = screenWidth - 2 * horizontalMargins
            let minItemWidth: CGFloat = 163
            columnCount = max(1, Int((usableWidth + spacing) / (minItemWidth + spacing)))
        }
        return columnCount
    }
    
    func makeLayout(columnCount: Int) -> UICollectionViewCompositionalLayout {
        let itemSize1 = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(columnCount)),
            heightDimension: columnCount == 1 ? .absolute(159) : .estimated(400)
        )
        let item1 = NSCollectionLayoutItem(layoutSize: itemSize1)
        let groupSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
        let group1 = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize1, subitems: [item1])
        group1.interItemSpacing = .fixed(compactMode ? compactSpacing : spacing)
        let section1 = NSCollectionLayoutSection(group: group1)
        section1.contentInsets = .init(top: compactMode ? 8 : 10, leading: horizontalMargins, bottom: 0, trailing: horizontalMargins)
        section1.interGroupSpacing = compactMode ? compactSpacing : spacing
        
        let itemSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1.0))
        let item2 = NSCollectionLayoutItem(layoutSize: itemSize2)
        let groupSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
        let group2 = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize2, subitems: [item2])
        let section2 = NSCollectionLayoutSection(group: group2)
        section2.contentInsets = .init(top: 8, leading: 0, bottom: compactMode ? 0 : 8, trailing: 0)

        let itemSize3 = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: compactMode ? .absolute(159) : .absolute(600)
        )
        let item3 = NSCollectionLayoutItem(layoutSize: itemSize3)
        let groupSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
        let group3 = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize3, subitems: [item3])
        let section3 = NSCollectionLayoutSection(group: group3)
        section3.contentInsets = .init(top: compactMode ? 8 : 10, leading: horizontalMargins, bottom: 0, trailing: horizontalMargins)
    
        let layout = UICollectionViewCompositionalLayout { [weak self] idx, env in
            guard let self, let dataSource else { return nil }
            switch dataSource.sectionIdentifier(for: idx) {
            case .main:
                return section1
            case .actions:
                return section2
            case .placeholder:
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
        view.backgroundColor = compactMode ? WTheme.groupedItem : WTheme.pickerBackground
        collectionView.backgroundColor = compactMode ? WTheme.groupedItem : WTheme.pickerBackground
    }
    
    public var scrollingView: UIScrollView? {
        return collectionView
    }
    
    public func updateCollectionFilter(_ filter: NftCollectionFilter) {
        if filter != self.filter {
            self.filter = filter
            updateNfts()
        }
    }
    
    private func updateNfts() {
        guard dataSource != nil else { return }
        if var nfts = NftStore.currentAccountShownNfts {
            nfts = filter.apply(to: nfts)
            self.allShownNftsCount = nfts.count
            if compactMode {
                nfts = OrderedDictionary(uncheckedUniqueKeysWithValues: nfts.prefix(6))
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
            if compactMode && showAllVisible {
                snapshot.appendSections([.actions])
                snapshot.appendItems([Row.action("showAll")], toSection: .actions)
            }
        }
        return snapshot
    }
    
    func reconfigureVisibleRows(animated: Bool) {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        if animated {
            dataSource.apply(snapshot)
        } else {
            UIView.performWithoutAnimation {
                dataSource.apply(snapshot)
            }
        }
    }
    
    func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool) {
        guard let dataSource else { return }
        dataSource.apply(snapshot, animatingDifferences: animated)
        onHeightChanged?(animated)
    }
    
    public var calculatedHeight: CGFloat {
        let seeAll: CGFloat = showAllVisible ? 36 : 0
        let height: CGFloat = switch allShownNftsCount {
        case 0:
            216
        case 1:
            seeAll + 24 + 159
        case 2:
            seeAll + 24 + (view.frame.width - 40) / 2
        case 3:
            seeAll + 24 + (view.frame.width - 48) / 3
        default:
            seeAll + 32 + 2 * (view.frame.width - 48) / 3
        }
        return height
    }
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(pauseAnimations), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pauseAnimations), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playAnimations), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playAnimations), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc func pauseAnimations() {
        self.isAppActive = false
        self.reconfigureVisibleRows(animated: true)
    }
    
    @objc func playAnimations() {
        self.isAppActive = true
        self.reconfigureVisibleRows(animated: true)
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
//        if isVisible != self.isVisible {
//            self.isVisible = isVisible
//            self.reconfigureVisibleRows(animated: true)
//        }
    }
    
    @available(iOS 26, *)
    func makeToolbarItemGroups() -> [UIBarButtonItemGroup] {
        let isFavorited = walletAssetsViewModel.isFavorited(filter: filter)
        return [
            UIBarButtonItemGroup(
                barButtonItems: [
                    UIBarButtonItem(image: UIImage(systemName: isFavorited ? "star.fill" : "star"), primaryAction: UIAction { [weak self] _ in self?.onFavorite() })
                ],
                representativeItem: nil,
            ),
        ]
    }
    
    func onFavorite() {
        if filter != .none, let accountId = AccountStore.accountId {
            Task {
                do {
                    let newIsFavorited = !self.walletAssetsViewModel.isFavorited(filter: filter)
                    
                    try await self.walletAssetsViewModel.setIsFavorited(filter: filter, isFavorited: newIsFavorited)
                    
                    (self.navigationBarStarItem?.view as? WButton)?.setImage(UIImage(systemName: newIsFavorited ? "star.fill" : "star"), for: .normal)
                    if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                        navigationItem.trailingItemGroups = makeToolbarItemGroups()
                    }
                    
                    if newIsFavorited {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                    }
                } catch {
                    log.error("failed to favorite collection: \(filter, .public) \(accountId, .public)")
                }
            }
        }
    }
}


extension NftsVC: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
        switch id {
        case .nft(let nftId):
            if let nft = displayNfts?[nftId]?.nft {
                let assetVC = NftDetailsVC(nft: nft, listContext: filter)
                navigationController?.pushViewController(assetVC, animated: true)
            }
        case .action(let actionId):
            if actionId == "showAll" {
                AppActions.showAssets(selectedTab: 1, collectionsFilter: filter)
            }
        case .placeholder:
            if compactMode {
                let url = URL(string: NFT_MARKETPLACE_URL)!
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
        scrollingContext.isScrolling = true
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onScrollEnd?()
        if !decelerate {
            scrollingContext.isScrolling = false
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollingContext.isScrolling = false
    }
    
    public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let dataSource, indexPaths.count == 1, let indexPath = indexPaths.first else {
            // FIXME: No context menu for multiple items yet
            return nil
        }

//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
//            if let view = self._viewByClassName(view: window, className: "_UIPlatterSoftShadowView") {
//                view.isHidden = true
//            }
//            if let view = self._viewByClassName(view: window, className: "_UIMorphingPlatterView") {
//                view.backgroundColor = .red
//            }
//        }

        let row = dataSource.itemIdentifier(for: indexPath)
        guard let accountId = AccountStore.accountId, case .nft(let nftId) = row, let nft = displayNfts?[nftId]?.nft else { return nil }
        
        let menu = UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
            return self.makeMenu(accountId: accountId, nft: nft)
        }
        return menu
    }
    
    private func makeMenu(accountId: String, nft: ApiNft) -> UIMenu {
//        let selectAction = UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { _ in
//            // Handle select action
//        }
        let detailsAction = UIAction(title: lang("Details"), image: UIImage(systemName: "info.circle")) { [filter] _ in
            let assetVC = NftDetailsVC(nft: nft, listContext: filter)
            self.navigationController?.pushViewController(assetVC, animated: true)
        }
        let sendAction = UIAction(title: lang("Send"), image: UIImage(systemName: "paperplane")) { _ in
            AppActions.showSend(prefilledValues: .init(nfts: [nft], nftSendMode: .send))
        }
        var section1Items = [detailsAction, sendAction]
        if let collection = nft.collection {
            let collectionAction = UIAction(title: lang("Open Collection"), image: nil) { _ in
                AppActions.showAssets(selectedTab: 1, collectionsFilter: .collection(collection))
            }
            section1Items.append(collectionAction)
        }
        let section1 = UIMenu(title: "", options: .displayInline, children: section1Items)
        
        var section2Items: [UIAction] = []
        if let mtwCardId = nft.metadata?.mtwCardId {
            let isCurrent = mtwCardId == AccountStore.currentAccountCardBackgroundNft?.metadata?.mtwCardId
            if isCurrent {
                section2Items.append(UIAction(title: lang("Reset Card"), image: UIImage(systemName: "xmark.rectangle")) { _ in
                    AccountStore.currentAccountCardBackgroundNft = nil
                    AccountStore.currentAccountAccentColorNft = nil
                })
            } else {
                section2Items.append(UIAction(title: lang("Install Card"), image: UIImage(systemName: "checkmark.rectangle")) { _ in
                    AccountStore.currentAccountCardBackgroundNft = nft
                    AccountStore.currentAccountAccentColorNft = nft
                })
            }
            
            let isCurrentAccent = mtwCardId == AccountStore.currentAccountAccentColorNft?.metadata?.mtwCardId
            if isCurrentAccent {
                section2Items.append(UIAction(title: lang("Reset Palette"), image: .airBundle("custom.paintbrush.badge.xmark")) { _ in
                    AccountStore.currentAccountAccentColorNft = nil
                })
            } else {
                section2Items.append(UIAction(title: lang("Install Palette"), image: .airBundle("custom.paintbrush.badge.checkmark")) { _ in
                    AccountStore.currentAccountAccentColorNft = nft
                })
            }
        }
        if nft.isOnFragment == true, let string = nft.metadata?.fragmentUrl?.nilIfEmpty, let url = URL(string: string) {
            section2Items.append(UIAction(title: "Fragment", image: UIImage(systemName: "globe")) { _ in
                AppActions.openInBrowser(url)
            })
        }
        let section2 = UIMenu(title: "", options: .displayInline, children: section2Items)
        
        let hideAction = UIAction(title: lang("Hide"), image: UIImage(systemName: "eye.slash")) { _ in
            NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
        }
        let burnAction = UIAction(title: lang("Burn"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            AppActions.showSend(prefilledValues: .init(nfts: [nft], nftSendMode: .burn))
        }
        let section3 = UIMenu(title: "", options: .displayInline, children: [hideAction, burnAction])
        
        let sections = section2Items.isEmpty ? [section1, section3] : [section1, section2, section3]
        return UIMenu(title: "", children: sections)
    }
    
    public func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return createTargetedPreview(for: configuration, in: collectionView)
    }
    
    public func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return createTargetedPreview(for: configuration, in: collectionView)
    }
    
    private func createTargetedPreview(for configuration: UIContextMenuConfiguration, in collectionView: UICollectionView) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let dim = min(cell.bounds.width, cell.bounds.height)
        let bounds = CGRect(x: (cell.bounds.width - dim) * 0.5, y: 0, width: dim, height: dim)
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        let shadowBounds = CGRect(x: dim * 0.25, y: dim * 0.25, width: dim * 0.5, height: dim * 0.5)
        parameters.shadowPath = UIBezierPath(roundedRect: shadowBounds, cornerRadius: cornerRadius)
        return UITargetedPreview(
            view: cell.contentView,
            parameters: parameters
        )
    }
    
    private func _viewByClassName(view: UIView, className: String) -> UIView? {
        let name = NSStringFromClass(type(of: view))
        if name == className {
            return view
        }
        else {
            for subview in view.subviews {
                if let view = _viewByClassName(view: subview, className: className) {
                    return view
                }
            }
        }
        return nil
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
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
    
    public func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        animator?.addAnimations {
            self.contextMenuExtraBlurView?.alpha = 0
        }
        animator?.addCompletion {
            self.contextMenuExtraBlurView?.removeFromSuperview()
            self.contextMenuExtraBlurView = nil
        }
    }
}


extension NftsVC: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    
    public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        if allShownNftsCount <= 1 { return [] }
        return makeDragItems(collectionView: collectionView, indexPath: indexPath)
    }
    
    public func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        makeDragItems(collectionView: collectionView, indexPath: indexPath)
    }
    
    private func makeDragItems(collectionView: UICollectionView, indexPath: IndexPath) -> [UIDragItem] {
        guard let dataSource, let cell = collectionView.cellForItem(at: indexPath), case .nft = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        dragItem.previewProvider = { [cornerRadius] in
            let dim = min(cell.bounds.width, cell.bounds.height)
            let bounds = CGRect(x: 0, y: 0, width: dim, height: dim)
            let targetView = UIView(frame: bounds)
            targetView.backgroundColor = .init(white: 1, alpha: 0.15)
            let parameters = UIDragPreviewParameters()
            parameters.visiblePath = UIBezierPath(roundedRect: targetView.bounds, cornerRadius: cornerRadius)
            return UIDragPreview(view: targetView, parameters: parameters)
        }
        return  [dragItem]
    }
    
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if let dataSource, let destinationIndexPath, case .nft = dataSource.itemIdentifier(for: destinationIndexPath) {
            return .init(operation: .move, intent: .insertAtDestinationIndexPath)
        } else {
            return .init(operation: .cancel)
        }
    }
    
    public func collectionView(_: UICollectionView, performDropWith _: UICollectionViewDropCoordinator) {
        // required for drop delegate
    }
    
    public func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let dataSource, let cell = collectionView.cellForItem(at: indexPath), case .nft = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let dim = min(cell.bounds.width, cell.bounds.height)
        let bounds = CGRect(x: (cell.bounds.width - dim) * 0.5, y: 0, width: dim, height: dim)
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        return parameters
    }
    
    public func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let dataSource, let cell = collectionView.cellForItem(at: indexPath), case .nft = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: cornerRadius)
        return parameters
    }
}


extension NftsVC: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task { @MainActor in
            switch event {
            case .nftsChanged(accountId: let accountId):
                if accountId == AccountStore.accountId {
                    updateNfts()
                }
            case .accountChanged:
                updateNfts()
            default:
                break
            }
        }
    }
}


extension CollectionDifference<NftsVC.Row> {
    func toNftIds() -> CollectionDifference<String> {
        var changes: [CollectionDifference<String>.Change] = []
        for rowChange in self {
            switch rowChange {
            case .remove(offset: let offset, element: let element, associatedWith: let associatedWith):
                changes.append(.remove(offset: offset, element: element.stringValue, associatedWith: associatedWith))
            case .insert(offset: let offset, element: let element, associatedWith: let associatedWith):
                changes.append(.insert(offset: offset, element: element.stringValue, associatedWith: associatedWith))
            }
        }
        return CollectionDifference<String>(changes)!
    }
}
