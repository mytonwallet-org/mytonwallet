import UIKit
import UIComponents
import WalletContext

struct InAppBrowserTabInfo {
    let id: UUID
    let title: String
    let subtitle: String
    let previewImage: UIImage?
    let isSelected: Bool
}

@MainActor
protocol InAppBrowserTabSwitcherDelegate: AnyObject {
    func inAppBrowserTabSwitcher(_ tabSwitcher: InAppBrowserTabSwitcherVC, didSelectTab id: UUID)
    func inAppBrowserTabSwitcher(_ tabSwitcher: InAppBrowserTabSwitcherVC, didCloseTab id: UUID)
}

final class InAppBrowserTabSwitcherVC: WViewController, UICollectionViewDelegate {
    private enum Section {
        case tabs
    }

    weak var delegate: InAppBrowserTabSwitcherDelegate?

    private var tabsByID: [UUID: InAppBrowserTabInfo] = [:]
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupDataSource()
    }

    func apply(tabs: [InAppBrowserTabInfo], animated: Bool) {
        tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        guard isViewLoaded else { return }
        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        let tabIDs = tabs.map(\.id)
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.tabs])
        snapshot.appendItems(tabIDs, toSection: .tabs)
        snapshot.reconfigureItems(tabIDs.filter { previousIDs.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<InAppBrowserTabCell, UUID> { [weak self] cell, _, id in
            guard let self, let tab = tabsByID[id] else { return }
            cell.configure(with: tab)
            cell.onClose = { [weak self] in
                guard let self else { return }
                delegate?.inAppBrowserTabSwitcher(self, didCloseTab: id)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let horizontalInset: CGFloat = 16
            let interItemSpacing: CGFloat = 14
            let availableWidth = environment.container.effectiveContentSize.width - horizontalInset * 2 - interItemSpacing
            let itemWidth = max(1, (availableWidth / 2).rounded(.down))
            let itemHeight = min(max(itemWidth * 1.35, 190), 360)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(itemHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 2)
            group.interItemSpacing = .fixed(interItemSpacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 18
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 20,
                leading: horizontalInset,
                bottom: 24,
                trailing: horizontalInset
            )
            return section
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        delegate?.inAppBrowserTabSwitcher(self, didSelectTab: id)
    }
}

private final class InAppBrowserTabCell: UICollectionViewCell {
    var onClose: (() -> Void)?

    private let cardView = UIView()
    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderImageView = UIImageView(image: UIImage(systemName: "globe"))
    private let footerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onClose = nil
        previewImageView.image = nil
    }

    func configure(with tab: InAppBrowserTabInfo) {
        titleLabel.text = tab.title
        subtitleLabel.text = tab.subtitle
        previewImageView.image = tab.previewImage
        previewImageView.isHidden = tab.previewImage == nil
        placeholderImageView.isHidden = tab.previewImage != nil
        cardView.layer.borderWidth = tab.isSelected ? 2 : 0
        cardView.layer.borderColor = tab.isSelected ? UIColor.tintColor.cgColor : UIColor.clear.cgColor
    }

    private func setupViews() {
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .air.groupedItem
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous
        cardView.layer.masksToBounds = true
        contentView.addSubview(cardView)

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.backgroundColor = .air.background
        previewContainer.clipsToBounds = true
        cardView.addSubview(previewContainer)

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFill
        previewContainer.addSubview(previewImageView)

        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.tintColor = .air.secondaryLabel
        placeholderImageView.contentMode = .scaleAspectFit
        previewContainer.addSubview(placeholderImageView)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.backgroundColor = .air.groupedItem
        cardView.addSubview(footerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        footerView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        footerView.addSubview(subtitleLabel)

        var closeConfiguration = UIButton.Configuration.filled()
        closeConfiguration.baseBackgroundColor = .air.groupedItem.withAlphaComponent(0.88)
        closeConfiguration.baseForegroundColor = .label
        closeConfiguration.cornerStyle = .capsule
        closeConfiguration.image = UIImage(systemName: "xmark")
        closeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        closeButton.configuration = closeConfiguration
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        closeButton.accessibilityLabel = lang("Close")
        cardView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewContainer.topAnchor.constraint(equalTo: cardView.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 34),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 34),

            footerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 58),

            titleLabel.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 9),
            titleLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -3),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: footerView.bottomAnchor, constant: -9),

            closeButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @objc private func closePressed() {
        onClose?()
    }
}
