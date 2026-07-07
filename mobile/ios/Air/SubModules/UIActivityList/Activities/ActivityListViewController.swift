import ContextMenuKit
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("ActivityListViewController")

private let appearAnimationDuration = 0.4
private let plainSectionEstimatedHeight: CGFloat = 300
private let nftActivityContextMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

open class ActivityListViewController: WViewController, ActivityCell.Delegate, UICollectionViewDelegate {

    public typealias Section = ActivityListViewModel.Section
    public typealias Row = ActivityListViewModel.Row

    public struct CustomSectionDescriptor {
        public let id: String
        public let dequeueCell: @MainActor (UICollectionView, IndexPath) -> UICollectionViewCell

        public init(
            id: String,
            dequeueCell: @escaping @MainActor (UICollectionView, IndexPath) -> UICollectionViewCell
        ) {
            self.id = id
            self.dequeueCell = dequeueCell
        }
    }

    public lazy var collectionView = ActivitiesCollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?

    public let skeletonView = SkeletonView()
    public var wasShowingSkeletons: Bool = false
    public private(set) var skeletonState: SkeletonState?
    open var isInitializingCache = true

    open var headerPlaceholderHeight: CGFloat { fatalError("abstract") }
    open var customSections: [CustomSectionDescriptor] { [] }
    open var activeCustomSectionIDs: [String] { customSections.map(\.id) }
    public var customSectionIDs: [String] { activeCustomSectionIDs }

    public var activityViewModel: ActivityListViewModel?

    private var reconfigureTokensWhenStopped: Bool = false
    private let nftAnimationPlaybackCoordinator = NftAnimationPlaybackCoordinator()
    private var isViewVisibleForNftAnimationPlayback = false
    private var nftAnimationPlaybackEligibleIDs = Set<String>()


    private let queue = DispatchQueue(label: "ActivitiesTableView", qos: .userInteractive)

    // MARK: - Misc

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.isViewVisibleForNftAnimationPlayback = true
        self.updateNftAnimationPlaybackActivity()
        self.updateVisibleActivityNftAnimationPlayback()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.isViewVisibleForNftAnimationPlayback = false
        self.updateNftAnimationPlaybackActivity()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updateVisibleActivityNftAnimationPlayback()
    }

    public func onSelect(transaction: ApiActivity) {
        guard let account = activityViewModel?.accountContext.account else { return }
        if case .swap(let swap) = transaction,
           swap.status == .pending || swap.status == .pendingTrusted,
           getSwapType(from: swap.from, to: swap.to, accountChains: account.supportedChains) == .crosschainToWallet,
           swap.cex?.status.uiStatus == .pending {
            AppActions.showCrossChainSwapVC(transaction, accountId: account.id)
        } else {
            AppActions.showActivityDetails(accountId: account.id, activity: transaction, context: .normal)
        }
    }

    // MARK: - Collection View

    public func setupCollectionView(collectionViewBottomConstraint: CGFloat) {

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: collectionViewBottomConstraint)
        ])
        dataSource = makeDataSource()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.allowsSelection = false
        collectionView.isScrollEnabled = false
        collectionView.delaysContentTouches = false
        collectionView.accessibilityIdentifier = "collectionView"
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            collectionView.topEdgeEffect.style = .soft
        }

        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        skeletonView.backgroundColor = .clear
        skeletonView.setupView(vertical: true)
        view.addSubview(skeletonView)
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: view.topAnchor),
            skeletonView.leftAnchor.constraint(equalTo: view.leftAnchor),
            skeletonView.rightAnchor.constraint(equalTo: view.rightAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
    }
    
    struct EnvironmentID: Equatable, Hashable {
        var containerId: ObjectIdentifier
        var traitsId: ObjectIdentifier
    }
    
    var cachedSections: [EnvironmentID: NSCollectionLayoutSection] = [:]
    
    @inline(__always) func makeListSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let environmentId = EnvironmentID(containerId: ObjectIdentifier(layoutEnvironment.container), traitsId: ObjectIdentifier(layoutEnvironment.traitCollection))
        if let section = cachedSections[environmentId] {
            return section
        }
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerTopPadding = 0
        configuration.headerMode = .supplementary
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED {
            configuration.separatorConfiguration.color = .air.separator
        }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        cachedSections[environmentId] = section
        return section
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        
        // plain section
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(plainSectionEstimatedHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let plainSection = NSCollectionLayoutSection(group: group)
        plainSection.interGroupSpacing = 0
        plainSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        
        return CollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self else {
                var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                configuration.backgroundColor = .clear
                return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            }
            
            return switch self.dataSource?.sectionIdentifier(for: sectionIndex) {
            case .headerPlaceholder, .custom, .emptyPlaceholder:
                plainSection
            case .placeholderTransactionsSection, .transactions, .none:
                makeListSection(layoutEnvironment: layoutEnvironment)
            }
        }
    }
    
    public func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Row> {
        let customSectionsByID = Dictionary(uniqueKeysWithValues: customSections.map { ($0.id, $0) })
        let headerPlaceholderCellRegistration = UICollectionView.CellRegistration<HeaderPlaceholderCell, Row> { [unowned self] cell, _, _ in
            cell.configure(height: headerPlaceholderHeight)
            cell.backgroundColor = .clear
        }
        let fallbackCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Row> { cell, _, _ in
            cell.backgroundColor = .clear
        }
        let activityCellRegistration = UICollectionView.CellRegistration<ActivityCell, Row> { [unowned self] cell, _, item in
            switch item {
            case .transaction(_, let transactionId):
                if let activityViewModel, let showingTransaction = activityViewModel.activity(forStableId: transactionId) {
                    cell.configure(
                        with: showingTransaction,
                        accountContext: activityViewModel.accountContext,
                        delegate: self
                    )
                    cell.setContextMenuInteraction(makeNftActivityContextMenuInteraction(for: showingTransaction))
                } else {
                    cell.configureSkeleton()
                    cell.setContextMenuInteraction(nil)
                }
            case .transactionPlaceholder, .loadingMore:
                cell.configureSkeleton()
                cell.setContextMenuInteraction(nil)
            case .headerPlaceholder, .custom(_), .emptyPlaceholder:
                cell.setContextMenuInteraction(nil)
                return
            }
        }
        let emptyWalletCellRegistration = UICollectionView.CellRegistration<EmptyWalletCell, Row> { cell, _, _ in
            cell.backgroundColor = .clear
            cell.set(animated: true)
        }
        let dateSupplementaryRegistration = UICollectionView.SupplementaryRegistration<ActivityDateCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, indexPath in
            guard let self, let section = self.dataSource?.sectionIdentifier(for: indexPath.section) else { return }
            switch section {
            case .placeholderTransactionsSection:
                cell.configureSkeleton()
            case .transactions(_, let date):
                cell.configure(with: date)
            case .headerPlaceholder, .custom(_), .emptyPlaceholder:
                break
            }
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .headerPlaceholder:
                return collectionView.dequeueConfiguredReusableCell(using: headerPlaceholderCellRegistration, for: indexPath, item: item)

            case .custom(let id):
                if let customSection = customSectionsByID[id] {
                    return customSection.dequeueCell(collectionView, indexPath)
                }
                assertionFailure("Missing custom section descriptor for id \(id)")
                return collectionView.dequeueConfiguredReusableCell(using: fallbackCellRegistration, for: indexPath, item: item)
                
            case .transaction(_, _), .transactionPlaceholder, .loadingMore:
                return collectionView.dequeueConfiguredReusableCell(using: activityCellRegistration, for: indexPath, item: item)

            case .emptyPlaceholder:
                return collectionView.dequeueConfiguredReusableCell(using: emptyWalletCellRegistration, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: dateSupplementaryRegistration, for: indexPath)
        }

        return dataSource
    }

    private func makeNftActivityContextMenuInteraction(for activity: ApiActivity) -> ContextMenuInteraction? {
        guard case .transaction(let transaction) = activity,
              transaction.isIncoming,
              transaction.status != .failed,
              let nft = transaction.nft,
              let accountId = activityViewModel?.accountContext.accountId else {
            return nil
        }

        return ContextMenuInteraction(
            triggers: [.longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 20.0)
            ),
            pressAnimation: .default(transformMode: .sublayerTransform)
        ) { _ in
            ContextMenuConfiguration(
                rootPage: ContextMenuPage(
                    items: [
                        .action(
                            ContextMenuAction(
                                title: lang("Hide NFT"),
                                icon: .airBundle("MenuHide26"),
                                role: .destructive,
                                handler: {
                                    NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
                                }
                            )
                        )
                    ]
                ),
                backdrop: .dimmed(alpha: 0.14),
                style: nftActivityContextMenuStyle
            )
        }
    }

    public func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        if let activityViewModel {
            return activityViewModel.snapshot
        } else {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.headerPlaceholder])
            snapshot.appendItems([.headerPlaceholder])
            if !activeCustomSectionIDs.isEmpty {
                for customSectionID in activeCustomSectionIDs {
                    let section = Section.custom(customSectionID)
                    snapshot.appendSections([section])
                    snapshot.appendItems([.custom(customSectionID)], toSection: section)
                }
            }
            snapshot.appendSections([.placeholderTransactionsSection])
            snapshot.appendItems(ActivityListViewModel.placeholderTransactionRows)
            return snapshot
        }
    }
    
    private func requestMoreRowsIfNeeded(indexPath: IndexPath) {
        guard let row = dataSource?.itemIdentifier(for: indexPath) else { return }
        Task {
            await activityViewModel?.rowDidBecomeVisible(row)
        }
    }
    
    private func unloadRowsIfNeededAfterScrollingStops() {
        let lastVisibleRow = collectionView.indexPathsForVisibleItems
            .sorted()
            .reversed()
            .lazy
            .compactMap { indexPath in
                self.dataSource?.itemIdentifier(for: indexPath)
            }
            .first { row in
                if case .transaction = row {
                    return true
                }
                return false
            }
        
        Task {
            await activityViewModel?.scrollDidStop(lastVisibleRow: lastVisibleRow)
        }
    }
    
    // MARK: - Reload methods
    
    open func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        guard let dataSource else { return }
        queue.async {
            // @MainActor annotation conflicts with the docs which allow calling consistently on the background thread
            dataSource.apply(snapshot, animatingDifferences: animatingDifferences) {
                DispatchQueue.main.async {
                    self.updateSkeletonViewsIfNeeded(animateAlondside: nil)
                    self.updateVisibleActivityNftAnimationPlayback()
                }
            }
        }
    }
    
    public func reconfigureHeaderPlaceholder(animated: Bool) {
        if let cell = collectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? HeaderPlaceholderCell {
            cell.configure(height: headerPlaceholderHeight)
        }
        
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    public func invalidateCustomSectionLayout(id: String) {
        guard let indexPath = dataSource?.indexPath(for: .custom(id)) else { return }
        let context = UICollectionViewLayoutInvalidationContext()
        context.invalidateItems(at: [indexPath])
        collectionView.collectionViewLayout.invalidateLayout(with: context)
    }

    public func reconfigureCustomSection(id: String) {
        guard let dataSource else { return }
        let currentSnapshot = dataSource.snapshot()
        let row = Row.custom(id)
        guard currentSnapshot.itemIdentifiers.contains(row) else { return }
        queue.async {
            var snapshot = currentSnapshot
            snapshot.reconfigureItems([row])
            // @MainActor annotation conflicts with the docs which allow calling consistently on the background thread
            dataSource.apply(snapshot, animatingDifferences: true) {
                DispatchQueue.main.async {
                    self.updateSkeletonViewsIfNeeded(animateAlondside: nil)
                    self.updateVisibleActivityNftAnimationPlayback()
                }
            }
        }
    }

    public func visibleCustomSectionCell(id: String) -> UICollectionViewCell? {
        guard let indexPath = dataSource?.indexPath(for: .custom(id)) else { return nil }
        return collectionView.cellForItem(at: indexPath)
    }
    
    public func updateTokensInVisibleRows() {
        if collectionView.isDecelerating || collectionView.isTracking {
            self.reconfigureTokensWhenStopped = true
        } else {
            for cell in collectionView.visibleCells {
                if let cell = cell as? ActivityCell {
                    cell.updateToken()
                }
            }
        }
    }
    
    public func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool) {
        let newSnapshot = self.makeSnapshot()
        applySnapshot(newSnapshot, animatingDifferences: true)
        self.updateSkeletonState()
    }
    
    public func tokensChanged() {
        updateTokensInVisibleRows()
    }
    
    // MARK: - Table view delegate
    
    open dynamic func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if reconfigureTokensWhenStopped {
            self.reconfigureTokensWhenStopped = false
            self.updateTokensInVisibleRows()
        }
        unloadRowsIfNeededAfterScrollingStops()
        updateVisibleActivityNftAnimationPlayback()
    }
    
    open dynamic func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            if reconfigureTokensWhenStopped {
                self.reconfigureTokensWhenStopped = false
                self.updateTokensInVisibleRows()
            }
            unloadRowsIfNeededAfterScrollingStops()
            updateVisibleActivityNftAnimationPlayback()
        }
    }

    open func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        requestMoreRowsIfNeeded(indexPath: indexPath)
        updateVisibleActivityNftAnimationPlayback()
    }

    open func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        updateVisibleActivityNftAnimationPlayback()
    }

    public func updateVisibleActivityNftAnimationPlayback() {
        guard isViewLoaded, dataSource != nil else {
            return
        }

        collectionView.layoutIfNeeded()
        var nextEligibleIDs = Set<String>()
        let visibleItems = collectionView.indexPathsForVisibleItems
            .sorted { lhs, rhs in
                if lhs.section != rhs.section {
                    return lhs.section < rhs.section
                }
                return lhs.item < rhs.item
            }
            .compactMap { indexPath -> NftAnimationPlaybackCoordinator.VisibleItem? in
                guard case .transaction = dataSource?.itemIdentifier(for: indexPath),
                      let cell = collectionView.cellForItem(at: indexPath) as? ActivityCell,
                      let id = cell.nftAnimationPlaybackID,
                      cell.hasPlayableNftAnimation else {
                    return nil
                }
                guard self.isEligibleForNftAnimationPlayback(
                    id: id,
                    cell: cell,
                    in: collectionView
                ) else {
                    return nil
                }
                nextEligibleIDs.insert(id)
                return .init(id: id, target: cell)
            }
        self.nftAnimationPlaybackEligibleIDs = nextEligibleIDs
        self.nftAnimationPlaybackCoordinator.updateVisibleItems(visibleItems)
        self.updateNftAnimationPlaybackActivity()
    }

    private var isNftAnimationPlaybackActive: Bool {
        self.isViewVisibleForNftAnimationPlayback && self.viewIfLoaded?.window != nil
    }

    private func updateNftAnimationPlaybackActivity() {
        self.nftAnimationPlaybackCoordinator.setActive(self.isNftAnimationPlaybackActive)
    }

    private func isEligibleForNftAnimationPlayback(
        id: String,
        cell: ActivityCell,
        in collectionView: UICollectionView
    ) -> Bool {
        let cellFrame = cell.convert(cell.bounds, to: collectionView)
        let visibleFrame = cellFrame.intersection(collectionView.bounds)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            return false
        }

        let cellArea = cellFrame.width * cellFrame.height
        guard cellArea > 0 else {
            return false
        }

        let visibleAreaFraction = (visibleFrame.width * visibleFrame.height) / cellArea
        if visibleAreaFraction >= 0.75 {
            return true
        }
        if visibleAreaFraction <= 0.25 {
            return false
        }
        return self.nftAnimationPlaybackEligibleIDs.contains(id)
    }
    
    // MARK: - Skeleton
    
    public func updateSkeletonState() {
        wasShowingSkeletons = skeletonState == .loading
        skeletonState = if activityViewModel?.idsByDate == nil {
            .loading
        } else if activityViewModel?.isEndReached == true {
            .loadedAll
        } else {
            .loadingMore
        }
        collectionView.isScrollEnabled = skeletonState != .loading
    }

    open func updateSkeletonViewsIfNeeded(animateAlondside: ((_ isLoading: Bool) -> ())?) {
        let dataAvailable = activityViewModel?.idsByDate != nil

        if !dataAvailable, !skeletonView.isAnimating, !isInitializingCache {
            view.bringSubviewToFront(skeletonView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let dataAvailable = activityViewModel?.idsByDate != nil
                if !dataAvailable, !skeletonView.isAnimating {
                    updateSkeletonViewMask()
                    skeletonView.startAnimating()
                    animateAlondside?(true)
                }
            }
        } else if dataAvailable {
            if skeletonView.isAnimating {
                skeletonView.stopAnimating()
                animateAlondside?(false)
            }
        }
        if skeletonView.isAnimating {
            self.updateSkeletonViewMask()
        }
    }

    open func updateSkeletonViewMask() {
    }
}

// MARK: - Debug (do not delete yet)

final class MyDataStore<Section: Hashable, Item: Hashable>: UICollectionViewDiffableDataSource<Section, Item> {
    
}

private final class CollectionViewCompositionalLayout: UICollectionViewCompositionalLayout {
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attrs = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
//        print(#function, itemIndexPath, attrs)
        return attrs
    }
}

// MARK: - First Row cell

private final class HeaderPlaceholderCell: UICollectionViewCell {
    private let spacerView = UIView()
    private var heightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        spacerView.backgroundColor = .clear
        contentView.addSubview(spacerView)
        heightConstraint = spacerView.heightAnchor.constraint(equalToConstant: 0)
        
        NSLayoutConstraint.activate([
            spacerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            spacerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            spacerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            spacerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
//            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(height: CGFloat) {
        heightConstraint.constant = height
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
        attrs.size.height = heightConstraint.constant
        return attrs
    }
    
}

open class FirstRowCell: UICollectionViewCell {
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    open override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { }
    }
    
    open var height: CGFloat?
    
    open func configure(height: CGFloat) {
        self.height = height
    }
    
    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let height {
            attrs.size.height = height
        }
        return attrs
    }
}
