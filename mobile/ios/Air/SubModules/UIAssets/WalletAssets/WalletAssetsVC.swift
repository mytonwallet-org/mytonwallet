
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-WalletAssets")

@MainActor public protocol WalletAssetsDelegate: AnyObject {
    func walletAssetDidChangeHeight(animated: Bool)
    func walletAssetDidChangeReorderingState()
}

@MainActor public final class WalletAssetsVC: WViewController, WalletCoreData.EventsObserver, Sendable {
    private var walletAssetsView: WalletAssetsView { view as! WalletAssetsView }
    
    public weak var delegate: (any WalletAssetsDelegate)?
    
    public var isReordering: Bool { tabsViewModel.isReordering }
    
    private var tokensVC: WalletTokensVC?
    private var nftsVC: NftsVC?
    
    private let accountIdProvider: AccountIdProvider
    private var accountSource: AccountSource { accountIdProvider.source }
    
    @AppStorage("debug_hideSegmentedControls") private var hideSegmentedControls = false
    
    private let tabsViewModel: WalletAssetsViewModel
    
    private var tabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]
    private var lastMeasuredWidth: CGFloat = 0
    
    private var menuContexts: [DisplayAssetTab: MenuContext] = [:]
    
    private func getMenuContext(tab: DisplayAssetTab) -> MenuContext {
        if let ctx = menuContexts[tab] {
            return ctx
        } else {
            let ctx = MenuContext()
            ctx.sourceView = self.walletAssetsView.tabsContainer.segmentedControl
            switch tab {
            case .tokens:
                configureTokensMenu(menuContext: ctx, onReorder: { [weak self] in self?.onSegmentsReorder() })
            case .nfts:
                configureCollectiblesMenu(accountSource: accountSource, menuContext: ctx, onReorder: { [weak self] in self?.onSegmentsReorder() })
            case .nftCollectionFilter(let filter):
                configureNftCollectionMenu(menuContext: ctx, onReorder: { [weak self] in self?.onSegmentsReorder() }, onHide: { [weak self] in
                    Task {
                        try? await self?.tabsViewModel.setIsFavorited(filter: filter, isFavorited: false)
                    }
                })
            }
            menuContexts[tab] = ctx
            return ctx
        }
    }
    
    public init(accountSource: AccountSource) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
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
        stopReordering(isCanceled: true)
        
        tabsViewModel.changeAccountTo(accountId: accountId)
        switchIncomingFirstTabAccountTo(accountId, animated: true)
        
        walletAssetsView.tabsContainer.handleSegmentChange(to: 0, animated: true)
    }
        
    func _displayTabsChanged(force: Bool) {
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
            let menuContext = getMenuContext(tab: tab)
            return switch tab {
            case .tokens:
                WSegmentedPagerItem(
                    id: "tokens",
                    title: lang("Assets"),
                    menuContext: menuContext,
                    isDeletable: false,
                    viewController: vcs[index],
                )
            case .nfts:
                WSegmentedPagerItem(
                    id: "nfts",
                    title: lang("Collectibles"),
                    menuContext: menuContext,
                    isDeletable: false,
                    viewController: vcs[index],
                )
            case .nftCollectionFilter(let filter):
                WSegmentedPagerItem(
                    id: filter.stringValue,
                    title: filter.displayTitle,
                    menuContext: menuContext,
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
    }
    
    private func makeViewControllerForTab(_ tab: DisplayAssetTab) -> any WSegmentedControllerContent & UIViewController {
        switch tab {
        case .tokens, .nfts:
            fatalError("created once")
        case .nftCollectionFilter(let filter):
            let vc = NftsVC(accountSource: accountSource, mode: .compact, filter: filter)
            vc.delegate = self
            return vc
        }
    }
    
    public override func loadView() {
        let tokensVC = WalletTokensVC(accountSource: accountSource, mode: .compact)
        self.tokensVC = tokensVC
        addChild(tokensVC)
        tokensVC.didMove(toParent: self)

        let nftsVC = NftsVC(accountSource: accountSource, mode: .compact, filter: .none)
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
        nftsVC?.delegate = self
        walletAssetsView.onScrollingOffsetChanged = { [weak self] _ in
            self?.headerHeightChanged(animated: true)
        }
        
        walletAssetsView.layer.cornerRadius = S.homeInsetSectionCornerRadius
        walletAssetsView.layer.masksToBounds = true
        
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
                case "super:telegram-gifts": return .nftCollectionFilter(.telegramGifts)
                default:
                    if let collection = collections.first(where: { $0.address == item.id }) {
                        return .nftCollectionFilter(.collection(collection))
                    }
                    return nil
                }
            }
            try? await self.tabsViewModel.setOrder(displayTabs: displayTabs)
        }
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
        return content.calculatedHeight
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
        tabsViewModel.startOrdering()
    }
    
    /// Called from parent (`HomeVC`), also called as a reaction on account switching
    public func stopReordering(isCanceled: Bool) {
        tabsViewModel.stopReordering(isCanceled: isCanceled, restoreTabsOnCancel: true)
    }
}

extension WalletAssetsVC: WalletAssetsViewModelDelegate {
    private func forEachNftsVC(_ body: (NftsVC) -> Void)  {
        var processedIds = Set<ObjectIdentifier>()

        if let nftsVC {
            processedIds.insert(ObjectIdentifier(nftsVC))
            body(nftsVC)
        }

        for vc in tabViewControllers.values {
            guard let vc = vc as? NftsVC else { continue }
            let id = ObjectIdentifier(vc)
            guard processedIds.insert(id).inserted else { continue }
            body(vc)
        }
    }
    
    public func walletAssetModelDidStartReordering() {
        delegate?.walletAssetDidChangeReorderingState()
        forEachNftsVC {
            $0.startReordering()
        }
        
        walletAssetsView.tabsContainer.model.startReordering()
    }
    
    public func walletAssetModelDidStopReordering(isCanceled: Bool) {
        delegate?.walletAssetDidChangeReorderingState()
        forEachNftsVC {
            $0.stopReordering(isCanceled: isCanceled)
        }
        
        walletAssetsView.tabsContainer.model.stopReordering()
    }
        
    public func walletAssetModelDidChangeDisplayTabs() {
        _displayTabsChanged(force: false)
    }
}

extension WalletAssetsVC: NftsViewControllerDelegate {
    public func nftsViewControllerDidChangeReorderingState(_ vc: NftsVC) {
        // nothing. The tabsViewModel will handle all changes itself
    }
    
    public func nftsViewControllerRequestReordering(_ vc: NftsVC) {
        tabsViewModel.startOrdering()
    }
    
    public func nftsViewControllerDidChangeHeightAnimated(_ animated: Bool) {
        headerHeightChanged(animated: animated)
    }
}
