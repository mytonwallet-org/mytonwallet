
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-WalletAssets")

@MainActor public protocol WalletAssetsDelegate: AnyObject {
    func headerHeightChanged(animated: Bool)
}

@MainActor public final class WalletAssetsVC: WViewController, WalletCoreData.EventsObserver, WalletAssetsViewModelDelegate, Sendable {
    
    private let compactMode: Bool
    
    var walletAssetsView: WalletAssetsView { view as! WalletAssetsView }
    public weak var delegate: (any WalletAssetsDelegate)?
    
    private var tokensVC: WalletTokensVC?
    private var nftsVC: NftsVC?
    private var currentAccountId: String?
    
    var tabsViewModel: WalletAssetsViewModel
    
    var tabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]
    
    private var menuContexts: [DisplayAssetTab: MenuContext] = [:]
    
    private func getMenuContext(tab: DisplayAssetTab) -> MenuContext {
        if let ctx = menuContexts[tab] {
            return ctx
        } else {
            let ctx = MenuContext()
            menuContexts[tab] = ctx
            return ctx
        }
    }
    
    public init(compactMode: Bool = true) {
        self.compactMode = compactMode
        self.tabsViewModel = WalletAssetsViewModel()
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func displayTabsChanged() {
        _displayTabsChanged(force: false)
    }
    
    func _displayTabsChanged(force: Bool) {
        let displayTabs = tabsViewModel.displayTabs
        for tab in displayTabs {
            if tabViewControllers[tab] == nil {
                let vc = makeViewControllerForTab(tab)
                addChild(vc)
                _ = vc.view
                tabViewControllers[tab] = vc
                vc.didMove(toParent: vc)
            }
        }
        let vcs = displayTabs.map { tabViewControllers[$0]! }
        let items: [SegmentedControlItem] = displayTabs.enumerated().map { index, tab in
            let menuContext = getMenuContext(tab: tab)
            return switch tab {
            case .tokens:
                SegmentedControlItem(
                    index: index,
                    id: "tokens",
                    content: AnyView(
                        TokensItem(menuContext: menuContext) {
                            Text(lang("Assets"))
                        }
                    )
                )
            case .nfts:
                SegmentedControlItem(
                    index: index,
                    id: "nfts",
                    content: AnyView(
                        AllNftsItem(menuContext: menuContext)
                    )
                )
            case .nftCollectionFilter(let filter):
                SegmentedControlItem(
                    index: index,
                    id: filter.stringValue,
                    content: AnyView(
                        NftCollectionItem(
                            menuContext: menuContext,
                            hideAction: { [weak self] in
                                Task {
                                    try? await self?.tabsViewModel.setIsFavorited(filter: filter, isFavorited: false)
                                }
                            }) {
                                Text(filter.displayTitle)
                            }
                    )
                )
            }
        }
        walletAssetsView.segmentedController.replace(
            viewControllers: vcs,
            items: items,
            force: force
        )
    }
    
    func makeViewControllerForTab(_ tab: DisplayAssetTab) -> any WSegmentedControllerContent & UIViewController {
        switch tab {
        case .tokens, .nfts:
            fatalError("created once")
        case .nftCollectionFilter(let filter):
            let vc = NftsVC(compactMode: compactMode, filter: filter)
            vc.onHeightChanged = { [weak self] animated in
                self?.delegate?.headerHeightChanged(animated: animated)
            }
            return vc
        }
    }
    
    public override func loadView() {
        let tokensVC = WalletTokensVC(compactMode: true)
        self.tokensVC = tokensVC
        addChild(tokensVC)
        tokensVC.didMove(toParent: self)
        
        let nftsVC = NftsVC(compactMode: true, filter: .none)
        self.nftsVC = nftsVC
        addChild(nftsVC)
        nftsVC.didMove(toParent: self)
        
        view = WalletAssetsView(walletTokensView: tokensVC.tokensView, walletCollectiblesView: nftsVC, onScrollingOffsetChanged: nil)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        tokensVC?.onHeightChanged = { [weak self] animated in
            self?.headerHeightChanged(animated: animated)
        }
        nftsVC?.onHeightChanged = { [weak self] animated in
            self?.headerHeightChanged(animated: animated)
        }
        walletAssetsView.onScrollingOffsetChanged = { [weak self] offset in
            self?.delegate?.headerHeightChanged(animated: false)
//            self?.nftsVC?.updateIsVisible(offset >= 0.2)
        }        
        
        walletAssetsView.layer.cornerRadius = S.homeInsetSectionCornerRadius
        walletAssetsView.layer.masksToBounds = true
        
        updateTheme()
        
        tabViewControllers[.tokens] = tokensVC?.tokensView
        tabViewControllers[.nfts] = nftsVC

        WalletCoreData.add(eventObserver: self)
        
        tabsViewModel.delegate = self
        _displayTabsChanged(force: true)
        
        let collections = NftStore.getCollections(accountId: AccountStore.accountId ?? "").collections
        
        walletAssetsView.segmentedController.model.onItemsReordered = { items in
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
            try! await self.tabsViewModel.setOrder(displayTabs: displayTabs)
        }
    }
    
    public override func updateTheme() {
        walletAssetsView.backgroundColor = WTheme.groupedItem
    }

    nonisolated public func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .accountChanged:
                walletAssetsView.selectedIndex = 0
//            case .nftsChanged(let accountId):
//            case .nftFeaturedCollectionChanged(let accountId):
            case .applicationWillEnterForeground:
                view.setNeedsLayout()
                view.setNeedsDisplay()
            default:
                break
            }
        }
    }
    
    private func headerHeightChanged(animated: Bool) {
        delegate?.headerHeightChanged(animated: animated)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for ctx in menuContexts.values { // reference type
            ctx.sourceView = self.walletAssetsView.segmentedController.newSegmentedControl
        }
    }
    
    public func computedHeight() -> CGFloat {
        let progress = walletAssetsView.scrollProgress
        
        var newItemsHeight: CGFloat
        guard let vcs = walletAssetsView.segmentedController.viewControllers else { return 0 }
        
        let lo = max(0, min(vcs.count - 2, Int(progress)))
        newItemsHeight = 44 + interpolate(
            from: vcs[lo].calculatedHeight,
            to: vcs[lo + 1].calculatedHeight,
            progress: clamp(progress - CGFloat(lo), min: 0, max: 1)
        )
        
        newItemsHeight += 16
        
        return newItemsHeight
    }
    
    public var skeletonViewCandidates: [UIView] {
        walletAssetsView.walletTokensView.visibleCells
    }
}
