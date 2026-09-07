import ContextMenuKit
import UIActivityList
import UIAssets
import UIComponents
import UIKit
import WalletContext
import WalletCore

@MainActor
final class HomeActivitySectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    private enum ItemIdentifier {
        static let activityPrefix = "activity:"
        static let placeholderPrefix = "placeholder:"
        static let empty = "empty"
        static let showAll = "show-all"

        static func activity(_ id: String) -> String {
            activityPrefix + id
        }

        static func placeholder(_ index: Int) -> String {
            placeholderPrefix + String(index)
        }

        static func activityID(from itemIdentifier: String) -> String? {
            guard itemIdentifier.hasPrefix(activityPrefix) else { return nil }
            return String(itemIdentifier.dropFirst(activityPrefix.count))
        }
    }

    let id: String
    weak var activityDelegate: ActivityCell.Delegate?
    var contextMenuProvider: ((ApiActivity) -> ContextMenuInteraction?)?
    var onShowAll: ((String?) -> Void)?

    private weak var activityViewModel: ActivityPreviewViewModel?

    private lazy var activityRegistration = UICollectionView.CellRegistration<ActivityCell, String> { [weak self] cell, _, itemIdentifier in
        guard let self,
              let activityID = ItemIdentifier.activityID(from: itemIdentifier),
              let activityViewModel,
              let activity = activityViewModel.activity(for: activityID),
              let activityDelegate else {
            cell.configureSkeleton()
            cell.setContextMenuInteraction(nil)
            return
        }
        cell.configure(
            with: activity,
            accountContext: activityViewModel.accountContext,
            delegate: activityDelegate,
            timestampDisplayMode: .dateWhenOlderThanTwelveHours
        )
        cell.setContextMenuInteraction(contextMenuProvider?(activity))
    }

    private lazy var placeholderRegistration = UICollectionView.CellRegistration<ActivityCell, String> { cell, _, _ in
        cell.configureSkeleton()
        cell.setContextMenuInteraction(nil)
    }

    private lazy var emptyRegistration = UICollectionView.CellRegistration<EmptyWalletCell, String> { cell, _, _ in
        cell.backgroundColor = .clear
        cell.set(animated: true, layout: .compact)
    }

    private lazy var showAllRegistration = UICollectionView.CellRegistration<WalletSeeAllCell, String> { [weak self] cell, _, _ in
        cell.baseBackgroundColor = .air.groupedItem
        cell.configureActivities(menu: self?.makeVisibleItemsLimitMenu())
        cell.configurationUpdateHandler = { showAllCell, state in
            showAllCell.isHighlighted = state.isHighlighted
        }
    }

    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<ActivityDateCell>(
        elementKind: UICollectionView.elementKindSectionHeader
    ) { cell, _, _ in
        cell.configure(title: lang("$home_activity"))
    }

    init(id: String = "activity") {
        self.id = id
    }

    var itemIdentifiers: [String] {
        let limit = activityViewModel?.requestedCount
            ?? AppStorageHelper.homeActivityVisibleItemsLimit.rawValue
        guard let activityViewModel, let activityIDs = activityViewModel.activityIDs else {
            return (0..<limit).map(ItemIdentifier.placeholder) + [ItemIdentifier.showAll]
        }

        let visibleActivityIDs = Array(activityIDs.prefix(limit))
        let missingCount = switch activityViewModel.loadState {
        case .loading, .failed:
            max(0, limit - visibleActivityIDs.count)
        case .satisfied, .exhausted:
            0
        }
        if visibleActivityIDs.isEmpty, missingCount == 0 {
            return [ItemIdentifier.empty]
        }

        var items = visibleActivityIDs.map(ItemIdentifier.activity)
        items.append(contentsOf: (0..<missingCount).map(ItemIdentifier.placeholder))
        items.append(ItemIdentifier.showAll)
        return items
    }

    func update(viewModel: ActivityPreviewViewModel?) {
        activityViewModel = viewModel
    }

    func prepareForUse() {
        _ = activityRegistration
        _ = placeholderRegistration
        _ = emptyRegistration
        _ = showAllRegistration
        _ = headerRegistration
    }

    func makeLayoutSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = itemIdentifiers == [ItemIdentifier.empty] ? .none : .supplementary
        configuration.headerTopPadding = 0
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED {
            configuration.separatorConfiguration.color = .air.separator
        }
        configuration.itemSeparatorHandler = { [weak self] indexPath, separatorConfiguration in
            guard let self else { return separatorConfiguration }
            var separatorConfiguration = separatorConfiguration
            let items = itemIdentifiers
            let item = items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
            let nextItem = items.indices.contains(indexPath.item + 1) ? items[indexPath.item + 1] : nil
            if item == ItemIdentifier.showAll {
                separatorConfiguration.topSeparatorVisibility = .hidden
                separatorConfiguration.bottomSeparatorVisibility = .hidden
            } else if nextItem == ItemIdentifier.showAll {
                separatorConfiguration.bottomSeparatorVisibility = .hidden
            }
            return separatorConfiguration
        }
        return NSCollectionLayoutSection.list(
            using: configuration,
            layoutEnvironment: layoutEnvironment
        )
    }

    func dequeueCell(
        _ collectionView: UICollectionView,
        _ indexPath: IndexPath,
        itemIdentifier: String
    ) -> UICollectionViewCell {
        if ItemIdentifier.activityID(from: itemIdentifier) != nil {
            return collectionView.dequeueConfiguredReusableCell(
                using: activityRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        if itemIdentifier.hasPrefix(ItemIdentifier.placeholderPrefix) {
            return collectionView.dequeueConfiguredReusableCell(
                using: placeholderRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        switch itemIdentifier {
        case ItemIdentifier.empty:
            return collectionView.dequeueConfiguredReusableCell(
                using: emptyRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        case ItemIdentifier.showAll:
            return collectionView.dequeueConfiguredReusableCell(
                using: showAllRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        default:
            assertionFailure("Unknown Home activity item identifier: \(itemIdentifier)")
            return collectionView.dequeueConfiguredReusableCell(
                using: emptyRegistration,
                for: indexPath,
                item: ItemIdentifier.empty
            )
        }
    }

    func dequeueSupplementaryView(
        _ collectionView: UICollectionView,
        kind: String,
        indexPath: IndexPath
    ) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        return collectionView.dequeueConfiguredReusableSupplementary(
            using: headerRegistration,
            for: indexPath
        )
    }

    func shouldSelect(itemIdentifier: String) -> Bool {
        itemIdentifier == ItemIdentifier.showAll
    }

    func didSelect(itemIdentifier: String) {
        guard itemIdentifier == ItemIdentifier.showAll else { return }
        onShowAll?(lastDisplayedActivityID)
    }

    private var lastDisplayedActivityID: String? {
        itemIdentifiers.reversed().compactMap(ItemIdentifier.activityID(from:)).first
    }

    private func makeVisibleItemsLimitMenu() -> UIMenu {
        UIMenu(options: [.displayInline, .singleSelection], children: [
            UIDeferredMenuElement.uncached { completion in
                let currentLimit = AppStorageHelper.homeActivityVisibleItemsLimit
                completion(HomeActivityVisibleItemsLimit.allCases.map { limit in
                    UIAction(title: limit.title, state: currentLimit == limit ? .on : .off) { _ in
                        AppStorageHelper.homeActivityVisibleItemsLimit = limit
                    }
                })
            }
        ])
    }
}
