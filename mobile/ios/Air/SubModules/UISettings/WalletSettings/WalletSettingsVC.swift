//
//  WalletSettingsVC.swift
//  UISettings
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
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    @Dependency(\.accountStore) private var accountStore
    private var orderedAccountIdsRestoreSnapshot: OrderedSet<String>?
    
    public override func viewDidLoad() {
        
        super.viewDidLoad()
        
        view.backgroundColor = .air.sheetBackground
        
        tabs.addToParentVC(self)
        
        observe { [weak self] in
            self?.updateEditingState()
        }
        navigationItem.titleView = HostingView {
            WalletSettingsNavigationHeader(viewModel: viewModel)
        }
        if let sheet = sheetPresentationController {
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = !isPad
            }
            if isPad {
                sheet.detents = [.large()]
                sheet.selectedDetentIdentifier = .large
            } else {
                sheet.detents = [
                    .custom(identifier: .init("twoThirds")) { $0.maximumDetentValue * 0.667 },
                    .large(),
                ]
                sheet.selectedDetentIdentifier = .init("twoThirds")
            }
            if #available(iOS 26.1, *) {
                sheet.backgroundEffect = UIColorEffect(color: .air.sheetBackground)
            }
        }
        
        let segmentedController = WSegmentedController(
            items: tabs.segmentedControlItems,
            defaultItemId: viewModel.currentFilter.rawValue,
            barHeight: 44,
            animationSpeed: .slow,
            capsuleFillColor: .airBundle("DarkCapsuleColor"),
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
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: segmentedControlContainer.topAnchor, constant: 12),
            segmentedControl.centerXAnchor.constraint(equalTo: segmentedControlContainer.centerXAnchor),
            segmentedControl.widthAnchor.constraint(equalTo: segmentedControlContainer.widthAnchor),
            segmentedControlContainer.widthAnchor.constraint(equalToConstant: min(maxWidth, screenWidth)),
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
        
        addCustomNavigationBarBackground()
        
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
        
        viewModel.onStartEditing = { [weak self] in
            guard let self else { return }
            
            let idx = tabs.itemIndexForFilter(.all) ?? 0
            segmentedController.switchTo(tabIndex: idx)
            segmentedController.handleSegmentChange(to: idx, animated: true)
            segmentedController.scrollView.isScrollEnabled = false
            segmentedController.model.startReordering()
            
            tabs.startEditing()
            orderedAccountIdsRestoreSnapshot = accountStore.orderedAccountIds
        }
        
        viewModel.onStopEditing = { [weak self] isCanceled in
            guard let self else { return }
            
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.model.stopReordering()
            
            tabs.stopEditing(isCanceled: isCanceled)
            segmentedController.replace(items: tabs.segmentedControlItems)
            if isCanceled, let orderedAccountIdsRestoreSnapshot {
                accountStore.reorderAccounts(newOrder: orderedAccountIdsRestoreSnapshot)
            }
            orderedAccountIdsRestoreSnapshot = nil
        }
    }
    
    private func updateNavigation() {
        let isEditing = viewModel.isReordering
        
        if isEditing {
            navigationItem.leftBarButtonItem = UIBarButtonItem.cancelTextButtonItem { [weak self] in
                self?.viewModel.stopEditing(isCanceled: true)
            }
            navigationItem.rightBarButtonItem = UIBarButtonItem.doneButtonItem { [weak self] in
                self?.viewModel.stopEditing(isCanceled: false)
            }
            
        } else {
            let other = viewModel.preferredLayout.other
            let viewAs = UIAction(
                title: other.title,
                image: UIImage(systemName: other.imageName),
                handler: { [weak self] _ in self?.viewModel.preferredLayout = other }
            )
            let viewAsMenu = UIMenu(options: .displayInline, children: [viewAs])
            let reorder = UIAction(
                title: lang("Reorder"),
                image: .airBundle("MenuReorder26"),
                handler: { [weak self] _ in
                    self?.viewModel.startEditing()
                }
            )
            let menu = UIMenu(children: [viewAsMenu, reorder])
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                menu: menu,
            )
            
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
            )
        }
        
        navigationController?.isModalInPresentation = isEditing
    }
    
    private func updateEditingState() {
        if viewModel.isReordering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateNavigation()
            }
        } else {
            updateNavigation()
        }
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

@available(iOS 26, *)
#Preview {
    previewSheet(WalletSettingsVC())
}
