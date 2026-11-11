import UIActivityList
import UIComponents
import UIKit
import WalletContext

public enum HomeExploreDestination: String, CaseIterable { case market, futures, agent, apps }

/// Wallet Home shortcuts to the Market, Futures, Agent and Apps sections
@MainActor
public final class HomeExploreSectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    public let id: String
    /// Row identifiers must be unique in the diffable snapshot, so repeated destinations are dropped.
    public var destinations: [HomeExploreDestination] = [] {
        didSet {
            var seen = Set<HomeExploreDestination>()
            let unique = destinations.filter { seen.insert($0).inserted }
            if unique != destinations { destinations = unique }
        }
    }
    public var onSelect: ((HomeExploreDestination) -> Void)?
    public var itemIdentifiers: [String] { destinations.map(\.rawValue) }
    private lazy var registration = UICollectionView.CellRegistration<HomeExploreCell, HomeExploreDestination> { cell, _, destination in
        cell.configure(destination)
    }
    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<InsetSectionHeaderCell>(elementKind: UICollectionView.elementKindSectionHeader) { view, _, _ in
        view.configure(title: lang("Explore"), topSpacing: 16)
    }

    public init(id: String) {
        self.id = id
    }

    public func prepareForUse() { _ = registration; _ = headerRegistration }

    public func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
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

    public func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath,
                                                     item: HomeExploreDestination(rawValue: itemIdentifier) ?? .market)
    }

    public func dequeueSupplementaryView(_ collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
    }

    public func shouldSelect(itemIdentifier: String) -> Bool {
        destinations.contains { $0.rawValue == itemIdentifier }
    }

    public func didSelect(itemIdentifier: String) {
        guard let destination = destinations.first(where: { $0.rawValue == itemIdentifier }) else { return }
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
        subtitleLabel.numberOfLines = 2
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
            icon.config(activityImage: .airBundle("ExploreAgent"),
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
        let textSize = CGSize(width: max(0, attributes.size.width - 78), height: .greatestFiniteMagnitude)
        let titleHeight = max(22, titleLabel.sizeThatFits(textSize).height)
        let subtitleHeight = max(18, subtitleLabel.sizeThatFits(textSize).height)
        result.size.height = ceil(titleHeight + subtitleHeight + 20)
        return result
    }
}
