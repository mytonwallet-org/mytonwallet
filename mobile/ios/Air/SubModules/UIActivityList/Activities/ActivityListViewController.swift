import ContextMenuKit
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let plainSectionEstimatedHeight: CGFloat = 300
private let nftActivityContextMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

open class ActivityListViewController: WViewController, ActivityCell.Delegate, UICollectionViewDelegate {

    public typealias Section = ActivityListViewModel.Section
    public typealias Row = ActivityListViewModel.Row

    @MainActor
    public protocol CustomSectionDataProvider {
        var id: String { get }
        var itemIdentifiers: [String] { get }

        func prepareForUse()
        func makeLayoutSection(
            layoutEnvironment: NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection?
        func dequeueCell(
            _ collectionView: UICollectionView,
            _ indexPath: IndexPath,
            itemIdentifier: String
        ) -> UICollectionViewCell
        func dequeueSupplementaryView(
            _ collectionView: UICollectionView,
            kind: String,
            indexPath: IndexPath
        ) -> UICollectionReusableView?
        func shouldSelect(itemIdentifier: String) -> Bool
        func didSelect(itemIdentifier: String)
        func willDisplay(_ cell: UICollectionViewCell, itemIdentifier: String)
        func didEndDisplaying(_ cell: UICollectionViewCell, itemIdentifier: String)
    }

    public struct CustomSectionDescriptor: CustomSectionDataProvider {
        public let id: String
        public let dequeueCell: @MainActor (UICollectionView, IndexPath) -> UICollectionViewCell
        private let onWillDisplay: (@MainActor (UICollectionViewCell) -> Void)?

        public var itemIdentifiers: [String] { [id] }

        public init(
            id: String,
            dequeueCell: @escaping @MainActor (UICollectionView, IndexPath) -> UICollectionViewCell,
            willDisplay: (@MainActor (UICollectionViewCell) -> Void)? = nil
        ) {
            self.id = id
            self.dequeueCell = dequeueCell
            self.onWillDisplay = willDisplay
        }

        public func dequeueCell(
            _ collectionView: UICollectionView,
            _ indexPath: IndexPath,
            itemIdentifier: String
        ) -> UICollectionViewCell {
            dequeueCell(collectionView, indexPath)
        }

        public func willDisplay(_ cell: UICollectionViewCell, itemIdentifier: String) {
            onWillDisplay?(cell)
        }
    }

    public lazy var collectionView = ActivitiesCollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?

    public let skeletonView = SkeletonView()
    public var wasShowingSkeletons: Bool = false
    public private(set) var skeletonState: SkeletonState?
    open var isInitializingCache = true

    open var headerPlaceholderHeight: CGFloat { fatalError("abstract") }
    open var headerPlaceholderBottomSpacing: CGFloat { 16 }
    open var customSections: [any CustomSectionDataProvider] { [] }
    open var activeCustomSectionIDs: [String] { customSections.map(\.id) }
    open var trailingCustomSections: [any CustomSectionDataProvider] { [] }
    open var activeTrailingCustomSectionIDs: [String] { trailingCustomSections.map(\.id) }
    open var trailingCustomRows: [any CustomSectionDataProvider] { [] }
    open var activeTrailingCustomRowIDs: [String] { trailingCustomRows.map(\.id) }
    public var customSectionIDs: [String] { activeCustomSectionIDs }
    open var displaysActivitySections: Bool { true }
    open var activityAccountContext: AccountContext? { activityViewModel?.accountContext }
    open var isActivityDataAvailableForSkeleton: Bool { activityViewModel?.idsByDate != nil }
    open var isActivityHistoryEndReachedForSkeleton: Bool { activityViewModel?.isEndReached == true }

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
        guard let accountContext = activityAccountContext else { return }
        let account = accountContext.account
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
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: collectionViewBottomConstraint)
        ])
        dataSource = makeDataSource()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.allowsSelection = true
        collectionView.isScrollEnabled = true
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
            skeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
    }
    
    struct EnvironmentID: Equatable, Hashable {
        var containerId: ObjectIdentifier
        var traitsId: ObjectIdentifier
    }
    
    var cachedSections: [EnvironmentID: NSCollectionLayoutSection] = [:]
    var cachedHeaderlessSections: [EnvironmentID: NSCollectionLayoutSection] = [:]

    private static let customItemIdentifierSeparator = "\u{1F}"

    private var allCustomSectionDataProviders: [any CustomSectionDataProvider] {
        customSections + trailingCustomSections + trailingCustomRows
    }

    private func customSectionDataProvider(id: String) -> (any CustomSectionDataProvider)? {
        allCustomSectionDataProviders.first { $0.id == id }
    }

    private func customRow(sectionID: String, itemIdentifier: String) -> Row {
        .custom(sectionID + Self.customItemIdentifierSeparator + itemIdentifier)
    }

    private func customItemIdentifier(from row: Row, sectionID: String) -> String? {
        guard case .custom(let identifier) = row else { return nil }
        let prefix = sectionID + Self.customItemIdentifierSeparator
        if identifier.hasPrefix(prefix) {
            return String(identifier.dropFirst(prefix.count))
        }
        // ActivityListSnapshotProxy still emits the legacy one-row representation. It is
        // normalized before display, but accepting it here keeps snapshots safe mid-update.
        return identifier == sectionID ? identifier : nil
    }

    private func customRows(for dataProvider: any CustomSectionDataProvider) -> [Row] {
        dataProvider.itemIdentifiers.map {
            customRow(sectionID: dataProvider.id, itemIdentifier: $0)
        }
    }

    private func reconfigurePreviouslyDisplayedRows(
        _ rows: [Row],
        in snapshot: inout NSDiffableDataSourceSnapshot<Section, Row>
    ) {
        guard let dataSource else { return }
        let displayedRows = Set(dataSource.snapshot().itemIdentifiers)
        let nextRows = Set(snapshot.itemIdentifiers)
        let rowsToReconfigure = rows.filter {
            displayedRows.contains($0) && nextRows.contains($0)
        }
        if !rowsToReconfigure.isEmpty {
            snapshot.reconfigureItems(rowsToReconfigure)
        }
    }
    
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

    @inline(__always) func makeHeaderlessListSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let environmentId = EnvironmentID(containerId: ObjectIdentifier(layoutEnvironment.container), traitsId: ObjectIdentifier(layoutEnvironment.traitCollection))
        if let section = cachedHeaderlessSections[environmentId] {
            return section
        }
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .none
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED {
            configuration.separatorConfiguration.color = .air.separator
        }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        cachedHeaderlessSections[environmentId] = section
        return section
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        
        func makePlainSection(bottomSpacing: CGFloat) -> NSCollectionLayoutSection {
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(plainSectionEstimatedHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: bottomSpacing, trailing: 0)
            return section
        }
        let plainSection = makePlainSection(bottomSpacing: 16)
        let headerPlaceholderSection = makePlainSection(bottomSpacing: headerPlaceholderBottomSpacing)
        
        return CollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self else {
                var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                configuration.backgroundColor = .clear
                return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            }
            
            return switch self.dataSource?.sectionIdentifier(for: sectionIndex) {
            case .custom(let id):
                if let customLayout = customSectionDataProvider(id: id)?.makeLayoutSection(
                    layoutEnvironment: layoutEnvironment
                ) {
                    customLayout
                } else if activeTrailingCustomSectionIDs.contains(id) {
                    makeHeaderlessListSection(layoutEnvironment: layoutEnvironment)
                } else {
                    plainSection
                }
            case .headerPlaceholder:
                headerPlaceholderSection
            case .emptyPlaceholder:
                plainSection
            case .placeholderTransactionsSection, .transactions, .none:
                makeListSection(layoutEnvironment: layoutEnvironment)
            }
        }
    }
    
    public func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Row> {
        allCustomSectionDataProviders.forEach { $0.prepareForUse() }
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

        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { [unowned self] collectionView, indexPath, item in
            switch item {
            case .headerPlaceholder:
                return collectionView.dequeueConfiguredReusableCell(using: headerPlaceholderCellRegistration, for: indexPath, item: item)

            case .custom:
                guard case .custom(let sectionID) = self.dataSource?.sectionIdentifier(for: indexPath.section),
                      let dataProvider = self.customSectionDataProvider(id: sectionID),
                      let itemIdentifier = self.customItemIdentifier(from: item, sectionID: sectionID) else {
                    assertionFailure("Missing custom section data provider at \(indexPath)")
                    return collectionView.dequeueConfiguredReusableCell(using: fallbackCellRegistration, for: indexPath, item: item)
                }
                return dataProvider.dequeueCell(
                    collectionView,
                    indexPath,
                    itemIdentifier: itemIdentifier
                )

            case .transaction(_, _), .transactionPlaceholder, .loadingMore:
                return collectionView.dequeueConfiguredReusableCell(using: activityCellRegistration, for: indexPath, item: item)

            case .emptyPlaceholder:
                return collectionView.dequeueConfiguredReusableCell(using: emptyWalletCellRegistration, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { [unowned self] collectionView, kind, indexPath in
            if case .custom(let sectionID) = self.dataSource?.sectionIdentifier(for: indexPath.section),
               let supplementaryView = customSectionDataProvider(id: sectionID)?.dequeueSupplementaryView(
                   collectionView,
                   kind: kind,
                   indexPath: indexPath
               ) {
                return supplementaryView
            }
            return collectionView.dequeueConfiguredReusableSupplementary(using: dateSupplementaryRegistration, for: indexPath)
        }

        return dataSource
    }

    public func makeNftActivityContextMenuInteraction(for activity: ApiActivity) -> ContextMenuInteraction? {
        guard case .transaction(let transaction) = activity,
              transaction.isIncoming,
              transaction.status != .failed,
              let nft = transaction.nft,
              let accountContext = activityAccountContext else {
            return nil
        }
        let accountId = accountContext.accountId

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
                                title: lang("Hide and Report"),
                                icon: .system("flag"),
                                role: .destructive,
                                handler: {
                                    AppActions.hideAndReportNft(accountId: accountId, nft: nft, onConfirmed: nil)
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
        if !displaysActivitySections {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.headerPlaceholder])
            snapshot.appendItems([.headerPlaceholder])
            for customSectionID in activeCustomSectionIDs {
                guard let dataProvider = customSectionDataProvider(id: customSectionID) else {
                    assertionFailure("Missing custom section data provider for id \(customSectionID)")
                    continue
                }
                let section = Section.custom(customSectionID)
                snapshot.appendSections([section])
                let rows = customRows(for: dataProvider)
                snapshot.appendItems(rows, toSection: section)
                reconfigurePreviouslyDisplayedRows(rows, in: &snapshot)
            }
            return snapshot
        }
        if let activityViewModel {
            var snapshot = activityViewModel.snapshot!
            let currentCustomSections = snapshot.sectionIdentifiers.compactMap { section -> Section? in
                if case .custom = section {
                    return section
                }
                return nil
            }
            let activeLeadingIDs = activeCustomSectionIDs
            let activeLeadingSections = activeLeadingIDs.map(Section.custom)
            let activeTrailingIDs = activeTrailingCustomSectionIDs
            let activeTrailingSections = activeTrailingIDs.map(Section.custom)
            let activeCustomSections = activeLeadingSections + activeTrailingSections

            if currentCustomSections != activeCustomSections {
                snapshot.deleteSections(currentCustomSections)
                if !activeLeadingSections.isEmpty {
                    snapshot.insertSections(activeLeadingSections, afterSection: .headerPlaceholder)
                }
                if !activeTrailingSections.isEmpty {
                    snapshot.appendSections(activeTrailingSections)
                }
            }
            for (id, section) in zip(
                activeLeadingIDs + activeTrailingIDs,
                activeLeadingSections + activeTrailingSections
            ) {
                guard let dataProvider = customSectionDataProvider(id: id) else {
                    assertionFailure("Missing custom section data provider for id \(id)")
                    continue
                }
                let currentRows = snapshot.itemIdentifiers(inSection: section)
                let desiredRows = customRows(for: dataProvider)
                if currentRows != desiredRows {
                    snapshot.deleteItems(currentRows)
                    snapshot.appendItems(desiredRows, toSection: section)
                }
                reconfigurePreviouslyDisplayedRows(desiredRows, in: &snapshot)
            }
            if let lastTransactionsSection = snapshot.sectionIdentifiers.last(where: { section in
                if case .transactions = section {
                    return true
                }
                return false
            }) {
                let rows = activeTrailingCustomRowIDs.flatMap { id in
                    customSectionDataProvider(id: id).map(customRows(for:)) ?? []
                }
                snapshot.appendItems(rows, toSection: lastTransactionsSection)
            }
            return snapshot
        } else {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.headerPlaceholder])
            snapshot.appendItems([.headerPlaceholder])
            if !activeCustomSectionIDs.isEmpty {
                for customSectionID in activeCustomSectionIDs {
                    guard let dataProvider = customSectionDataProvider(id: customSectionID) else {
                        assertionFailure("Missing custom section data provider for id \(customSectionID)")
                        continue
                    }
                    let section = Section.custom(customSectionID)
                    snapshot.appendSections([section])
                    let rows = customRows(for: dataProvider)
                    snapshot.appendItems(rows, toSection: section)
                    reconfigurePreviouslyDisplayedRows(rows, in: &snapshot)
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
    
    // MARK: - Reload methods
    
    open func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        guard let dataSource else { return }
        queue.async {
            // @MainActor annotation conflicts with the docs which allow calling consistently on the background thread
            dataSource.apply(snapshot, animatingDifferences: animatingDifferences) {
                DispatchQueue.main.async {
                    self.updateSkeletonViewsIfNeeded(animateAlondside: nil)
                    self.updateVisibleActivityNftAnimationPlayback()
                    self.didApplySnapshot()
                }
            }
        }
    }

    open func didApplySnapshot() {
    }

    @discardableResult
    public func scrollToActivity(
        stableID: String,
        position: UICollectionView.ScrollPosition = .centeredVertically,
        animated: Bool
    ) -> Bool {
        guard let dataSource else { return false }
        let row = dataSource.snapshot().itemIdentifiers.first { item in
            guard case .transaction(_, let itemStableID) = item else { return false }
            return itemStableID == stableID
        }
        guard let row, let indexPath = dataSource.indexPath(for: row) else { return false }
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: indexPath, at: position, animated: animated)
        return true
    }
    
    public func reconfigureHeaderPlaceholder(animated: Bool) {
        if let cell = collectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? HeaderPlaceholderCell {
            cell.configure(height: headerPlaceholderHeight)
        }
        
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    public func invalidateCustomSectionLayout(id: String) {
        guard let dataProvider = customSectionDataProvider(id: id) else { return }
        let indexPaths = customRows(for: dataProvider).compactMap { dataSource?.indexPath(for: $0) }
        guard !indexPaths.isEmpty else { return }
        let context = UICollectionViewLayoutInvalidationContext()
        context.invalidateItems(at: indexPaths)
        collectionView.collectionViewLayout.invalidateLayout(with: context)
    }

    public func reconfigureCustomSection(id: String) {
        guard let dataSource, let dataProvider = customSectionDataProvider(id: id) else { return }
        let currentSnapshot = dataSource.snapshot()
        let rows = customRows(for: dataProvider).filter(currentSnapshot.itemIdentifiers.contains)
        guard !rows.isEmpty else { return }
        queue.async {
            var snapshot = currentSnapshot
            snapshot.reconfigureItems(rows)
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
        guard let dataProvider = customSectionDataProvider(id: id) else { return nil }
        return customRows(for: dataProvider)
            .compactMap { dataSource?.indexPath(for: $0) }
            .compactMap { collectionView.cellForItem(at: $0) }
            .first
    }

    public func firstItemFrame(inCustomSection id: String) -> CGRect? {
        guard let dataProvider = customSectionDataProvider(id: id),
              let row = customRows(for: dataProvider).first,
              let indexPath = dataSource?.indexPath(for: row) else {
            return nil
        }
        return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
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
    
    open func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool) {
        let newSnapshot = self.makeSnapshot()
        applySnapshot(newSnapshot, animatingDifferences: true)
        self.updateSkeletonState()
    }
    
    open func tokensChanged() {
        updateTokensInVisibleRows()
    }
    
    // MARK: - Table view delegate
    
    open dynamic func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if reconfigureTokensWhenStopped {
            self.reconfigureTokensWhenStopped = false
            self.updateTokensInVisibleRows()
        }
        updateVisibleActivityNftAnimationPlayback()
    }
    
    open dynamic func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            if reconfigureTokensWhenStopped {
                self.reconfigureTokensWhenStopped = false
                self.updateTokensInVisibleRows()
            }
            updateVisibleActivityNftAnimationPlayback()
        }
    }

    open func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let (dataProvider, itemIdentifier) = customSectionItem(at: indexPath) else {
            return false
        }
        return dataProvider.shouldSelect(itemIdentifier: itemIdentifier)
    }

    open func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let (dataProvider, itemIdentifier) = customSectionItem(at: indexPath) else { return }
        dataProvider.didSelect(itemIdentifier: itemIdentifier)
    }

    open func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let (dataProvider, itemIdentifier) = customSectionItem(at: indexPath) {
            dataProvider.willDisplay(cell, itemIdentifier: itemIdentifier)
        }
        requestMoreRowsIfNeeded(indexPath: indexPath)
        updateVisibleActivityNftAnimationPlayback()
    }

    open func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let (dataProvider, itemIdentifier) = customSectionItem(at: indexPath) {
            dataProvider.didEndDisplaying(cell, itemIdentifier: itemIdentifier)
        }
        updateVisibleActivityNftAnimationPlayback()
    }

    private func customSectionItem(
        at indexPath: IndexPath
    ) -> ((any CustomSectionDataProvider), String)? {
        guard let dataSource,
              let row = dataSource.itemIdentifier(for: indexPath),
              case .custom(let sectionID) = dataSource.sectionIdentifier(for: indexPath.section),
              let dataProvider = customSectionDataProvider(id: sectionID),
              let itemIdentifier = customItemIdentifier(from: row, sectionID: sectionID) else {
            return nil
        }
        return (dataProvider, itemIdentifier)
    }

    public func updateVisibleActivityNftAnimationPlayback() {
        // Rotation builds a new Home before it appears. Its scroll/layout callbacks
        // must not force another layout just to prepare playback for an inactive view.
        guard isViewVisibleForNftAnimationPlayback, isViewLoaded, dataSource != nil else {
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
                guard let cell = collectionView.cellForItem(at: indexPath) as? ActivityCell,
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
        skeletonState = if !isActivityDataAvailableForSkeleton {
            .loading
        } else if isActivityHistoryEndReachedForSkeleton {
            .loadedAll
        } else {
            .loadingMore
        }
    }

    open func updateSkeletonViewsIfNeeded(animateAlondside: ((_ isLoading: Bool) -> ())?) {
        let dataAvailable = isActivityDataAvailableForSkeleton

        if !dataAvailable, !skeletonView.isAnimating, !isInitializingCache {
            view.bringSubviewToFront(skeletonView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let dataAvailable = isActivityDataAvailableForSkeleton
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

public extension ActivityListViewController.CustomSectionDataProvider {
    func prepareForUse() { }

    func makeLayoutSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        nil
    }

    func dequeueSupplementaryView(
        _ collectionView: UICollectionView,
        kind: String,
        indexPath: IndexPath
    ) -> UICollectionReusableView? {
        nil
    }

    func shouldSelect(itemIdentifier: String) -> Bool {
        false
    }

    func didSelect(itemIdentifier: String) { }

    func willDisplay(_ cell: UICollectionViewCell, itemIdentifier: String) { }

    func didEndDisplaying(_ cell: UICollectionViewCell, itemIdentifier: String) { }
}

// MARK: - Debug

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
