import UIActivityList
import UIComponents
import UIKit
import WalletContext

@MainActor
final class PerpsActivitySectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    let id = "activity"
    var activities: [PerpsTradeActivity] = []
    var isStale = false
    var onSelect: ((String) -> Void)?
    var itemIdentifiers: [String] { activities.map(\.id) }
    private lazy var registration = UICollectionView.CellRegistration<PerpsTradeActivityCell, PerpsTradeActivity> { [weak self] cell, _, activity in
        cell.configure(activity, isStale: self?.isStale == true, accessibilityPrefix: "perps.home.activity.")
        cell.configurationUpdateHandler = { cell, state in cell.isHighlighted = state.isHighlighted }
    }
    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<InsetSectionHeaderCell>(elementKind: UICollectionView.elementKindSectionHeader) { view, _, _ in
        view.configure(title: lang("Activity"), topSpacing: 24)
    }

    func prepareForUse() { _ = registration; _ = headerRegistration }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
        configuration.headerTopPadding = 0
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED { configuration.separatorConfiguration.color = .air.separator }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        section.contentInsets.top = 0
        section.contentInsets.bottom = 0
        return section
    }
    func dequeueCell(_ collection: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        guard let activity = activities.first(where: { $0.id == itemIdentifier }) else { return UICollectionViewCell() }
        return collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: activity)
    }
    func dequeueSupplementaryView(_ collection: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        return collection.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
    }
    func shouldSelect(itemIdentifier: String) -> Bool {
        activities.contains { $0.id == itemIdentifier }
    }
    func didSelect(itemIdentifier: String) {
        guard shouldSelect(itemIdentifier: itemIdentifier) else { return }
        onSelect?(itemIdentifier)
    }
}
