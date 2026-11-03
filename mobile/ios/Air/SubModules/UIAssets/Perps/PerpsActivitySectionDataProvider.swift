import UIActivityList
import UIComponents
import UIKit
import WalletContext

@MainActor
final class PerpsActivitySectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    let id = "activity"
    var accountID = ""
    var activities: [PerpsHomeActivity] = []
    var onSelect: ((String) -> Void)?
    private var uniqueActivities: [PerpsHomeActivity] {
        var seen = Set<String>()
        return activities.filter { seen.insert($0.id).inserted }
    }
    private func rowID(_ activity: PerpsHomeActivity) -> String { accountID + ":" + activity.id }
    var itemIdentifiers: [String] { uniqueActivities.map(rowID) }
    private lazy var registration = UICollectionView.CellRegistration<PerpsActivityCell, PerpsHomeActivity> { cell, _, activity in
        cell.configure(activity)
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
        guard let activity = uniqueActivities.first(where: { rowID($0) == itemIdentifier }) else { return UICollectionViewCell() }
        return collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: activity)
    }
    func dequeueSupplementaryView(_ collection: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        return collection.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
    }
    func shouldSelect(itemIdentifier: String) -> Bool {
        uniqueActivities.contains { rowID($0) == itemIdentifier && $0.canSelect }
    }
    func didSelect(itemIdentifier: String) {
        guard let activity = uniqueActivities.first(where: { rowID($0) == itemIdentifier && $0.canSelect }) else { return }
        onSelect?(activity.id)
    }
}
