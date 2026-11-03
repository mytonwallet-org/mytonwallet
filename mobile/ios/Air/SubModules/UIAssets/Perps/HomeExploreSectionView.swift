import SwiftUI
import UIComponents
import UIKit
import WalletContext

/// The SwiftUI boundary only hosts the native section used in Home and the UI lab.
public struct HomeExploreSectionView: UIViewRepresentable {
    private let destinations: [HomeExploreDestination]
    private let onSelect: (HomeExploreDestination) -> Void

    public init(destinations: [HomeExploreDestination] = HomeExploreDestination.allCases,
                onSelect: @escaping (HomeExploreDestination) -> Void) {
        self.destinations = destinations
        self.onSelect = onSelect
    }

    public func makeUIView(context: Context) -> UIView { HomeExploreSectionContentView() }

    public func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? HomeExploreSectionContentView)?.configure(destinations: destinations, onSelect: onSelect)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: uiView.intrinsicContentSize.height)
    }
}

final class HomeExploreSectionContentView: UIView, UICollectionViewDelegate {
    let collectionView: UICollectionView
    private let header = InsetSectionHeaderCell()
    private var destinations: [HomeExploreDestination] = []
    private var collectionHeight: NSLayoutConstraint!
    private var collectionTopToHeader: NSLayoutConstraint!
    private var collectionTopToSelf: NSLayoutConstraint!
    private var onSelect: ((HomeExploreDestination) -> Void)?
    private lazy var registration = UICollectionView.CellRegistration<HomeExploreCell, HomeExploreDestination> {
        cell, _, destination in cell.configure(destination)
    }
    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, HomeExploreDestination>(collectionView: collectionView) { [weak self] collection, index, destination in
        guard let self else { return nil }
        return collection.dequeueConfiguredReusableCell(using: registration, for: index, item: destination)
    }

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
            configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
            if !IOS_26_MODE_ENABLED { configuration.separatorConfiguration.color = .air.separator }
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.contentInsets = .zero
            return section
        })
        super.init(frame: frame)
        header.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isScrollEnabled = false
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
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

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: destinations.isEmpty ? 0 : InsetSectionHeader.height + CGFloat(destinations.count) * 60)
    }

    func configure(destinations: [HomeExploreDestination], onSelect: @escaping (HomeExploreDestination) -> Void) {
        var seen = Set<HomeExploreDestination>()
        self.destinations = destinations.filter { seen.insert($0).inserted }
        self.onSelect = onSelect
        header.configure(title: lang("Explore"))
        header.isHidden = self.destinations.isEmpty
        NSLayoutConstraint.deactivate([collectionTopToHeader, collectionTopToSelf])
        collectionTopToHeader.isActive = !self.destinations.isEmpty
        collectionTopToSelf.isActive = self.destinations.isEmpty
        let oldIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, HomeExploreDestination>()
        snapshot.appendSections([0])
        snapshot.appendItems(self.destinations)
        snapshot.reconfigureItems(self.destinations.filter { oldIDs.contains($0) })
        collectionHeight.constant = CGFloat(self.destinations.count) * 60
        dataSource.apply(snapshot, animatingDifferences: false)
        invalidateIntrinsicContentSize()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let destination = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelect?(destination)
    }
}

final class HomeExploreCell: WHighlightCollectionViewCell {
    let icon = IconView(size: 30)
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        baseBackgroundColor = .air.groupedItem
        highlightBackgroundColor = .air.highlight
        contentView.backgroundColor = .clear
        titleLabel.textColor = .label
        subtitleLabel.textColor = .air.secondaryLabel
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)
        contentView.addSubview(labels)
        icon.layer.cornerRadius = 8
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            subtitleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged)))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ destination: HomeExploreDestination) {
        titleLabel.applyTextStyle(.callout)
        titleLabel.text = switch destination { case .market: lang("Market"); case .agent: lang("Agent"); case .futures: lang("Futures"); case .apps: lang("Apps") }
        subtitleLabel.applyTextStyle(.supporting)
        subtitleLabel.text = lang(destination == .agent ? "PerpsExploreAgentDescription" : "$perps_explore_" + destination.rawValue)
        switch destination {
        case .apps:
            icon.config(with: .init(image: .airBundle("ExploreApps"), shape: .square))
        case .agent:
            icon.config(activityImage: UIImage.airBundle("tab_agent").resized(to: CGSize(width: 22, height: 22)).withRenderingMode(.alwaysTemplate),
                        gradientColors: [UIColor(hex: "65BCFF"), UIColor(hex: "9D53C8")], shape: .square)
        case .market, .futures:
            icon.config(activityImage: .airBundle(destination == .market ? "ExploreMarket" : "ExploreFutures"),
                        gradientColors: destination == .market
                            ? [UIColor(hex: "EEB627"), UIColor(hex: "E438B3")]
                            : [UIColor(hex: "C6E720"), UIColor(hex: "10B189")], shape: .square)
        }
        accessibilityIdentifier = "home.explore." + destination.rawValue
        isAccessibilityElement = true
        accessibilityLabel = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .button
    }

    @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
        isHighlighted = gesture.state == .began || gesture.state == .changed
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size.height = 60
        return result
    }
}
