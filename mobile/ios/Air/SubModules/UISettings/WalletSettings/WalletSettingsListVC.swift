//
//  WalletSettingsListVC.swift
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception

final class WalletSettingsListVC: SettingsBaseVC, WSegmentedControllerContent, ReorderableCollectionViewControllerDelegate {
    
    var viewModel: WalletSettingsViewModel
    var filter: WalletFilter
    
    @Dependency(\.accountStore) private var accountStore
    @Dependency(\.accountStore.accountsById) private var accountsById
    @Dependency(\.accountStore.orderedAccountIds) private var orderedAccountIds
    
    private var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    private var reorderController: ReorderableCollectionViewController!
    private var contextMenuExtraBlurView: UIView?
    private var previousMode: WalletSettingsViewModel.Mode = .normal
    
    private enum Section: Hashable {
        case grid
        case list
        case empty
    }
    
    private enum Item: Hashable {
        case grid(String)
        case list(String)
        case empty
        
        var accountId: String? {
            switch self {
            case .grid(let accountId), .list(let accountId):
                accountId
            case .empty:
                nil
            }
        }
    }
    
    private var layoutStyle: WalletListLayout = .grid
    
    init(viewModel: WalletSettingsViewModel, filter: WalletFilter) {
        self.viewModel = viewModel
        self.filter = filter
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        observe { [weak self] in
            self?.applySnapshot(animated: true)
        }
        observe { [weak self] in
            guard let self else { return }
            // Keep the selection in sync when accounts are removed (e.g. after deletion),
            // so the delete button's count/enabled state reflects reality.
            let stillExisting = viewModel.selectedAccountIds.intersection(accountsById.keys)
            if stillExisting != viewModel.selectedAccountIds {
                viewModel.selectedAccountIds = stillExisting
            }
            if viewModel.mode == .select {
                updateVisibleSelection()
            }
        }
        observe { [weak self] in
            guard let self, viewModel.mode == .select else { return }
            _ = viewModel.selectedAccountIds
            updateVisibleSelection()
        }
        observe { [weak self] in
            guard let self else { return }
            collectionView?.isUserInteractionEnabled = !viewModel.isDeletingAccounts
        }
        observe { [weak self] in
            guard let self else { return }
            
            let mode = viewModel.mode
            guard mode != previousMode else { return }
            
            reorderController.isReordering = mode == .reordering
            collectionView?.dragInteractionEnabled = mode == .normal
            
            if mode == .select || previousMode == .select {
                collectionView?.collectionViewLayout.invalidateLayout()
                updateVisibleSelection()
            }
            
            previousMode = mode
        }
    }
    
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { collectionView }
    func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    
    private func setupViews() {
        
        view.backgroundColor = .air.sheetBackground
        
        let layout = makeLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView = collectionView
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.sheetBackground
        collectionView.alwaysBounceVertical = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 122, left: 0, bottom: 80, right: 0)
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delaysContentTouches = false
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            collectionView.topEdgeEffect.isHidden = true
        }
        
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        reorderController = ReorderableCollectionViewController(collectionView: collectionView)
        reorderController.scrollDirection = .vertical
        reorderController.delegate = self

        dataSource = makeDataSource(collectionView: collectionView)
    }
    
    private func makeDataSource(collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Section, Item> {
        let gridCellRegistration = UICollectionView.CellRegistration<WalletSettingsGridCell, String> { [weak self] cell, indexPath, accountId in
            guard let self else { return }
            let isSelecting = viewModel.mode == .select
            cell.configure(
                with: AccountContext(accountId: accountId),
                isSelected: isSelecting ? viewModel.selectedAccountIds.contains(accountId) : nil
            )
            reorderController.updateCell(cell, indexPath: indexPath)
        }
        let listCellRegistration = UICollectionView.CellRegistration<WalletSettingsListCell, String> { [weak self] cell, indexPath, accountId in
            guard let self else { return }
            let isSelecting = viewModel.mode == .select
            cell.configure(
                with: AccountContext(accountId: accountId),
                isSelected: isSelecting ? viewModel.selectedAccountIds.contains(accountId) : nil
            )
            reorderController.updateCell(cell, indexPath: indexPath)
        }
        let emptyCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [filter, viewModel] cell, _, _ in
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletSettingsEmptyCell(filter: filter, viewModel: viewModel)
                }
                .background(.clear)
                .margins(.horizontal, 32)
                .margins(.vertical, 20)
            }
        }
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, identifier in
            switch identifier {
            case .grid(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: gridCellRegistration, for: indexPath, item: accountId)
            case .list(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: accountId)
            case .empty:
                return collectionView.dequeueConfiguredReusableCell(using: emptyCellRegistration, for: indexPath, item: ())
            }
        }
        
        return dataSource
    }

    private func toggleSelection(_ accountId: String) {
        guard !viewModel.isDeletingAccounts else { return }
        viewModel.selectedAccountIds.formSymmetricDifference([accountId])
        let item: Item = viewModel.preferredLayout == .grid ? .grid(accountId) : .list(accountId)
        guard let indexPath = dataSource?.indexPath(for: item) else { return }
        updateCellSelection(at: indexPath, accountId: accountId)
    }

    private func updateCellSelection(at indexPath: IndexPath, accountId: String) {
        guard let collectionView else { return }
        let isSelecting = viewModel.mode == .select
        let selection: Bool? = isSelecting ? viewModel.selectedAccountIds.contains(accountId) : nil
        if let cell = collectionView.cellForItem(at: indexPath) as? WalletSettingsListCell {
            cell.setSelection(selection)
        } else if let cell = collectionView.cellForItem(at: indexPath) as? WalletSettingsGridCell {
            cell.setSelection(selection)
        }
    }

    private func updateVisibleSelection() {
        guard let collectionView, let dataSource else { return }
        let isSelecting = viewModel.mode == .select
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let accountId = dataSource.itemIdentifier(for: indexPath)?.accountId else { continue }
            let selection: Bool? = isSelecting ? viewModel.selectedAccountIds.contains(accountId) : nil
            if let cell = collectionView.cellForItem(at: indexPath) as? WalletSettingsListCell {
                cell.setSelection(selection)
            } else if let cell = collectionView.cellForItem(at: indexPath) as? WalletSettingsGridCell {
                cell.setSelection(selection)
            }
        }
    }
    
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let gridMaximumCardWidth: CGFloat = 150
        let gridSpacing: CGFloat = 6
        let gridSectionInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = .clear
        listConfiguration.headerTopPadding = 14
        listConfiguration.itemSeparatorHandler = { [weak self] _, config in
            var config = config
            let isSelecting = self?.viewModel.mode == .select
            let leading = WalletSettingsListCell.Layout.textLeading + (isSelecting ? WalletSettingsListCell.Layout.markerSpace : 0)
            let trailing = WalletSettingsListCell.Layout.textTrailing
            config.topSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
            config.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
            return config
        }
        
        let emptyItem = NSCollectionLayoutItem(
            layoutSize: .init(.fractionalWidth(1), .fractionalHeight(1))
        )
        let emptyGroup = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(.fractionalWidth(1), .fractionalHeight(0.7)),
            subitems: [emptyItem]
        )
        let emptySection = NSCollectionLayoutSection(group: emptyGroup)
        
        return UICollectionViewCompositionalLayout { [weak self] idx, env in
            switch self?.dataSource?.sectionIdentifier(for: idx) {
            case .grid:
                let containerWidth = env.container.effectiveContentSize.width
                let usableWidth = max(0, containerWidth - gridSectionInsets.leading - gridSectionInsets.trailing)
                let columnCount = max(3, Int(ceil((usableWidth + gridSpacing) / (gridMaximumCardWidth + gridSpacing))))
                
                let gridItem = NSCollectionLayoutItem(
                    layoutSize: .init(.fractionalWidth(1.0 / CGFloat(columnCount)), .estimated(110))
                )
                let gridGroup = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(.fractionalWidth(1), .estimated(110)),
                    subitems: [gridItem]
                )
                gridGroup.interItemSpacing = .fixed(gridSpacing)
                
                let gridSection = NSCollectionLayoutSection(group: gridGroup)
                gridSection.contentInsets = gridSectionInsets
                gridSection.interGroupSpacing = 4
                return gridSection
            case .list:
                let listSection = NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: env)
                if !IOS_26_MODE_ENABLED {
                    listSection.contentInsets.top = 8
                }
                return listSection
            case .empty:
                return emptySection
            case nil:
                return nil
            }
        }
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var accountIds = self.orderedAccountIds
        if let accountType = filter.accountType {
            accountIds = accountIds.filter { accountsById[$0]?.type == accountType }
        }
        
        if accountIds.isEmpty {
            snapshot.appendSections([.empty])
            snapshot.appendItems([.empty])
        } else {
            switch viewModel.preferredLayout {
            case .grid:
                snapshot.appendSections([.grid])
                snapshot.appendItems(accountIds.map(Item.grid))
            case .list:
                snapshot.appendSections([.list])
                snapshot.appendItems(accountIds.map(Item.list))
            }
        }
        return snapshot
    }
    
    private func applySnapshot(animated: Bool) {
        let snapshot = makeSnapshot()
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }
    
    // MARK: Context menu
    
    private func makeMenu(accountId: String, canReorderOrSelect: Bool) -> UIMenu {
        var mainSectionItems: [UIMenuElement] = []
        
        if canReorderOrSelect {
            mainSectionItems += UIAction(
                title: lang("Reorder"),
                image: .airBundle("MenuReorder26"),
                handler: { [weak self] _ in
                    self?.viewModel.startReordering()
                }
            )
            
            mainSectionItems += UIAction(
                title: lang("Select"),
                image: .airBundle("MenuSelect26"),
                handler: { [weak self] _ in
                    self?.viewModel.startSelecting(preselected: [accountId])
                }
            )
        }
                
        mainSectionItems += UIAction(
            title: lang("Rename"),
            image: UIImage(systemName: "pencil.line"),
            handler: { _ in
                AppActions.showRenameAccount(accountId: accountId)
            }
        )
        
        mainSectionItems += UIAction(
            title: lang("Customize"),
            image: UIImage(systemName: "wand.and.stars.inverse"),
            handler: { _ in
                AppActions.showCustomizeWallet(accountId: accountId)
            }
        )
        let mainSection = UIMenu(options: .displayInline, children: mainSectionItems)
        
        let delete = UIAction(
            title: lang("Remove"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
            handler: { [weak self] _ in
                self?.viewModel.deleteAccounts([accountId])
            }
        )
        return UIMenu(children: [mainSection, delete])
    }
        
    private func isReorderablePath(_ indexPath: IndexPath) -> Bool {
        guard let dataSource, [.grid, .list].contains(dataSource.sectionIdentifier(for: indexPath.section)) else {
            return false
        }
        return true
    }
    
    // MARK: - ReorderableCollectionViewControllerDelegate
    
    func reorderController(_ controller: ReorderableCollectionViewController, canStartSystemDragForItemAt indexPath: IndexPath) -> Bool {
        return viewModel.mode == .normal && isReorderablePath(indexPath) && filter == .all
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, canMoveItemAt indexPath: IndexPath) -> Bool {
        return viewModel.mode == .reordering && isReorderablePath(indexPath)
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) -> Bool {
        guard isReorderablePath(sourceIndexPath), isReorderablePath(destinationIndexPath),
              sourceIndexPath.section == destinationIndexPath.section else {
            return false
        }
        
        var reordered = orderedAccountIds
        let moved = reordered.remove(at: sourceIndexPath.item)
        reordered.insert(moved, at: destinationIndexPath.item)
     
        accountStore.reorderAccounts(newOrderHint: reordered)
        
        // This is called in observe as well but to avoid SwiftUI glitching it is necessary to call it at this point
        applySnapshot(animated: true)

        return true
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, didChangeReorderingStateByExternalActor externalActor: Bool) {
        guard viewModel.mode != .select else { return }
        if !externalActor {
            viewModel.startReordering()
        }
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, didSelectItemAt indexPath: IndexPath) {
        guard !viewModel.isDeletingAccounts else { return }
        guard let accountId = dataSource?.itemIdentifier(for: indexPath)?.accountId else { return }
        
        switch viewModel.mode {
        case .select:
            toggleSelection(accountId)
        case .normal:
            if accountId != accountStore.currentAccountId {
                Task {
                    _ = try await accountStore.activateAccount(accountId: accountId)
                    topViewController()?.dismiss(animated: true)
                    AppActions.showHome(popToRoot: true)
                }
            } else {
                topViewController()?.dismiss(animated: true)
            }
        case .reordering:
            break
        }
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, contextMenuConfigurationForItemAt indexPath: IndexPath,
                           point: CGPoint) -> UIContextMenuConfiguration? {
        guard let accountId = dataSource?.itemIdentifier(for: indexPath)?.accountId, viewModel.mode == .normal else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
            return self.makeMenu(accountId: accountId, canReorderOrSelect: self.orderedAccountIds.count > 1)
        }
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        contextMenuExtraBlurView?.removeFromSuperview()
        contextMenuExtraBlurView = ContextMenuBackdropBlur.show(in: view.window, animator: animator)

        if let indexPath = configuration.identifier as? IndexPath,
           let cell = collectionView?.cellForItem(at: indexPath) as? WalletSettingsListCell {
            cell.setPreviewChrome(true)
        }
    }

    public func reorderController(_ controller: ReorderableCollectionViewController, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                                  animator: (any UIContextMenuInteractionAnimating)?) {
        let blurView = contextMenuExtraBlurView
        contextMenuExtraBlurView = nil
        ContextMenuBackdropBlur.hide(blurView, animator: animator)

        if let indexPath = configuration.identifier as? IndexPath,
           let cell = collectionView?.cellForItem(at: indexPath) as? WalletSettingsListCell {
            let clear = { cell.setPreviewChrome(false) }
            if let animator {
                animator.addCompletion(clear)
            } else {
                clear()
            }
        }
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, adjustPreviewFrame previewFrame: CGRect) -> CGRect {
        let cv = controller.collectionView
        var visibleBounds = cv.bounds.inset(by: cv.adjustedContentInset)
        if viewModel.preferredLayout == .list {
            visibleBounds = visibleBounds.inset(by: UIEdgeInsets(top: 0, left: cv.layoutMargins.left, bottom: 0, right: cv.layoutMargins.right))
        }
        return previewFrame.clamped(to: visibleBounds)
    }
    
    public func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview? {
        guard let cell = cell as? WalletSettingsListCell else { return nil }
        return .init(view: cell.contentView, cornerRadius: WalletSettingsListCell.Layout.previewCornerRadius, copyView: false)
    }
}

@available(iOS 18, *)
#Preview {
    WalletSettingsListVC(viewModel: WalletSettingsViewModel(), filter: .all)
}
