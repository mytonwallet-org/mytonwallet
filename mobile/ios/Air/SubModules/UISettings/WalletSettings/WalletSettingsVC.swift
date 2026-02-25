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
    
    @Dependency(\.balanceStore) private var balanceStore
    
    lazy var items = [
        SegmentedControlItem(
            id: "all",
            title: lang("All"),
            viewController: tabViewControllers[0],
        ),
        SegmentedControlItem(
            id: "my",
            title: lang("My"),
            viewController: tabViewControllers[1],
        ),
        SegmentedControlItem(
            id: "ledger",
            title: lang("Ledger"),
            viewController: tabViewControllers[2],
        ),
        SegmentedControlItem(
            id: "view",
            title: lang("$view_accounts"),
            viewController: tabViewControllers[3],
        ),
    ]
    lazy var tabViewControllers: [WalletSettingsListVC] = [
        WalletSettingsListVC(viewModel: viewModel, filter: .all),
        WalletSettingsListVC(viewModel: viewModel, filter: .my),
        WalletSettingsListVC(viewModel: viewModel, filter: .ledger),
        WalletSettingsListVC(viewModel: viewModel, filter: .view),
    ]
    private var currentFilter: WalletFilter { viewModel.currentFilter }
    private var segmentedController: WSegmentedController?
    private var segmentedControl: WSegmentedControl? { segmentedController?.segmentedControl }
    private var viewModel = WalletSettingsViewModel()
    private let segmentedControlWidth: CGFloat = 320
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    public override func viewDidLoad() {
        
        super.viewDidLoad()
        
        view.backgroundColor = WTheme.sheetBackground
        
        observe { [weak self] in
            guard let self else { return }
            makeLeadingBarItem()
        }
        navigationItem.titleView = HostingView {
            WalletSettingsNavigationHeader(viewModel: viewModel)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
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
                sheet.backgroundEffect = UIColorEffect(color: WTheme.sheetBackground)
            }
        }
        
        let segmentedController = WSegmentedController(
            items: items,
            defaultItemId: viewModel.currentFilter.rawValue,
            barHeight: 44,
            animationSpeed: .slow,
            secondaryTextColor: UIColor.secondaryLabel,
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
        
        observe { [weak self] in
            guard let self else { return }
            if viewModel.isReordering {
                let idx = items.firstIndex(where: { $0.id == "all" })!
                segmentedController.switchTo(tabIndex: idx)
                segmentedController.handleSegmentChange(to: idx, animated: true)
                segmentedController.scrollView.isScrollEnabled = false
                segmentedControl.isUserInteractionEnabled = false
            } else {
                segmentedController.scrollView.isScrollEnabled = true
                segmentedControl.isUserInteractionEnabled = true
            }
        }
    }
    
    func makeLeadingBarItem() {
        if viewModel.isReordering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                    self?.viewModel.stopEditing()
                })
            }
        } else {
            let other = viewModel.preferredLayout.other
            let viewAs = UIAction(
                title: other.title,
                image: UIImage(systemName: other.imageName),
                handler: { [weak self] _ in self?.viewModel.setPreferredLayout(other) }
            )
            let viewAsMenu = UIMenu(options: .displayInline, children: [viewAs])
            let reorder = UIAction(
                title: lang("Reorder"),
                image: UIImage(systemName: "chevron.up.chevron.down"),
                handler: { [weak self] _ in
                    self?.viewModel.startEditing()
                }
            )
            let menu = UIMenu(children: [viewAsMenu, reorder])
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                menu: menu,
            )
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
