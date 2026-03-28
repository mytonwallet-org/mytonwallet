import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("ActivityListViewController")

private let appearAnimationDuration = 0.4
private let plainSectionEstimatedHeight: CGFloat = 300

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


    private let queue = DispatchQueue(label: "ActivitiesTableView", qos: .userInteractive)

    // MARK: - Misc

    open override var hideNavigationBar: Bool { false }

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

    // MARK: - Table views

    public func setupTableViews(tableViewBottomConstraint: CGFloat) {

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: tableViewBottomConstraint)
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
        collectionView.accessibilityIdentifier = "tableView"

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
                } else {
                    cell.configureSkeleton()
                }
            case .transactionPlaceholder, .loadingMore:
                cell.configureSkeleton()
            case .headerPlaceholder, .custom(_), .emptyPlaceholder:
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
    }
    
    open dynamic func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            if reconfigureTokensWhenStopped {
                self.reconfigureTokensWhenStopped = false
                self.updateTokensInVisibleRows()
            }
            unloadRowsIfNeededAfterScrollingStops()
        }
    }

    open func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        requestMoreRowsIfNeeded(indexPath: indexPath)
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
            if let bottomBarBlurView {
                view.bringSubviewToFront(bottomBarBlurView)
            }
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
