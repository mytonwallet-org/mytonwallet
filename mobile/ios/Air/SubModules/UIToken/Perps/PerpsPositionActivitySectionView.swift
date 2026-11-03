import UIComponents
import UIKit
import WalletContext

final class PerpsPositionActivityCell: ActivitySummaryCell {
    override init(frame: CGRect) { super.init(frame: frame, iconSize: 44, maximumAmountWidthRatio: 0.5) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ activity: PerpsPositionDisplayData.Activity, isStale: Bool = false) {
        let image: UIImage
        let colors: [UIColor]
        switch activity.kind {
        case .opened, .increased:
            image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))!
            colors = UIColor.air.blueGradient
        case .reduced, .closed:
            image = UIImage(systemName: "arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))!
            colors = UIColor.air.blueGradient
        case .liquidated:
            image = .airBundle("PerpsActivityLiquidated")
            colors = UIColor.air.redGradient
        }
        let color: UIColor = switch activity.amount.tone {
        case .positive: .air.positiveAmount
        case .negative: .air.negativeAmount
        case .neutral: .label
        }
        configure(title: activity.title, date: activity.date,
                  amount: NSAttributedString(string: activity.amount.text, attributes: [.foregroundColor: color]),
                  detail: activity.detail, image: image, gradientColors: colors,
                  accessibilityIdentifier: "perps.position.activity." + activity.id, canSelect: activity.canSelect, isStale: isStale)
    }
}

/// A non-scrolling history card; the asset page owns scrolling and bar insets.
final class PerpsPositionActivitySectionView: UIView, UICollectionViewDelegate {
    let collectionView: UICollectionView
    private let header = InsetSectionHeaderCell()
    private var activities: [String: PerpsPositionDisplayData.Activity] = [:]
    private var isStale = false
    private var collectionHeight: NSLayoutConstraint!
    private var collectionTopToHeader: NSLayoutConstraint!
    private var collectionTopToSelf: NSLayoutConstraint!
    private let onSelect: (String) -> Void
    private lazy var registration = UICollectionView.CellRegistration<PerpsPositionActivityCell, PerpsPositionDisplayData.Activity> {
        [weak self] cell, _, activity in cell.configure(activity, isStale: self?.isStale == true)
    }
    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] collection, index, id in
        guard let self, let activity = activities[id] else { return nil }
        return collection.dequeueConfiguredReusableCell(using: registration, for: index, item: activity)
    }

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 66
            configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
            if !IOS_26_MODE_ENABLED { configuration.separatorConfiguration.color = .air.separator }
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.contentInsets = .zero
            return section
        })
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        addSubview(header)
        addSubview(collectionView)
        collectionHeight = collectionView.heightAnchor.constraint(equalToConstant: 0)
        collectionTopToHeader = collectionView.topAnchor.constraint(equalTo: header.bottomAnchor)
        collectionTopToSelf = collectionView.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionTopToHeader,
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionHeight,
        ])
        _ = registration
        _ = dataSource
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(activities: [PerpsPositionDisplayData.Activity], title: String = lang("Activity"), isStale: Bool = false) {
        self.isStale = isStale
        header.configure(title: title)
        var ids: [String] = []
        self.activities.removeAll(keepingCapacity: true)
        for activity in activities where self.activities[activity.id] == nil {
            self.activities[activity.id] = activity
            ids.append(activity.id)
        }
        let oldIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(ids.filter { oldIDs.contains($0) })
        header.isHidden = ids.isEmpty
        NSLayoutConstraint.deactivate([collectionTopToHeader, collectionTopToSelf])
        collectionTopToHeader.isActive = !ids.isEmpty
        collectionTopToSelf.isActive = ids.isEmpty
        collectionHeight.constant = CGFloat(ids.count) * ActivitySummaryCell.rowHeight
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return activities[id]?.canSelect == true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let id = dataSource.itemIdentifier(for: indexPath), activities[id]?.canSelect == true else { return }
        onSelect(id)
    }
}
