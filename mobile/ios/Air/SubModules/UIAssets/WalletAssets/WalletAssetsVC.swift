
import ContextMenuKit
import Perception
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor public protocol WalletAssetsDelegate: AnyObject {
    func walletAssetDidChangeHeight(animated: Bool)
    func walletAssetDidChangeDisplayTabs(animated: Bool)
}

@MainActor public final class WalletAssetsVC: WViewController, WalletCoreData.EventsObserver, Sendable {
    private var walletAssetsView: WalletAssetsView { view as! WalletAssetsView }
    
    public weak var delegate: (any WalletAssetsDelegate)?
    
    public var editingNavigator: NftsEditingNavigator { nftsVCManager.editingNavigator  }

    private var nftsVC: NftsVC?
    private let nftsVCManager: NftsVCManager
    
    private let accountIdProvider: AccountIdProvider
    private var accountSource: AccountSource { accountIdProvider.source }
    
    private let tabsViewModel: WalletAssetsViewModel
    
    private var tabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]
    private var lastMeasuredWidth: CGFloat = 0
    private var calculatedTabHeights: [ObjectIdentifier: CGFloat] = [:]
    private var lastReportedHasVisibleContent: Bool?
    
    private lazy var tabContextMenuProviders = WalletAssetsTabContextMenuProviders(
        accountSource: accountSource,
        nftsVCManager: nftsVCManager,
        sourceViewProvider: { [weak self] in
            self?.walletAssetsView.tabsContainer.segmentedControl
        },
        onReorder: { [weak self] in
            self?.onSegmentsReorder()
        },
        onSelectTab: { [weak self] tab in
            guard let self,let index = tabsViewModel.displayTabs.firstIndex(of: tab) else { return }
            walletAssetsView.tabsContainer.handleSegmentChange(to: index, animated: true)
        }
    )

    public var tokensMenu: UIMenu? {
        tabContextMenuProviders.makeTokensMenu()
    }

    private func makePagerItem(
        tab: DisplayAssetTab,
        viewController: any WSegmentedControllerContent
    ) -> WSegmentedPagerItem {
        WSegmentedPagerItem(
            id: tab.segmentedControlItemId,
            title: tab.segmentedControlTitle,
            contextMenuProvider: tabContextMenuProviders.provider(for: tab),
            hidesMenuIcon: true,
            isDeletable: tab.isDeletableSegment,
            viewController: viewController
        )
    }
    
    public init(accountSource: AccountSource) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.tabsViewModel = WalletAssetsViewModel(accountSource: accountSource, includesTokens: false)
        self.nftsVCManager = NftsVCManager(tabsViewModel: tabsViewModel)
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func switchIncomingFirstTabAccountTo(_ accountId: String) {
        guard let first = tabsViewModel.displayTabs.first, let vc = tabViewControllers[first] else { return }

        switch vc {
        case let nftsVC as NftsVC:
            nftsVC.switchAccountTo(accountId: accountId, animated: false)
        default:
            break
        }
    }
    
    private var displayedAccountId: String?

    private func observeAccountId() {
        withPerceptionTracking {
            _ = accountIdProvider.accountId
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.accountIdChanged()
                self?.observeAccountId()
            }
        }
    }

    private func accountIdChanged() {
        let accountId = accountIdProvider.accountId
        guard accountId != displayedAccountId else { return }
        displayedAccountId = accountId
        editingNavigator.cancelEditing()
        walletAssetsView.tabsContainer.handleSegmentChange(to: 0, animated: true)
    }


    func _displayTabsChanged(force: Bool, animated: Bool) {
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
        invalidateCalculatedTabHeights()
                
        let vcs = displayTabs.map { tabViewControllers[$0]! }
        let items: [WSegmentedPagerItem] = displayTabs.enumerated().map { index, tab in
            makePagerItem(tab: tab, viewController: vcs[index])
        }
        walletAssetsView.tabsContainer.isSegmentedControlHidden = items.count == 1
        walletAssetsView.tabsContainer.replace(
            items: items,
            force: force,
            animated: animated
        )
        lastReportedHasVisibleContent = hasVisibleContent
        
        // now remove "orphaned" tabs
        tabViewControllersToRemove.values.forEach { removeChild($0) }

        if view.window != nil {
            activateEmptyStateAnimationForSelectedPage()
            activateNftAnimationForSelectedPage()
        }
    }
    
    private func makeViewControllerForTab(_ tab: DisplayAssetTab) -> any WSegmentedControllerContent & UIViewController {
        switch tab {
        case .tokens:
            fatalError("Tokens are presented as a separate Home section")
        case .nfts:
            return nftsVC!
        case .nftCollectionFilter(let filter):
            return makeNftsViewController(filter: filter)
        }
    }
    
    private func makeNftsViewController(filter: NftCollectionFilter) -> NftsVC {
        let vc = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .compact, filter: filter)
        let tab: DisplayAssetTab = filter == .none ? .nfts : .nftCollectionFilter(filter)
        vc.showAllMenuProvider = tabContextMenuProviders.provider(for: tab)
        return vc
    }

    public override func loadView() {
        let nftsVC = makeNftsViewController(filter: .none)
        self.nftsVC = nftsVC
        addChild(nftsVC)
        nftsVC.didMove(toParent: self)

        view = WalletAssetsView(walletCollectiblesView: nftsVC)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
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
            
            let hasVisibleContent = self.hasVisibleContent
            let visibilityChanged = self.lastReportedHasVisibleContent.map { $0 != hasVisibleContent } == true
            self.lastReportedHasVisibleContent = hasVisibleContent
            let heightChanged = newState.heightChanged(since: oldState)
            if visibilityChanged || heightChanged {
                self.invalidateCalculatedTabHeights()
            }
            if visibilityChanged {
                self.delegate?.walletAssetDidChangeDisplayTabs(animated: true)
            } else if heightChanged {
                self.headerHeightChanged(animated: true)
            }
        }
        
        walletAssetsView.onScrollingOffsetChanged = { [weak self] _, animated in
            guard let self else { return }
            self.headerHeightChanged(animated: animated)
            
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

        tabViewControllers[.nfts] = nftsVC

        WalletCoreData.add(eventObserver: self)
        displayedAccountId = accountIdProvider.accountId
        observeAccountId()
        
        tabsViewModel.delegate = self
        _displayTabsChanged(force: true, animated: false)
                
        walletAssetsView.tabsContainer.model.onItemsReorder = { [weak self] (items: [SegmentedControlItem]) in
            guard let self else { return }
            let displayTabs: [DisplayAssetTab] = items.compactMap { item in
                DisplayAssetTab.fromSegmentedControlItemId(item.id, accountId: self.accountIdProvider.accountId)
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
        invalidateCalculatedTabHeights()
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
        let id = ObjectIdentifier(content as AnyObject)
        if let height = calculatedTabHeights[id] {
            return height
        }
        prepareForHeightCalculation(content)
        let height = content.calculateHeight(isHosted: false)
        calculatedTabHeights[id] = height
        return height
    }

    private func invalidateCalculatedTabHeights() {
        calculatedTabHeights.removeAll(keepingCapacity: true)
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
        let contentTopInset = walletAssetsView.tabsContainer.contentTopInset
        
        var newItemsHeight: CGFloat
        
        let vcs = walletAssetsView.tabsContainer.viewControllers
        if vcs.isEmpty {
            newItemsHeight = 0
        } else if vcs.count == 1 {
            newItemsHeight = contentTopInset + calculatedHeight(for: vcs[0])
        } else {
            let lo = max(0, min(vcs.count - 2, Int(progress)))
            newItemsHeight = contentTopInset + interpolate(
                from: calculatedHeight(for: vcs[lo]),
                to: calculatedHeight(for: vcs[lo + 1]),
                progress: clamp(progress - CGFloat(lo), min: 0, max: 1)
            )
        }
        
        newItemsHeight += 16
        
        return newItemsHeight
    }

    public var hasVisibleContent: Bool {
        Self.shouldShowContent(
            hasDisplayTabs: !tabsViewModel.displayTabs.isEmpty,
            visibleNftCount: NftStore.getAccountShownNfts(accountId: accountIdProvider.accountId)?.count
        )
    }

    static func shouldShowContent(hasDisplayTabs: Bool, visibleNftCount: Int?) -> Bool {
        hasDisplayTabs && visibleNftCount != 0
    }
    
    private func onSegmentsReorder() {
        nftsVCManager.startReordering()
    }    
}

extension WalletAssetsVC: WalletAssetsViewModelDelegate {
    public func walletAssetModelDidChangeDisplayTabs(dueToAccountSwitch: Bool) {
        _displayTabsChanged(force: dueToAccountSwitch, animated: dueToAccountSwitch)
        if dueToAccountSwitch {
            // Runs after the tabs were rebuilt for the new account, so the first tab's reused
            // controller is switched regardless of how the account observers were ordered
            switchIncomingFirstTabAccountTo(accountIdProvider.accountId)
        }
        delegate?.walletAssetDidChangeDisplayTabs(animated: dueToAccountSwitch)
    }
}
