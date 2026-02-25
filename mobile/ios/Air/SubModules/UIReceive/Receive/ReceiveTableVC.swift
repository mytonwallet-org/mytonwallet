import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

final class ReceiveTableVC: WViewController, WSegmentedControllerContent, UICollectionViewDelegate {

    private enum Section: Hashable {
        case address
        case buyCrypto
    }

    @AccountContext private var account: MAccount
    let chain: ApiChain

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ReceiveItem>!

    public init(account: AccountContext, chain: ApiChain, customTitle: String? = nil) {
        self._account = account
        self.chain = chain
        super.init(nibName: nil, bundle: nil)
        title = customTitle ?? lang("Add Crypto")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        configureDataSource()
        applySnapshot(animated: false)
    }

    public override func updateTheme() {
    }

    private func setupViews() {
        view.backgroundColor = .clear

        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            configuration.headerMode = sectionIndex == 0 ? .supplementary : .none
            configuration.headerTopPadding = sectionIndex == 0 ? 16 : 8
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.top = headerHeight
        collectionView.contentInset.bottom = 16
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.bounces = false
        collectionView.delaysContentTouches = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.insertSubview(collectionView, at: 0)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let address = account.getAddress(chain: chain) ?? ""

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, _ in
            guard let self else { return }
            let title = lang("Your %blockchain% Address", arg1: chain.title)
            var content = UIListContentConfiguration.groupedHeader()
            content.text = title
            cell.contentConfiguration = content
        }

        let addressRegistration = AddressCell.makeRegistration(address: address, chain: chain)
        let buyCryptoRegistration = BuyCryptoItemCell.makeRegistration()

        dataSource = UICollectionViewDiffableDataSource<Section, ReceiveItem>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .address:
                collectionView.dequeueConfiguredReusableCell(using: addressRegistration, for: indexPath, item: ())
            case .buyWithCard, .buyWithCrypto, .depositLink:
                collectionView.dequeueConfiguredReusableCell(using: buyCryptoRegistration, for: indexPath, item: item)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            default:
                nil
            }
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ReceiveItem>()

        snapshot.appendSections([.address])
        snapshot.appendItems([.address], toSection: .address)

        if !ConfigStore.shared.shouldRestrictSwapsAndOnRamp {
            snapshot.appendSections([.buyCrypto])

            var buyCryptoItems: [ReceiveItem] = []
            if chain.isOfframpSupported {
                buyCryptoItems.append(.buyWithCard)
            }
            buyCryptoItems.append(.buyWithCrypto)
            if chain.formatTransferUrl != nil {
                buyCryptoItems.append(.depositLink)
            }
            snapshot.appendItems(buyCryptoItems, toSection: .buyCrypto)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return item != .address
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .address:
            break
        case .buyWithCard:
            AppActions.showBuyWithCard(chain: chain, push: true)
        case .buyWithCrypto:
            AppActions.showSwap(defaultSellingToken: chain.defaultSellingSlug, defaultBuyingToken: chain.defaultBuyingSlug, defaultSellingAmount: nil, push: true)
        case .depositLink:
            topWViewController()?.navigationController?.pushViewController(DepositLinkVC(), animated: true)
        }
    }

    public override func viewWillLayoutSubviews() {
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }

    // MARK: - WSegmentedControllerContent

    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?
    public var scrollingView: UIScrollView? { collectionView }
}

private extension ApiChain {
    var defaultSellingSlug: String {
        switch self {
        case .ton:
            TRON_USDT_SLUG
        case .tron:
            TON_USDT_SLUG
        case .solana:
            TON_USDT_SLUG
        case .other:
            TON_USDT_SLUG
        }
    }
    
    var defaultBuyingSlug: String {
        self.usdtSlug[.mainnet] ?? self.nativeToken.slug
    }
}
