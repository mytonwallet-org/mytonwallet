import SwiftUI
import UIComponents
import UIKit
import WalletContext

final class MarketTokenListVC: WViewController, UICollectionViewDelegate {
    private enum Section {
        case main
    }

    private let screenTitle: String
    private let tokens: [MarketToken]
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MarketToken>!

    init(title: String, tokens: [MarketToken]) {
        self.screenTitle = title
        self.tokens = tokens
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
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

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, MarketToken> {
            cell, _, token in
            cell.contentConfiguration = UIHostingConfiguration {
                MarketTokenRow(token: token, showsChevron: false)
            }
            .margins(.all, 0)
            .background {
                Color.air.background
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, token in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: token
            )
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MarketToken>()
        snapshot.appendSections([.main])
        snapshot.appendItems(tokens)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }
}
