import UIComponents
import UIKit
import WalletContext

/// Shared native layout for Market and Futures, including the horizontally scrolling cards.
final class MarketSectionContentView: UIView, UICollectionViewDelegate {
    private(set) var section: MarketSectionDisplayData?
    var onSelect: ((MarketItemDisplayData) -> Void)?
    private let header = InsetSectionHeaderCell()
    let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private struct ItemID: Hashable {
        let section: String
        let token: String
        let layout: MarketSectionDisplayData.Layout
    }
    private var source: UICollectionViewDiffableDataSource<Int, ItemID>!
    private var items: [ItemID: Row] = [:]
    private var configurationVersion = 0
    private var contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    private var needsInitialScrollPosition = false
    private var columnCount = 4

    private struct Row { let item: MarketItemDisplayData; let showsSeparator: Bool }
    private static let tileRegistration = UICollectionView.CellRegistration<MarketTileCell, MarketItemDisplayData> { cell, _, item in cell.configure(item) }
    private static let moverRegistration = UICollectionView.CellRegistration<MarketMoverCell, MarketItemDisplayData> { cell, _, item in cell.configure(item) }
    private static let rowRegistration = UICollectionView.CellRegistration<MarketRowCell, Row> { cell, _, row in
        cell.configure(row.item, showsChevron: true, showsSeparator: row.showsSeparator)
    }

    // A section can itself live inside a collection cell. UIKit requires these registrations
    // to exist before entering that outer cell provider, even though the inner list is separate.
    static func prepareForUse() {
        _ = tileRegistration; _ = moverRegistration; _ = rowRegistration
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        Self.prepareForUse()
        addSubview(header)
        addSubview(collection)
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.delaysContentTouches = false
        collection.showsHorizontalScrollIndicator = false
        collection.showsVerticalScrollIndicator = false
        collection.layer.cornerCurve = .continuous
        collection.delegate = self
        source = UICollectionViewDiffableDataSource<Int, ItemID>(collectionView: collection) { [weak self] collection, index, id in
            guard let self, let row = items[id] else { return nil }
            switch id.layout {
            case .grid: return collection.dequeueConfiguredReusableCell(using: Self.tileRegistration, for: index, item: row.item)
            case .rows: return collection.dequeueConfiguredReusableCell(using: Self.rowRegistration, for: index, item: row)
            case .largeHorizontal: return collection.dequeueConfiguredReusableCell(using: Self.moverRegistration, for: index, item: row.item)
            }
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    static func height(for section: MarketSectionDisplayData, columnCount: Int = 4) -> CGFloat {
        guard !section.tokens.isEmpty else { return 0 }
        let content: CGFloat = switch section.layout {
        case .largeHorizontal: 160
        case .rows: CGFloat(section.tokens.count) * 60
        case .grid: 40 + CGFloat((section.tokens.count + columnCount - 1) / columnCount) * 98 + CGFloat((section.tokens.count - 1) / columnCount) * 16
        }
        return content + (section.title.isEmpty ? 0 : 39)
    }

    func configure(_ value: MarketSectionDisplayData, columnCount: Int = 4, insets: NSDirectionalEdgeInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16),
                   onSeeAll: @escaping () -> Void, onSelect: @escaping (MarketItemDisplayData) -> Void) {
        var value = value
        var seen = Set<String>()
        value.tokens = value.tokens.filter { seen.insert($0.id).inserted }
        let replacesSection = section?.id != value.id || section?.layout != value.layout
        let changesLayout = section?.layout != value.layout || self.columnCount != columnCount
        var nextItems: [ItemID: Row] = [:]
        let identifiers = value.tokens.enumerated().map { index, token in
            let id = ItemID(section: value.id, token: token.id, layout: value.layout)
            nextItems[id] = Row(item: token, showsSeparator: index < value.tokens.count - 1)
            return id
        }
        // Layout changes can request cells from the previous snapshot. Keep both sets
        // available, including their cell types, until the latest apply completes.
        items.merge(nextItems, uniquingKeysWith: { _, new in new })
        configurationVersion += 1
        let version = configurationVersion
        self.columnCount = columnCount
        section = value
        contentInsets = insets
        self.onSelect = onSelect
        header.configure(title: value.title, actionTitle: value.showsSeeAll ? lang("See All") : nil, onAction: onSeeAll)
        header.isHidden = value.title.isEmpty || value.tokens.isEmpty
        if changesLayout {
            collection.setCollectionViewLayout(makeLayout(value.layout), animated: false)
        }
        if replacesSection {
            collection.setContentOffset(.zero, animated: false)
        }
        let horizontal = value.layout == .largeHorizontal
        let isAtStart = abs(collection.contentOffset.x + collection.contentInset.left) < 1
        if horizontal && (replacesSection || (isAtStart && collection.contentInset.left != insets.leading)) {
            needsInitialScrollPosition = true
        } else if !horizontal {
            needsInitialScrollPosition = false
        }
        collection.isScrollEnabled = horizontal
        collection.alwaysBounceHorizontal = horizontal
        collection.clipsToBounds = !horizontal
        collection.layer.cornerRadius = horizontal ? 0 : 26
        collection.backgroundColor = horizontal ? .clear : .air.groupedItem
        collection.contentInset = horizontal ? UIEdgeInsets(top: 0, left: insets.leading, bottom: 0, right: insets.trailing) : .zero
        var snapshot = NSDiffableDataSourceSnapshot<Int, ItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers)
        let oldIDs = Set(source.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(identifiers.filter { oldIDs.contains($0) })
        source.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, configurationVersion == version else { return }
            items = nextItems
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func makeLayout(_ layout: MarketSectionDisplayData.Layout) -> UICollectionViewLayout {
        let group: NSCollectionLayoutGroup
        switch layout {
        case .largeHorizontal:
            let size = NSCollectionLayoutSize(widthDimension: .absolute(160), heightDimension: .absolute(160))
            group = .horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        case .grid:
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columnCount)), heightDimension: .absolute(98)))
            group = .horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(98)), repeatingSubitem: item, count: columnCount)
        case .rows:
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(60))
            group = .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        }
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = layout == .rows ? 0 : 16
        if layout == .grid { section.contentInsets = .init(top: 20, leading: 5, bottom: 20, trailing: 5) }
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = layout == .largeHorizontal ? .horizontal : .vertical
        // The parent handles safe areas; inheriting them here makes cards follow its top bar.
        configuration.contentInsetsReference = .none
        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: section.map { Self.height(for: $0, columnCount: columnCount) } ?? 0) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight: CGFloat = header.isHidden ? 0 : 39
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let left = rtl ? contentInsets.trailing : contentInsets.leading
        let width = max(0, bounds.width - contentInsets.leading - contentInsets.trailing)
        header.frame = CGRect(x: left, y: 0, width: width, height: headerHeight)
        let horizontal = section?.layout == .largeHorizontal
        collection.frame = CGRect(x: horizontal ? 0 : left, y: headerHeight,
                                  width: horizontal ? bounds.width : width, height: max(0, bounds.height - headerHeight))
        if needsInitialScrollPosition && collection.bounds.width > 0 {
            collection.layoutIfNeeded()
            collection.contentOffset.x = -collection.contentInset.left
            needsInitialScrollPosition = false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = source.itemIdentifier(for: indexPath), let row = items[id] else { return }
        onSelect?(row.item)
    }
}

final class MarketSectionCell: UICollectionViewCell {
    let market = MarketSectionContentView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addStretchedToBounds(subview: market)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size.height = market.intrinsicContentSize.height
        return result
    }
}
