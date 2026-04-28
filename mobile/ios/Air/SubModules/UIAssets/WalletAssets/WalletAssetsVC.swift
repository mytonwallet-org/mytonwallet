
import ContextMenuKit
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-WalletAssets")

@MainActor public protocol WalletAssetsDelegate: AnyObject {
    func walletAssetDidChangeHeight(animated: Bool)
}

@MainActor public final class WalletAssetsVC: WViewController, WalletCoreData.EventsObserver, Sendable {
    private var walletAssetsView: WalletAssetsView { view as! WalletAssetsView }
    
    public weak var delegate: (any WalletAssetsDelegate)?
    
    public var editingNavigator: NftsEditingNavigator { nftsVCManager.editingNavigator  }
    
    private var tokensVC: WalletTokensVC?
    private var nftsVC: NftsVC?
    private let nftsVCManager: NftsVCManager
    
    private let accountIdProvider: AccountIdProvider
    private var accountSource: AccountSource { accountIdProvider.source }
    
    @AppStorage("debug_hideSegmentedControls") private var hideSegmentedControls = false
    
    private let tabsViewModel: WalletAssetsViewModel
    
    private var tabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]
    private var lastMeasuredWidth: CGFloat = 0
    
    private var contextMenuProviders: [DisplayAssetTab: SegmentedControlContextMenuProvider] = [:]
    
    private func makeSegmentedTabSourcePortal() -> ContextMenuSourcePortal {
        ContextMenuSourcePortal(
            sourceViewProvider: { [weak self] in
                self?.walletAssetsView.tabsContainer.segmentedControl
            },
            mask: .roundedAttachmentRect(cornerRadius: 12.0, cornerCurve: .circular),
            showsBackdropCutout: true
        )
    }

    private func getContextMenuProvider(tab: DisplayAssetTab) -> SegmentedControlContextMenuProvider {
        if let provider = contextMenuProviders[tab] {
            return provider
        }

        let configuration: () -> ContextMenuConfiguration
        switch tab {
        case .tokens:
            configuration = makeTokensMenuConfig(onReorder: { [weak self] in
                self?.onSegmentsReorder()
            })
        case .nfts:
            configuration = makeCollectiblesMenuConfig(accountSource: accountSource, onReorder: { [weak self] in
                self?.onSegmentsReorder()
            })
        case let .nftCollectionFilter(filter):
            configuration = makeNftCollectionMenuConfig(
                onReorder: { [weak self] in
                    self?.onSegmentsReorder()
                },
                onHide: { [weak self] in
                    Task {
                        try? await self?.nftsVCManager.setIsFavorited(filter: filter, isFavorited: false)
                    }
                }
            )
        }

        let provider = SegmentedControlContextMenuProvider(
            sourcePortal: makeSegmentedTabSourcePortal(),
            configuration: configuration
        )
        contextMenuProviders[tab] = provider
        return provider
    }
    
    public init(accountSource: AccountSource) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
        self.nftsVCManager = NftsVCManager(tabsViewModel: tabsViewModel)
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func switchIncomingFirstTabAccountTo(_ accountId: String, animated: Bool) {
        guard let first = tabsViewModel.displayTabs.first, let vc = tabViewControllers[first] else { return }

        switch vc {
        case let tokensVC as WalletTokensVC:
            tokensVC.switchAccountTo(accountId: accountId, animated: animated)
        case let nftsVC as NftsVC:
            nftsVC.switchAccountTo(accountId: accountId, animated: animated)
        default:
            break
        }
    }
    
    public func interactivelySwitchAccountTo(accountId: String) {
        editingNavigator.cancelEditing()
        
        tabsViewModel.changeAccountTo(accountId: accountId)
        switchIncomingFirstTabAccountTo(accountId, animated: true)
        
        walletAssetsView.tabsContainer.handleSegmentChange(to: 0, animated: true)
    }
        
    func _displayTabsChanged(force: Bool) {
        nftsVCManager.beginUpdate()
        defer {
            nftsVCManager.endUpdate()
        }
        
        let displayTabs = tabsViewModel.displayTabs
        var tabViewControllersToRemove = tabViewControllers
        var newTabsViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]
        
        for tab in displayTabs {
            if let oldVC = tabViewControllersToRemove.removeValue(forKey: tab) {
                newTabsViewControllers[tab] = oldVC
            } else {
                let vc = makeViewControllerForTab(tab)
                addChild(vc)
                _ = vc.view
                newTabsViewControllers[tab] = vc
                vc.didMove(toParent: self)
            }
        }
        
        self.tabViewControllers = newTabsViewControllers
                
        let vcs = displayTabs.map { tabViewControllers[$0]! }
        let items: [WSegmentedPagerItem] = displayTabs.enumerated().map { index, tab in
            let contextMenuProvider = getContextMenuProvider(tab: tab)
            return switch tab {
            case .tokens:
                WSegmentedPagerItem(
                    id: "tokens",
                    title: lang("Assets"),
                    contextMenuProvider: contextMenuProvider,
                    isDeletable: false,
                    viewController: vcs[index],
                )
            case .nfts:
                WSegmentedPagerItem(
                    id: "nfts",
                    title: lang("Collectibles"),
                    contextMenuProvider: contextMenuProvider,
                    isDeletable: false,
                    viewController: vcs[index],
                )
            case .nftCollectionFilter(let filter):
                WSegmentedPagerItem(
                    id: filter.stringValue,
                    title: filter.displayTitle,
                    contextMenuProvider: contextMenuProvider,
                    viewController: vcs[index],
                )
            }
        }
        walletAssetsView.tabsContainer.replace(
            items: items,
            force: force
        )
        
        // now remove "orphaned" tabs
        tabViewControllersToRemove.values.forEach { removeChild($0) }

        if view.window != nil {
            activateEmptyStateAnimationForSelectedPage()
            activateNftAnimationForSelectedPage()
        }
    }
    
    private func makeViewControllerForTab(_ tab: DisplayAssetTab) -> any WSegmentedControllerContent & UIViewController {
        switch tab {
        case .tokens, .nfts:
            fatalError("created once")
        case .nftCollectionFilter(let filter):
            return NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .compact, filter: filter)
        }
    }
    
    public override func loadView() {
        let tokensVC = WalletTokensVC(accountSource: accountSource, mode: .compact)
        self.tokensVC = tokensVC
        addChild(tokensVC)
        tokensVC.didMove(toParent: self)

        let nftsVC = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .compact, filter: .none)
        self.nftsVC = nftsVC
        addChild(nftsVC)
        nftsVC.didMove(toParent: self)

        view = WalletAssetsView(walletTokensVC: tokensVC, walletCollectiblesView: nftsVC)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        tokensVC?.onHeightChanged = { [weak self] animated in
            self?.headerHeightChanged(animated: animated)
        }
        
        nftsVCManager.restoreTabsOnReorderCanceling = true
        nftsVCManager.onStateChange = { [weak self] oldState, newState in
            guard let self else { return }
            
            if oldState.editingState != newState.editingState {
                if newState.editingState == .reordering {
                    self.walletAssetsView.tabsContainer.model.startReordering()
                } else {
                    self.walletAssetsView.tabsContainer.model.stopReordering()
                }
            }
            
            if newState.heightChanged(since: oldState) {
                self.headerHeightChanged(animated: true)
            }
        }
        
        walletAssetsView.onScrollingOffsetChanged = { [weak self] _ in
            guard let self else { return }
            self.headerHeightChanged(animated: true)
            
            if self.editingNavigator.state.editingState == .selection {
                self.editingNavigator.cancelEditing()
            }
        }
        
        walletAssetsView.layer.cornerRadius = S.homeInsetSectionCornerRadius
        walletAssetsView.layer.masksToBounds = true

        walletAssetsView.tabsContainer.onWillStartTransition = { [weak self] in
            self?.pauseAllEmptyStateAnimations()
            self?.pauseAllNftAnimations()
        }
        walletAssetsView.tabsContainer.onDidStartDragging = { [weak self] in
            self?.pauseAllEmptyStateAnimations()
            self?.pauseAllNftAnimations()
        }
        walletAssetsView.tabsContainer.onDidEndScrolling = { [weak self] in
            self?.activateEmptyStateAnimationForSelectedPage()
            self?.activateNftAnimationForSelectedPage()
        }
        
        updateTheme()
        
        tabViewControllers[.tokens] = tokensVC
        tabViewControllers[.nfts] = nftsVC

        WalletCoreData.add(eventObserver: self)
        
        tabsViewModel.delegate = self
        _displayTabsChanged(force: true)
                
        walletAssetsView.tabsContainer.model.onItemsReorder = { [weak self] items in
            guard let self else { return }            
            let collections = NftStore.getCollections(accountId: accountIdProvider.accountId).collections
            let displayTabs: [DisplayAssetTab] = items.compactMap { item in
                switch item.id {
                case "tokens": return .tokens
                case "nfts": return .nfts
                default:
                    let giftsFilter =  NftCollectionFilter.telegramGifts
                    if item.id == giftsFilter.stringValue {
                        return .nftCollectionFilter(giftsFilter)
                    }
                    if let collection = collections.first(where: { $0.id == item.id }) {
                        let filter = NftCollectionFilter.collection(collection)
                        assert(filter.stringValue == item.id)
                        return .nftCollectionFilter(filter)
                    }
                    assertionFailure("Unable to find a collection for the tab with id: \(item.id)")
                    return nil
                }
            }
            try? await self.tabsViewModel.setOrder(displayTabs: displayTabs)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateEmptyStateAnimationForSelectedPage()
        activateNftAnimationForSelectedPage()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseAllEmptyStateAnimations()
        pauseAllNftAnimations()
    }
    
    private func updateTheme() {
        walletAssetsView.backgroundColor = .air.groupedItem
    }

    nonisolated public func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .accountChanged:
                if accountSource == .current {
                    walletAssetsView.selectedIndex = 0
                }
            case .applicationWillEnterForeground:
                view.setNeedsLayout()
                view.setNeedsDisplay()
            default:
                break
            }
        }
    }
    
    private func headerHeightChanged(animated: Bool) {
        delegate?.walletAssetDidChangeHeight(animated: animated)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 0, width != lastMeasuredWidth else { return }
        lastMeasuredWidth = width
        headerHeightChanged(animated: false)
    }

    private var heightMeasurementWidth: CGFloat {
        let candidates: [CGFloat] = [
            walletAssetsView.tabsContainer.bounds.width,
            walletAssetsView.bounds.width,
            lastMeasuredWidth,
        ]
        return candidates.first(where: { $0 > 0 }) ?? 0
    }

    private func prepareForHeightCalculation(_ content: any WSegmentedControllerContent) {
        let vc = content as UIViewController
        vc.loadViewIfNeeded()

        guard vc.view.superview == nil else { return }
        let width = heightMeasurementWidth
        guard width > 0 else { return }

        let targetSize = CGSize(width: width, height: max(vc.view.bounds.height, 1))
        guard vc.view.bounds.size != targetSize else { return }

        vc.view.frame = CGRect(origin: .zero, size: targetSize)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
    }

    private func calculatedHeight(for content: any WSegmentedControllerContent) -> CGFloat {
        prepareForHeightCalculation(content)
        return content.calculateHeight(isHosted: false)
    }

    private func forEachEmptyStateAnimationController(_ body: (WalletAssetsEmptyStateAnimationControlling) -> Void) {
        var processedIds = Set<ObjectIdentifier>()
        for viewController in walletAssetsView.tabsContainer.viewControllers {
            guard let animatable = viewController as? WalletAssetsEmptyStateAnimationControlling else {
                continue
            }
            let id = ObjectIdentifier(animatable as AnyObject)
            guard processedIds.insert(id).inserted else {
                continue
            }
            body(animatable)
        }
    }

    private func pauseAllEmptyStateAnimations() {
        forEachEmptyStateAnimationController {
            $0.setWalletAssetsEmptyStateAnimationActive(false)
        }
    }

    private func forEachNftAnimationController(_ body: (NftAnimationPlaybackControlling) -> Void) {
        var processedIds = Set<ObjectIdentifier>()
        for viewController in walletAssetsView.tabsContainer.viewControllers {
            guard let animatable = viewController as? NftAnimationPlaybackControlling else {
                continue
            }
            let id = ObjectIdentifier(animatable as AnyObject)
            guard processedIds.insert(id).inserted else {
                continue
            }
            body(animatable)
        }
    }

    private func pauseAllNftAnimations() {
        forEachNftAnimationController {
            $0.setNftAnimationPlaybackActive(false)
        }
    }

    private func activateEmptyStateAnimationForSelectedPage() {
        let selectedControllerID = walletAssetsView.tabsContainer.selectedIndex
            .flatMap { index -> (WalletAssetsEmptyStateAnimationControlling)? in
                let viewControllers = walletAssetsView.tabsContainer.viewControllers
                guard viewControllers.indices.contains(index) else {
                    return nil
                }
                return viewControllers[index] as? WalletAssetsEmptyStateAnimationControlling
            }
            .map { ObjectIdentifier($0 as AnyObject) }
        forEachEmptyStateAnimationController { controller in
            controller.setWalletAssetsEmptyStateAnimationActive(selectedControllerID == ObjectIdentifier(controller as AnyObject))
        }
    }

    private func activateNftAnimationForSelectedPage() {
        let selectedControllerID = walletAssetsView.tabsContainer.selectedIndex
            .flatMap { index -> (NftAnimationPlaybackControlling)? in
                let viewControllers = walletAssetsView.tabsContainer.viewControllers
                guard viewControllers.indices.contains(index) else {
                    return nil
                }
                return viewControllers[index] as? NftAnimationPlaybackControlling
            }
            .map { ObjectIdentifier($0 as AnyObject) }
        forEachNftAnimationController { controller in
            controller.setNftAnimationPlaybackActive(selectedControllerID == ObjectIdentifier(controller as AnyObject))
        }
    }
    
    public func computedHeight() -> CGFloat {
        let progress = walletAssetsView.scrollProgress
        
        var newItemsHeight: CGFloat
        
        let vcs = walletAssetsView.tabsContainer.viewControllers
        if vcs.isEmpty {
            newItemsHeight = 44
        } else if vcs.count == 1 {
            newItemsHeight = 44 + calculatedHeight(for: vcs[0])
        } else {
            let lo = max(0, min(vcs.count - 2, Int(progress)))
            newItemsHeight = 44 + interpolate(
                from: calculatedHeight(for: vcs[lo]),
                to: calculatedHeight(for: vcs[lo + 1]),
                progress: clamp(progress - CGFloat(lo), min: 0, max: 1)
            )
        }
        
        newItemsHeight += 16
        
        return newItemsHeight
    }
    
    public var skeletonViewCandidates: [UIView] {
        walletAssetsView.walletTokensVC.skeletonViewCandidates
    }
    
    private func onSegmentsReorder() {
        nftsVCManager.startReordering()
    }    
}

extension WalletAssetsVC: WalletAssetsViewModelDelegate {
    public func walletAssetModelDidChangeDisplayTabs() {
        _displayTabsChanged(force: false)
    }
}
