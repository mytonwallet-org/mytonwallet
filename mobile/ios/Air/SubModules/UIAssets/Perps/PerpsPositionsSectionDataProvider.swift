import UIActivityList
import UIComponents
import UIKit
import WalletContext

/// Native rows shared by Wallet Home, Futures and the full positions list.
@MainActor
public final class PerpsPositionsSectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    public let id: String
    public var data: PerpsPositionsDisplayData?
    public var onAction: ((PerpsHomeAction) -> Void)?
    public var sectionAccountId: String? { data?.accountID }
    private let showsHeader: Bool
    private let previewLimit: Int?
    private let topSpacing: CGFloat
    private var showAllID: String { id + ":all:" + (data?.accountID ?? "") }
    private var statusID: String { id + ":status:" + (data?.accountID ?? "") }
    private func rowID(_ positionID: String) -> String { id + ":position:" + (data?.accountID ?? "") + ":" + positionID }
    private var visiblePositions: [PerpsPositionRowDisplayData] {
        guard let data, data.status == .ready else { return [] }
        var seen = Set<String>()
        return Array(data.positions.filter { seen.insert($0.id).inserted }.prefix(previewLimit ?? Int.max))
    }
    public var itemIdentifiers: [String] {
        guard let data else { return [] }
        guard data.status == .ready else { return [statusID] }
        let rows = visiblePositions.map { rowID($0.id) }
        if rows.isEmpty { return previewLimit == nil ? [statusID] : [] }
        return rows + (previewLimit == nil ? [] : [showAllID])
    }

    public init(id: String, showsHeader: Bool = true, previewLimit: Int? = 5, topSpacing: CGFloat = 16) {
        self.id = id
        self.showsHeader = showsHeader
        self.previewLimit = previewLimit
        self.topSpacing = topSpacing
    }

    private lazy var positionRegistration = UICollectionView.CellRegistration<PerpsPositionCell, PerpsPositionRowDisplayData> { cell, _, position in
        cell.configure(position)
        cell.configurationUpdateHandler = { cell, state in cell.isHighlighted = state.isHighlighted }
    }
    private lazy var showAllRegistration = UICollectionView.CellRegistration<WalletSeeAllCell, String> { [weak self] cell, _, _ in
        guard let self else { return }
        cell.baseBackgroundColor = .air.groupedItem
        cell.configurePositions(positionsCount: max(data?.totalCount ?? 0, data?.positions.count ?? 0))
        cell.configurationUpdateHandler = { cell, state in cell.isHighlighted = state.isHighlighted }
    }
    private lazy var statusRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, _ in
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = .air.secondaryLabel
        content.textProperties.alignment = .center
        cell.accessories = []
        switch self?.data?.status {
        case .loading:
            content.text = nil
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessories = [.customView(configuration: .init(customView: spinner, placement: .leading()))]
        case .unavailable(let message):
            content.text = message
            content.secondaryText = lang("Retry")
            content.secondaryTextProperties.color = .tintColor
        default: content.text = lang("$perps_no_positions")
        }
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .air.groupedItem
        cell.backgroundConfiguration = background
    }
    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<InsetSectionHeaderCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, _ in
        view.configure(title: lang("Open Positions"), topSpacing: self?.topSpacing ?? 0)
    }

    public func prepareForUse() {
        _ = positionRegistration; _ = showAllRegistration; _ = statusRegistration; _ = headerRegistration
    }

    public func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = showsHeader ? .supplementary : .none
        configuration.headerTopPadding = 0
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED { configuration.separatorConfiguration.color = .air.separator }
        configuration.itemSeparatorHandler = { [weak self] indexPath, separator in
            guard let self else { return separator }
            return separatorConfiguration(at: indexPath.item, default: separator)
        }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        section.contentInsets.top = showsHeader ? 0 : topSpacing
        section.contentInsets.bottom = 0
        return section
    }

    func separatorConfiguration(at index: Int, default configuration: UIListSeparatorConfiguration) -> UIListSeparatorConfiguration {
        var configuration = configuration
        let items = itemIdentifiers
        guard items.indices.contains(index) else { return configuration }
        if items[index] == showAllID {
            configuration.topSeparatorVisibility = .hidden
            configuration.bottomSeparatorVisibility = .hidden
        } else if items.indices.contains(index + 1), items[index + 1] == showAllID {
            configuration.bottomSeparatorVisibility = .hidden
        }
        return configuration
    }

    public func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        if let position = visiblePositions.first(where: { rowID($0.id) == itemIdentifier }) {
            return collectionView.dequeueConfiguredReusableCell(using: positionRegistration, for: indexPath, item: position)
        }
        if itemIdentifier == showAllID {
            return collectionView.dequeueConfiguredReusableCell(using: showAllRegistration, for: indexPath, item: itemIdentifier)
        }
        return collectionView.dequeueConfiguredReusableCell(using: statusRegistration, for: indexPath, item: itemIdentifier)
    }

    public func dequeueSupplementaryView(_ collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
    }

    public func shouldSelect(itemIdentifier: String) -> Bool {
        if itemIdentifier == statusID, case .unavailable = data?.status { return true }
        guard data?.status == .ready else { return false }
        return itemIdentifier == showAllID || visiblePositions.contains { rowID($0.id) == itemIdentifier && $0.canSelect }
    }

    public func didSelect(itemIdentifier: String) {
        guard shouldSelect(itemIdentifier: itemIdentifier) else { return }
        if itemIdentifier == showAllID { onAction?(.allPositions) }
        else if itemIdentifier == statusID { onAction?(.refresh) }
        else if let position = visiblePositions.first(where: { rowID($0.id) == itemIdentifier }) { onAction?(.position(position.id)) }
    }
}
