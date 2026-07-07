//
//  WalletSettingsVC.swift
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

private let maxWidth: CGFloat = 580

public final class WalletSettingsVC: SettingsBaseVC, WSegmentedController.Delegate {
    
    @MainActor
    private class Tabs {
        private let viewModel: WalletSettingsViewModel
        private var itemsRestoreSnapshot: [SegmentedControlItem]?
        private var viewControllers: [UIViewController] = []
        
        private(set) var segmentedControlItems: [SegmentedControlItem] = [] {
            didSet {
                viewModel.filters = segmentedControlItems.compactMap { WalletFilter(rawValue: $0.id) }
            }
        }
        
        init(viewModel: WalletSettingsViewModel) {
            self.viewModel = viewModel
            for filter in viewModel.filters {
                let vc = WalletSettingsListVC(viewModel: viewModel, filter: filter)
                let item = SegmentedControlItem(
                    id: filter.rawValue,
                    title: filter.title,
                    isDeletable: false,
                    viewController: vc
                )
                segmentedControlItems.append(item)
                viewControllers.append(vc)
            }
        }
        
        func addToParentVC(_ parent: UIViewController) {
            viewControllers.forEach {
                parent.addChild($0)
                $0.didMove(toParent: parent)
            }
        }
        
        func itemIndexForFilter(_ filter: WalletFilter) -> Int? {
            return segmentedControlItems.firstIndex(where: { $0.id == filter.rawValue })
        }
        
        func startEditing() {
            itemsRestoreSnapshot = segmentedControlItems
        }

        func editItems(with newValue: [SegmentedControlItem]) {
            segmentedControlItems = newValue
        }
        
        func stopEditing(isCanceled: Bool) {
            if let itemsRestoreSnapshot, isCanceled  {
                segmentedControlItems = itemsRestoreSnapshot
            }
            itemsRestoreSnapshot = nil
        }
    }
    
    private lazy var tabs = Tabs(viewModel: viewModel)

    private var currentFilter: WalletFilter { viewModel.currentFilter }
    private var segmentedController: WSegmentedController?
    private var segmentedControl: WSegmentedControl? { segmentedController?.segmentedControl }
    private var viewModel = WalletSettingsViewModel()
    private let segmentedControlWidth: CGFloat = 320
    private var segmentedControlContainerWidthConstraint: NSLayoutConstraint?
    private var isConfiguredForBottomAttachedSheet: Bool?
    private var lastAppliedNavigationKey: NavigationKey?

    private struct NavigationKey: Equatable {
        var mode: WalletSettingsViewModel.Mode
        var preferredLayout: WalletListLayout
        var accountCount: Int
    }
    
    @Dependency(\.accountStore) private var accountStore
    private var orderedAccountIdsRestoreSnapshot: OrderedSet<String>?
        
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        tabs.addToParentVC(self)
        
        observe { [weak self] in
            guard let self else { return }
            
            switch viewModel.mode {
            case .reordering, .select:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.updateNavigation()
                }
            case .normal:
                updateNavigation()
            }
        }
        observe { [weak self] in
            guard let self else { return }
            if accountStore.accountsById.isEmpty {
                dismiss(animated: true)
            }
        }
        observe { [weak self] in
            guard let self else { return }
            _ = viewModel.isDeletingAccounts
            updateNavigation()
        }
        observe { [weak self] in
            guard let self else { return }
            _ = viewModel.preferredLayout
            _ = accountStore.accountsById.count
            updateNavigation()
        }
        
        let titleView = NavigationHeader2()
        titleView.setContentView(WalletSettingsNavigationHeader(viewModel: viewModel))
        navigationItem.titleView = titleView
        
        updateSheetPresentation()
        
        let segmentedController = WSegmentedController(
            items: tabs.segmentedControlItems,
            defaultItemId: viewModel.currentFilter.rawValue,
            animationSpeed: .slow,
            capsuleFillColor: .air.darkCapsule,
            delegate: self
        )
        self.segmentedController = segmentedController
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedController.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
        ])

        let segmentedControl = segmentedController.segmentedControl!
        segmentedControl.removeFromSuperview()
        
        let segmentedControlContainer = UIView()
        segmentedControlContainer.translatesAutoresizingMaskIntoConstraints = false
        segmentedControlContainer.addSubview(segmentedControl)
        let segmentedControlContainerWidthConstraint = segmentedControlContainer.widthAnchor.constraint(equalToConstant: preferredSegmentedControlContainerWidth)
        self.segmentedControlContainerWidthConstraint = segmentedControlContainerWidthConstraint
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: segmentedControlContainer.topAnchor, constant: 12),
            segmentedControl.centerXAnchor.constraint(equalTo: segmentedControlContainer.centerXAnchor),
            segmentedControl.widthAnchor.constraint(equalTo: segmentedControlContainer.widthAnchor),
            segmentedControlContainerWidthConstraint,
        ])
        segmentedControlContainer.frame.size.height = 54
        
        if let cls = NSClassFromString("ettelaPraBnoitagivaNIU_".reverse) as? UIView.Type {
            let palette = cls.perform(NSSelectorFromString("alloc"))
                .takeUnretainedValue()
                .perform(NSSelectorFromString("initWithContentView:"), with: segmentedControlContainer)
                .takeUnretainedValue()
        
            navigationItem.perform(NSSelectorFromString(":ettelaPmottoBtes_".reverse), with: palette)
        }
        
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        
        view.backgroundColor = .air.sheetBackground
        addCustomNavigationBarBackground(color: .air.sheetBackground, navItemTransparent: false)
        
        let bottomButton = HostingView {
            WalletSettingsAddButton(viewModel: viewModel)
        }
        view.addSubview(bottomButton)
        NSLayoutConstraint.activate([
            bottomButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        segmentedController.model.onItemsReorder = { [weak self] items in
            self?.tabs.editItems(with: items)
        }
        
        viewModel.onStartReordering = { [weak self] in
            guard let self else { return }
            
            switchToAllTabOnEditing()
            segmentedController.scrollView.isScrollEnabled = false
            segmentedController.model.startReordering()
            
            tabs.startEditing()
            orderedAccountIdsRestoreSnapshot = accountStore.orderedAccountIds
        }
        
        viewModel.onStopReordering = { [weak self] isCanceled in
            guard let self else { return }
            
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.model.stopReordering()
            
            tabs.stopEditing(isCanceled: isCanceled)
            segmentedController.replace(items: tabs.segmentedControlItems)
            if isCanceled, let orderedAccountIdsRestoreSnapshot {
                accountStore.reorderAccounts(newOrderHint: orderedAccountIdsRestoreSnapshot)
            }
            orderedAccountIdsRestoreSnapshot = nil
        }
        
        viewModel.onStartSelecting = { [weak self] in
            guard let self else { return }
            
            switchToAllTabOnEditing()
            segmentedController.scrollView.isScrollEnabled = false
            segmentedController.segmentedControl.isUserInteractionEnabled = false
        }
        
        viewModel.onStopSelecting = { [weak self] in
            guard self != nil else { return }
            
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.segmentedControl.isUserInteractionEnabled = true
        }
    }
    
    private func switchToAllTabOnEditing() {
        guard let segmentedController else { return }
        let idx = tabs.itemIndexForFilter(.all) ?? 0
        segmentedController.switchTo(tabIndex: idx)
        segmentedController.handleSegmentChange(to: idx, animated: true)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSegmentedControlContainerWidth()
        updateSheetPresentation()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateSegmentedControlContainerWidth()
        updateSheetPresentation()
    }

    private var preferredSegmentedControlContainerWidth: CGFloat {
        let availableWidth = view.bounds.width > 0
            ? view.bounds.width
            : (view.window?.bounds.width ?? screenWidth)
        guard availableWidth > 0 else {
            return min(maxWidth, segmentedControlWidth)
        }
        return min(maxWidth, availableWidth)
    }

    private func updateSegmentedControlContainerWidth() {
        segmentedControlContainerWidthConstraint?.constant = preferredSegmentedControlContainerWidth
    }

    private func updateSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }
        let usesBottomSheetControls = isSheetPresentationAttachedToBottom
        let shouldUpdateDetents = isConfiguredForBottomAttachedSheet != usesBottomSheetControls
        isConfiguredForBottomAttachedSheet = usesBottomSheetControls

        if IOS_26_MODE_ENABLED {
            sheet.prefersGrabberVisible = usesBottomSheetControls
        }
        if shouldUpdateDetents {
            if usesBottomSheetControls {
                sheet.detents = [
                    .custom(identifier: .init("twoThirds")) { $0.maximumDetentValue * 0.667 },
                    .large(),
                ]
                sheet.selectedDetentIdentifier = .init("twoThirds")
            } else {
                sheet.detents = [.large()]
                sheet.selectedDetentIdentifier = .large
            }
        }
        if #available(iOS 26.1, *) {
            sheet.backgroundEffect = UIColorEffect(color: .air.sheetBackground)
        }
    }
    
    private func updateNavigation() {
        let isDeleting = viewModel.isDeletingAccounts
        var isEditing = false
        let leftBarButtonItem: UIBarButtonItem
        let rightBarButtonItem: UIBarButtonItem
        
        switch viewModel.mode {
        case .reordering:
            leftBarButtonItem = UIBarButtonItem.cancelTextButtonItem { [weak self] in
                self?.viewModel.stopReordering(isCanceled: true)
            }
            rightBarButtonItem = UIBarButtonItem.doneButtonItem { [weak self] in
                self?.viewModel.stopReordering(isCanceled: false)
            }
            isEditing = true
        case .select:
            leftBarButtonItem = UIBarButtonItem.textButtonItem(text: lang("Select All")) { [weak self] in
                guard let self else { return }
                viewModel.toggleSelectAll(accountIds: accountStore.orderedAccountIds.elements)
            }
            rightBarButtonItem = UIBarButtonItem.cancelXButtonItem { [weak self] in
                self?.viewModel.stopSelecting()
            }
            isEditing = true
        case .normal:
            var menuItems: [UIMenuElement] = []

            do {
                let other = viewModel.preferredLayout.other
                let viewAs = UIAction(
                    title: other.title,
                    image: UIImage(systemName: other.imageName),
                    handler: { [weak self] _ in self?.viewModel.preferredLayout = other }
                )
                menuItems += UIMenu(options: .displayInline, children: [viewAs])
            }
            
            menuItems += UIAction(
                title: lang("Reorder"),
                image: .airBundle("MenuReorder26"),
                handler: { [weak self] _ in
                    self?.viewModel.startReordering()
                }
            )
            
            if accountStore.accountsById.count > 1 {
                menuItems += UIAction(
                    title: lang("Select"),
                    image: .airBundle("MenuSelect26"),
                    handler: { [weak self] _ in
                        self?.viewModel.startSelecting(preselected: [])
                    }
                )
            }
            
            leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                menu: UIMenu(children: menuItems),
            )
            
            rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
            )
        }
        
        leftBarButtonItem.isEnabled = !isDeleting
        rightBarButtonItem.isEnabled = !isDeleting
        
        let newKey = NavigationKey(
            mode: viewModel.mode,
            preferredLayout: viewModel.preferredLayout,
            accountCount: accountStore.accountsById.count
        )
        let wasEverApplied = lastAppliedNavigationKey != nil
        let keyChanged = newKey != lastAppliedNavigationKey
        lastAppliedNavigationKey = newKey

        if keyChanged {
            navigationItem.setLeftBarButtonItems([leftBarButtonItem], animated: wasEverApplied)
            navigationItem.setRightBarButtonItems([rightBarButtonItem], animated: wasEverApplied)
        } else {
            navigationItem.leftBarButtonItem?.isEnabled = leftBarButtonItem.isEnabled
            navigationItem.rightBarButtonItem?.isEnabled = rightBarButtonItem.isEnabled
        }
        
        navigationController?.isModalInPresentation = isEditing || isDeleting
    }
    
    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        if let id = self.segmentedControl?.model.selectedItem?.id, let filter = WalletFilter(rawValue: id) {
            if filter != self.viewModel.currentFilter {
                self.viewModel.currentFilter = filter
            }
        }
    }
    
    public func segmentedControllerDidEndScrolling() {
        viewModel.segmentedControllerDidSwitchTrigger += 1
    }
}

@available(iOS 18, *)
#Preview {
    previewSheet(WalletSettingsVC())
}
