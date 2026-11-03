import UIComponents
import UIKit
import WalletContext
import WalletCore

public final class MarketTokenListVC: WViewController, UICollectionViewDelegate {
    public var onVisibilityChanged: ((Bool) -> Void)?
    private enum Section {
        case main
    }

    private let screenTitle: String
    private var tokens: [MarketItemDisplayData]
    private let onSelect: (MarketItemDisplayData) -> Void
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>!

    convenience init(title: String, tokens: [MarketToken]) {
        self.init(title: title, tokens: tokens.map(\.presentation)) { AppActions.showTokenBySlug($0.token.slug) }
    }

    public init(title: String, tokens: [MarketItemDisplayData], onSelect: @escaping (MarketItemDisplayData) -> Void) {
        self.screenTitle = title
        var ids = Set<String>()
        self.tokens = tokens.filter { ids.insert($0.id).inserted }
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        view.backgroundColor = .air.background
        addCustomNavigationBarBackground(color: .air.background)

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .air.background
        configuration.showsSeparators = true
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.background
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delaysContentTouches = false
        view.addStretchedToBounds(subview: collectionView)

        let registration = UICollectionView.CellRegistration<MarketRowCell, MarketItemDisplayData> {
            cell, _, token in
            cell.configure(token, showsChevron: false)
            cell.baseBackgroundColor = .air.background
            cell.highlightBackgroundColor = .air.highlight
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self]
            collectionView, indexPath, id in
            guard let token = self?.tokens.first(where: { $0.id == id }) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: token
            )
        }

        update(tokens: tokens)
    }

    public func update(tokens: [MarketItemDisplayData]) {
        var ids = Set<String>()
        self.tokens = tokens.filter { ids.insert($0.id).inserted }
        guard isViewLoaded, let dataSource else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(self.tokens.map(\.id))
        let currentIDs = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { currentIDs.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    public override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onVisibilityChanged?(true) }
    public override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); onVisibilityChanged?(false) }

    public override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let token = tokens.first(where: { $0.id == id }) else { return }
        onSelect(token)
    }
}
