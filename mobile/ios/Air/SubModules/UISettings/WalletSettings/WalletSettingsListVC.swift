//
//  Wallet.swift
//  MyTonWalletAir
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
import OrderedCollections

final class WalletSettingsListVC: SettingsBaseVC, WSegmentedControllerContent, UICollectionViewDelegate, UICollectionViewDropDelegate, UICollectionViewDragDelegate {
    
    var viewModel: WalletSettingsViewModel
    var filter: WalletFilter
    
    @Dependency(\.accountStore) private var accountStore
    @Dependency(\.accountStore.accountsById) private var accountsById
    @Dependency(\.accountStore.orderedAccountIds) private var orderedAccountIds
    
    private(set) var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    
    enum Section: Hashable {
        case grid
        case list
        case empty
    }
    enum Item: Hashable {
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
            collectionView?.isEditing = viewModel.isReordering
        }
    }
    
    var onScroll: ((CGFloat) -> Void)?
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?
    var scrollingView: UIScrollView? { collectionView }
    
    func setupViews() {
        
        view.backgroundColor = WTheme.sheetBackground
        
        let layout = makeLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView = collectionView
        
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = WTheme.sheetBackground
        collectionView.alwaysBounceVertical = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 114, left: 0, bottom: 80, right: 0)
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.delaysContentTouches = false
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        
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
        
        dataSource = makeDataSource(collectionView: collectionView)
        
    }
    
    func makeDataSource(collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Section, Item> {
        let gridCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, walletId in
            let accountContext = AccountContext(accountId: walletId)
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletSettingsGridCell(accountContext: accountContext)
                }
                .margins(.all, 0)
            }
        }
        let listCellRegistration = AccountListCell.makeRegistration()
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
        dataSource.reorderingHandlers.canReorderItem = { [weak self] item in
            guard let self else { return false }
            if viewModel.isReordering, case .list = item {
                return true
            }
            return false
        }
        dataSource.reorderingHandlers.willReorder = { _ in
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self else { return }
            let diff = transaction.difference.toString()
            accountStore.reorderAccounts(changes: diff)
        }
        return dataSource
    }
    
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let gridMaximumCardWidth: CGFloat = 150
        let gridSpacing: CGFloat = 8
        let gridSectionInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = .clear
        listConfiguration.headerTopPadding = 8

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
                return NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: env)
            case .empty:
                return emptySection
            case nil:
                return nil
            }
        }
    }

    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var accountIds = self.orderedAccountIds
        if let accountType = filter.accountType {
            accountIds = accountIds.filter { accountsById[$0]?.type == accountType }
        }
        if accountIds.isEmpty {
            snapshot.appendSections([.empty])
            snapshot.appendItems([.empty])
        } else {
            switch viewModel.effectiveLayout {
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
    
    func applySnapshot(animated: Bool) {
        let snapshot = makeSnapshot()
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let accountId = dataSource?.itemIdentifier(for: indexPath)?.accountId {
            if accountId != accountStore.currentAccountId {
                Task {
                    _ = try await accountStore.activateAccount(accountId: accountId)
                    topViewController()?.dismiss(animated: true)
                    AppActions.showHome(popToRoot: true)
                }
            } else {
                topViewController()?.dismiss(animated: true)
            }
        }
    }
    
    // MARK: Context menu
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        if let indexPath = indexPaths.first, let accountId = dataSource?.itemIdentifier(for: indexPath)?.accountId, !viewModel.isReordering {
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
                let reorder = UIAction(
                    title: lang("Reorder"),
                    image: UIImage(systemName: "chevron.up.chevron.down"),
                    handler: { [weak self] _ in
                        self?.viewModel.startEditing()
                    }
                )
                let rename = UIAction(
                    title: lang("Rename"),
                    image: UIImage(systemName: "pencil.line"),
                    handler: { _ in
                        AppActions.showRenameAccount(accountId: accountId)
                    }
                )
                let customize = UIAction(
                    title: lang("Customize"),
                    image: UIImage(systemName: "wand.and.stars.inverse"),
                    handler: { _ in
                        AppActions.showCustomizeWallet(accountId: accountId)
                    }
                )
                let section = UIMenu(options: .displayInline, children: [reorder, rename, customize])
                let delete = UIAction(
                    title: lang("Remove"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                    handler: { _ in
                        AppActions.showDeleteAccount(accountId: accountId)
                    }
                )
                let menu = UIMenu(children: [section, delete])
                return menu
            }
        }
        return nil
    }
    
    // MARK: Drag and drop
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard filter == .all, viewModel.isReordering else { return [] }
        return makeDragItems(collectionView: collectionView, indexPath: indexPath)
    }
    
    private func makeDragItems(collectionView: UICollectionView, indexPath: IndexPath) -> [UIDragItem] {
        guard let dataSource, case .list = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        return  [dragItem]
    }
    
    public func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let dataSource, let cell = collectionView.cellForItem(at: indexPath), case .list = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 26)
        return parameters
    }
    
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if let dataSource, let destinationIndexPath, case .list = dataSource.itemIdentifier(for: destinationIndexPath) {
            return .init(operation: .move, intent: .insertAtDestinationIndexPath)
        } else {
            return .init(operation: .cancel)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
        // required for drop delegate
    }
}

private extension CollectionDifference<WalletSettingsListVC.Item> {
    func toString() -> CollectionDifference<String> {
        var changes: [CollectionDifference<String>.Change] = []
        for rowChange in self {
            switch rowChange {
            case .remove(offset: let offset, element: let element, associatedWith: let associatedWith):
                if let accountId = element.accountId {
                    changes.append(.remove(offset: offset, element: accountId, associatedWith: associatedWith))
                }
            case .insert(offset: let offset, element: let element, associatedWith: let associatedWith):
                if let accountId = element.accountId {
                    changes.append(.insert(offset: offset, element: accountId, associatedWith: associatedWith))
                }
            }
        }
        return CollectionDifference<String>(changes)!
    }
}

@available(iOS 26, *)
#Preview {
    WalletSettingsListVC(viewModel: WalletSettingsViewModel(), filter: .all)
}
