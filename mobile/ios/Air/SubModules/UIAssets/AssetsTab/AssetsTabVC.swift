//
//  AssetsTabVC.swift
//
//  Created by Sina on 10/24/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

public class AssetsTabVC: WViewController, WalletCoreData.EventsObserver {
    private let accountIdProvider: AccountIdProvider
    private var accountSource: AccountSource { accountIdProvider.source }

    private var segmentedController: WSegmentedController!
    private let defaultTab: DisplayAssetTab
    private let tabsViewModel: WalletAssetsViewModel
    private let nftsVCManager: NftsVCManager
    private var tabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]

    private lazy var tabContextMenuProviders = WalletAssetsTabContextMenuProviders(
        accountSource: accountSource,
        nftsVCManager: nftsVCManager,
        sourceViewProvider: { [weak self] in
            self?.segmentedController?.segmentedControl
        },
        onReorder: { [weak self] in
            self?.onSegmentsReorder()
        },
        onSelectTab: { [weak self] tab in
            guard let self else { return }
            show(accountSource: accountSource, tab: tab, animated: true)
        },
        includesTokenLimitActions: false
    )

    public init(accountSource: AccountSource, defaultTab: DisplayAssetTab) {
        let tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.defaultTab = defaultTab
        self.tabsViewModel = tabsViewModel
        self.nftsVCManager = NftsVCManager(tabsViewModel: tabsViewModel)
        super.init(nibName: nil, bundle: nil)
    }

    public static func canShow(accountSource: AccountSource, tab: DisplayAssetTab) -> Bool {
        let tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
        return hasDisplayTab(tab, in: tabsViewModel.displayTabs)
    }

    public func canShow(accountSource: AccountSource, tab: DisplayAssetTab) -> Bool {
        let accountIdProvider = AccountIdProvider(source: accountSource)
        return accountIdProvider.accountId == self.accountIdProvider.accountId && Self.hasDisplayTab(tab, in: tabsViewModel.displayTabs)
    }

    @discardableResult
    public func show(accountSource: AccountSource, tab: DisplayAssetTab, animated: Bool) -> Bool {
        guard canShow(accountSource: accountSource, tab: tab) else { return false }
        loadViewIfNeeded()
        guard let segmentedController,
              let index = segmentedController.model.getItemIndexById(itemId: tab.segmentedControlItemId) else {
            return false
        }
        segmentedController.handleSegmentChange(to: index, animated: animated)
        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        default:
            break
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
    
    func setupViews() {
        if let sheet = self.sheetPresentationController {
            sheet.configureFullScreen(true)
            sheet.configureAllowsInteractiveDismiss(true)
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = true
            }
        }

        nftsVCManager.restoreTabsOnReorderCanceling = true

        let displayTabs = tabsViewModel.displayTabs
        segmentedController = WSegmentedController(
            items: makeSegmentedItems(displayTabs: displayTabs),
            defaultItemId: defaultItemId(displayTabs: displayTabs),
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            delegate: self
        )
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.separator.isHidden = true
        segmentedController.blurView.isHidden = true
        
        updateState()

        addCustomNavigationBarBackground(color: .air.pickerBackground)
        segmentedController.segmentedControl.embed(in: navigationItem)
        
        view.backgroundColor = .air.pickerBackground

        nftsVCManager.onStateChange = { [weak self] oldState, newState in
            guard let self, let segmentedController = self.segmentedController else { return }
            guard oldState.editingState != newState.editingState else { return }
            if newState.editingState == .reordering {
                segmentedController.model.startReordering()
            } else {
                segmentedController.model.stopReordering()
            }
        }

        segmentedController.model.onItemsReorder = { [weak self] items in
            guard let self else { return }
            let displayTabs: [DisplayAssetTab] = items.compactMap { item in
                DisplayAssetTab.fromSegmentedControlItemId(item.id, accountId: self.accountIdProvider.accountId)
            }
            try? await self.tabsViewModel.setOrder(displayTabs: displayTabs)
        }
        
        nftsVCManager.editingNavigator.onStateChange = { [weak self] _, _ in
            self?.updateState()
        }

        tabsViewModel.delegate = self
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sheet = self.sheetPresentationController {
            sheet.configureAllowsInteractiveDismiss(true)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateNftAnimationForSelectedPage()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseAllNftAnimations()
    }
    
    private func defaultItemId(displayTabs: [DisplayAssetTab]) -> String? {
        let requestedItemId = defaultTab.segmentedControlItemId
        return displayTabs.contains(where: { $0.segmentedControlItemId == requestedItemId })
            ? requestedItemId
            : displayTabs.first?.segmentedControlItemId
    }

    private static func hasDisplayTab(_ tab: DisplayAssetTab, in displayTabs: [DisplayAssetTab]) -> Bool {
        let itemId = tab.segmentedControlItemId
        return displayTabs.contains { $0.segmentedControlItemId == itemId }
    }

    private func makeSegmentedItems(displayTabs: [DisplayAssetTab]) -> [SegmentedControlItem] {
        displayTabs.map { tab in
            let viewController = viewController(for: tab)
            return SegmentedControlItem(
                id: tab.segmentedControlItemId,
                title: tab.segmentedControlTitle,
                contextMenuProvider: tabContextMenuProviders.provider(for: tab),
                isDeletable: tab.isDeletableSegment,
                viewController: viewController
            )
        }
    }

    private func viewController(for tab: DisplayAssetTab) -> any WSegmentedControllerContent {
        if let viewController = tabViewControllers[tab] {
            return viewController
        }

        let viewController: any WSegmentedControllerContent
        switch tab {
        case .tokens:
            viewController = WalletTokensVC(accountSource: accountSource, mode: .expanded)
        case .nfts:
            viewController = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .regular, filter: .none)
        case let .nftCollectionFilter(filter):
            viewController = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .regular, filter: filter)
        }

        addChild(viewController)
        tabViewControllers[tab] = viewController
        viewController.didMove(toParent: self)
        return viewController
    }

    private func displayTabsChanged(force: Bool) {
        nftsVCManager.beginUpdate()
        defer {
            nftsVCManager.endUpdate()
        }

        let displayTabs = tabsViewModel.displayTabs
        var tabViewControllersToRemove = tabViewControllers
        var newTabViewControllers: [DisplayAssetTab: any WSegmentedControllerContent] = [:]

        for tab in displayTabs {
            if let oldVC = tabViewControllersToRemove.removeValue(forKey: tab) {
                newTabViewControllers[tab] = oldVC
            } else {
                newTabViewControllers[tab] = viewController(for: tab)
            }
        }

        tabViewControllers = newTabViewControllers
        segmentedController.replace(items: makeSegmentedItems(displayTabs: displayTabs), force: force)
        tabViewControllersToRemove.values.forEach { removeChild($0) }

        if view.window != nil {
            activateNftAnimationForSelectedPage()
        }

        updateState()
    }

    private func updateState() {
        updateNavigationAppearance()
        
        let navigator = nftsVCManager.editingNavigator
        let state = navigator.state
        if state.editingState == .selection {
            navigator.installToolbar(into: view)
        }
        
        navigationController?.allowBackSwipeToDismiss(state.editingState == nil)
        navigationController?.isModalInPresentation = state.editingState != nil
    }
            
    private func updateNavigationAppearance() {
        let navigator = nftsVCManager.editingNavigator
        
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        var setCloseButton: Bool = false
        if let editingState = navigator.state.editingState {
            segmentedController.scrollView.isScrollEnabled = false
            switch editingState {
            case .reordering:
                segmentedController.segmentedControl?.isHidden = false
                leadingItemGroups += navigator.cancelEditingBarButtonItem.asSingleItemGroup()
                trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
            case .selection:
                segmentedController.segmentedControl?.isHidden = true
                leadingItemGroups += navigator.selectAllBarButtonItem.asSingleItemGroup()
                trailingItemGroups += navigator.cancelXEditingBarButtonItem.asSingleItemGroup()
            }
        } else {
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.segmentedControl?.isHidden = false
            setCloseButton = true
        }
        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups
        if setCloseButton {
            addCloseNavigationItemIfNeeded()
        }
    }

    private func onSegmentsReorder() {
        nftsVCManager.startReordering()
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }

    private func forEachNftAnimationController(_ body: (NftAnimationPlaybackControlling) -> Void) {
        var processedIds = Set<ObjectIdentifier>()
        for viewController in segmentedController.viewControllers {
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

    private func activateNftAnimationForSelectedPage() {
        let selectedControllerID = segmentedController.selectedIndex
            .flatMap { index -> (NftAnimationPlaybackControlling)? in
                let viewControllers = segmentedController.viewControllers ?? []
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
}

extension AssetsTabVC: WalletAssetsViewModelDelegate {
    public func walletAssetModelDidChangeDisplayTabs(dueToAccountSwitch: Bool) {
        displayTabsChanged(force: false)
    }
}

extension AssetsTabVC: WSegmentedControllerDelegate {
    public func segmentedControllerDidStartDragging() {
        pauseAllNftAnimations()
    }

    public func segmentedControllerDidEndScrolling() {
        activateNftAnimationForSelectedPage()
    }
}
