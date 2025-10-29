
import UIKit
import WalletCore
import WalletContext

private let log = Log("ActivitiesTableViewController")

open class ActivitiesTableViewController: WViewController, ActivityCell.Delegate, UITableViewDelegate {

    public typealias Section = ActivityViewModel.Section
    public typealias Row = ActivityViewModel.Row

    public enum SkeletonSection: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case main
    }
    public enum SkeletonRow: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case transactionPlaceholder(Int)
    }

    public var tableView = ActivitiesTableView(frame: .zero, style: .insetGrouped)
    private var dataSource: UITableViewDiffableDataSource<Section, Row>?
    public var skeletonTableView = UITableView(frame: .zero, style: .insetGrouped)
    private var skeletonDataSource: UITableViewDiffableDataSource<SkeletonSection, SkeletonRow>?

    public let skeletonView = SkeletonView()
    public let emptyWalletView = EmptyWalletView()

    public var wasShowingSkeletons: Bool = false
    public private(set) var skeletonState: SkeletonState? {
        didSet {
            log.info("skeletonState: \(skeletonState as Any, .public)")
        }
    }
    open var isInitializingCache = true

    open var headerPlaceholderHeight: CGFloat { fatalError("abstract") }
    open var firstRowPlaceholderHeight: CGFloat { 0 }
    open var firstRow: UITableViewCell.Type? { nil }
    open func configureFirstRow(cell: UITableViewCell) {}
    open var isGeneralDataAvailable: Bool { true }
    open var account: MAccount? { AccountStore.account }

    open var activityViewModel: ActivityViewModel? { fatalError("abstract") }

    private var reconfigureTokensWhenStopped: Bool = false

    public let processorQueue = DispatchQueue(label: "activities.background_processor")
    public let processorQueueLock = DispatchSemaphore(value: 1)

    // MARK: - Misc

    open override var hideNavigationBar: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            false
        } else {
            true
        }
    }

    public func onSelect(transaction: ApiActivity) {
        tableView.beginUpdates()
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.tableView.endUpdates()
            }
        }
        if case .swap(let swap) = transaction, (swap.status == .pending || swap.status == .pendingTrusted), swap.swapType == .crossChainToTon, swap.cex?.status.uiStatus == .pending {
            AppActions.showCrossChainSwapVC(transaction)
        } else {
            if let accountId = AccountStore.accountId {
                AppActions.showActivityDetails(accountId: accountId, activity: transaction)
            }
        }
    }

    // MARK: - Table views

    public func setupTableViews(tableViewBottomConstraint: CGFloat) {

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: tableViewBottomConstraint)
        ])
        dataSource = makeDataSource()

        // configure skeleton table view
        view.addSubview(skeletonTableView)
        NSLayoutConstraint.activate([
            skeletonTableView.topAnchor.constraint(equalTo: view.topAnchor),
            skeletonTableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            skeletonTableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            skeletonTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        skeletonDataSource = makeSkeletonDataSource()

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.showsVerticalScrollIndicator = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderPlaceholder")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BottomPlaceholder")
        if let firstRow {
            tableView.register(firstRow, forCellReuseIdentifier: "FirstRow")
        }
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "Transaction")
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "LoadingMoreSkeleton")
        tableView.register(ActivityDateCell.self, forHeaderFooterViewReuseIdentifier: "Date")
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.allowsSelection = false
        tableView.isScrollEnabled = false
        tableView.delaysContentTouches = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            tableView.separatorColor = WTheme.separator
        }
        tableView.separatorInset.left = 62
        tableView.accessibilityIdentifier = "tableView"

        skeletonTableView.translatesAutoresizingMaskIntoConstraints = false
        skeletonTableView.delegate = self
        skeletonTableView.showsVerticalScrollIndicator = false
        skeletonTableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderPlaceholder")
        skeletonTableView.register(ActivityCell.self, forCellReuseIdentifier: "Transaction")
        skeletonTableView.register(ActivityDateCell.self, forHeaderFooterViewReuseIdentifier: "Date")
        skeletonTableView.estimatedRowHeight = 0
        skeletonTableView.backgroundColor = .clear
        skeletonTableView.contentInsetAdjustmentBehavior = .never
        skeletonTableView.isUserInteractionEnabled = false
        skeletonTableView.alpha = 0
        skeletonTableView.sectionHeaderTopPadding = 0
        skeletonTableView.sectionHeaderHeight = 0
        skeletonTableView.sectionFooterHeight = 0
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            skeletonTableView.separatorColor = WTheme.separator
        }
        skeletonTableView.separatorInset.left = 62
        skeletonTableView.accessibilityIdentifier = "skeletonTableView"

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

        view.addSubview(emptyWalletView)
        NSLayoutConstraint.activate([
            emptyWalletView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 20),
            emptyWalletView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -20),
            emptyWalletView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8).withPriority(.defaultLow),
        ])
    }

    public func makeDataSource() -> UITableViewDiffableDataSource<Section, Row> {
        let dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView) { [unowned self] tableView, indexPath, item in
            switch item {
            case .headerPlaceholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderPlaceholder", for: indexPath)
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                cell.tag = 123
                return cell

            case .firstRow:
                let cell = tableView.dequeueReusableCell(withIdentifier: "FirstRow", for: indexPath)
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                configureFirstRow(cell: cell)
                return cell

            case .transaction(let transactionId):
                let showingTransaction = activityViewModel?.activitiesById?[transactionId]
                let cell = tableView.dequeueReusableCell(withIdentifier: "Transaction", for: indexPath) as! ActivityCell
                if let showingTransaction {
                    cell.configure(with: showingTransaction,
                                delegate: self,
                                shouldFadeOutSkeleton: false)
                } else {
                    cell.configureSkeleton()
                }
                return cell

            case .loadingMore:
                let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingMoreSkeleton", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell

            case .emptyPlaceholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "BottomPlaceholder", for: indexPath)
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                return cell
            }
        }

        dataSource.defaultRowAnimation = .fade

        return dataSource
    }

    public func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        if let activityViewModel {
            return activityViewModel.snapshot
        } else {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.headerPlaceholder])
            snapshot.appendItems([.headerPlaceholder])
            if firstRow != nil {
                snapshot.appendSections([.firstRow])
                snapshot.appendItems([.firstRow])
            }
            return snapshot
        }
    }

    // MARK: - Skeleton table

    public func makeSkeletonDataSource() -> UITableViewDiffableDataSource<SkeletonSection, SkeletonRow> {
        return UITableViewDiffableDataSource<SkeletonSection, SkeletonRow>(tableView: skeletonTableView) { tableView, indexPath, item in
            switch item {
            case .headerPlaceholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderPlaceholder", for: indexPath)
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                return cell

            case .transactionPlaceholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Transaction", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell
            }
        }
    }

    public func makeSkeletonSnapshot() -> NSDiffableDataSourceSnapshot<SkeletonSection, SkeletonRow> {
        var snapshot = NSDiffableDataSourceSnapshot<SkeletonSection, SkeletonRow>()
        snapshot.appendSections([.headerPlaceholder])
        snapshot.appendItems([.headerPlaceholder])
        snapshot.appendSections([.main])
        for i in 0..<100 {
            snapshot.appendItems([.transactionPlaceholder(i)])
        }

        return snapshot
    }

    open func applySkeletonSnapshot(_ snapshot: NSDiffableDataSourceSnapshot<SkeletonSection, SkeletonRow>, animated: Bool) {
        guard skeletonDataSource != nil else { return }
        skeletonDataSource?.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Reload methods

    open func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool, animatingDifferences: Bool? = nil) {
        let start = Date()
        defer { log.info("applySnapshot(\(animated), \(animatingDifferences as Any, .public)): \(Date().timeIntervalSince(start))s")}
        guard dataSource != nil else { return }
        if animated {
            dataSource?.apply(snapshot, animatingDifferences: animatingDifferences ?? true)
        } else {
            UIView.performWithoutAnimation {
                dataSource?.apply(snapshot, animatingDifferences: animatingDifferences ?? false)
            }
        }
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureHeaderPlaceholder() {
        let start = Date()
        defer {
            let t = Date().timeIntervalSince(start)
            if t > 0.004 {
                log.info("reconfigureHeaderPlaceholder: \(t)s \t[!]")
            }
        }
        guard dataSource != nil, skeletonDataSource != nil else { return }
        // force layout
        tableView.beginUpdates()
        if skeletonState == .loading {
            skeletonTableView.beginUpdates()
            skeletonTableView.endUpdates()
        }
        tableView.endUpdates()
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureFirstRowCell() {
        guard dataSource != nil, skeletonDataSource != nil else { return }
        tableView.beginUpdates()

        if let snapshot = dataSource?.snapshot(),
           snapshot.itemIdentifiers.contains(.firstRow) {
            var updatedSnapshot = snapshot
            updatedSnapshot.reconfigureItems([.firstRow])
            dataSource?.apply(updatedSnapshot, animatingDifferences: false)
        }

        if skeletonState == .loading {
            skeletonTableView.beginUpdates()
            skeletonTableView.endUpdates()
        }
        tableView.endUpdates()
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureVisibleRows() {
//        let start = Date()
//        defer { log.info("reconfigureVisibleRows: \(Date().timeIntervalSince(start))s")}
        if tableView.isDecelerating || tableView.isTracking {
            self.reconfigureTokensWhenStopped = true
        } else {
            for cell in tableView.visibleCells {
                if let cell = cell as? ActivityCell {
                    cell.updateToken()
                }
            }
        }
    }

    public func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool) {
        let start = Date()
        defer { log.info("transactionsUpdated: \(Date().timeIntervalSince(start))s")}
        updateEmptyView()
        let wasEmpty = if let dataSource, dataSource.snapshot().numberOfSections >= 3 { false } else { true }
        let newSnapshot = self.makeSnapshot()
        applySnapshot(newSnapshot, animated: !accountChanged, animatingDifferences: !wasEmpty)
        self.updateSkeletonState()
        updateEmptyView()
    }

    public func tokensChanged() {
        reconfigureVisibleRows()
    }

    // MARK: - Table view delegate

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView == self.tableView, let sectionId = dataSource?.sectionIdentifier(for: section), case .transactions(let date) = sectionId {
            let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: "Date") as! ActivityDateCell
            cell.configure(with: date, isFirst: section == 1, shouldFadeOutSkeleton: false)
            return cell
        } else if tableView == self.skeletonTableView, section == 1 {
            let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: "Date") as! ActivityDateCell
            cell.configureSkeleton()
            return cell
        }
        return nil
    }

    /// - Note: jumps when scrolling up without this method
    public func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 0
        } else {
            return 54
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {

        if tableView === self.tableView, let id = dataSource?.itemIdentifier(for: indexPath) {
            switch id {
            case .headerPlaceholder:
                return headerPlaceholderHeight
            case .firstRow, .transaction, .loadingMore:
                return /*cellHeightsCache[id] ??*/ UITableView.automaticDimension
            case .emptyPlaceholder:
                return 300
            }
        } else if tableView === self.skeletonTableView, let id = skeletonDataSource?.itemIdentifier(for: indexPath) {
            switch id {
            case .headerPlaceholder:
                return headerPlaceholderHeight + firstRowPlaceholderHeight
            case .transactionPlaceholder:
                return 60
            }
        }
        assertionFailure()
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 0
        } else {
            return 54
        }
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if activityViewModel?.isEndReached != true {
            Task.detached { [self] in
                if await activityViewModel?.loadMoreTask == nil,
                    await tableView === self.tableView, let id = await dataSource?.itemIdentifier(for: indexPath) {
                    if let snapshot = await dataSource?.snapshot(), snapshot.itemIdentifiers.suffix(20).contains(id) {
                        await activityViewModel?.requestMoreIfNeeded()
                    }
                }
            }
        }

        // insert animation fixups
        if tableView === self.tableView, self.tableView.animatingRowsInsertion.contains(indexPath) {
            let delay: Double = if self.tableView.animatingRowsInsertion.count == 1 {
                self.tableView.animatingRowsDeletion.isEmpty ? 0.15 /* slide in from top */ : 0.15 /* replace */
            } else {
                0
            }
            if let snapshot = self.tableView.deleteSnapshot, let sv = snapshot.superview {
                sv.bringSubviewToFront(snapshot)
            }
            cell.contentView.alpha = 0
            UIView.animate(withDuration: 0.3, delay: delay, options: [.curveEaseOut, .allowUserInteraction]) {
                cell.contentView.alpha = 1
            } completion: { _ in
                self.tableView.animatingRowsInsertion = []
                self.tableView.animatingRowsDeletion = []
            }

            // Fix ugly corners showing up for the cell that is animating from the top spot
            if indexPath.row == 0, let nextCell = self.tableView.cellForRow(at: indexPath) {

                let oldMask = nextCell.mask
                let mask = UIView()
                mask.translatesAutoresizingMaskIntoConstraints = false
                mask.frame = nextCell.bounds
                mask.backgroundColor = .white
                mask.layer.cornerRadius = nextCell.layer.cornerRadius
                mask.layer.maskedCorners = [nextCell.layer.maskedCorners, .layerMinXMinYCorner, .layerMaxXMinYCorner]
                nextCell.mask = mask
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nextCell.mask = oldMask
                }
            }
        }
    }

    open dynamic func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if reconfigureTokensWhenStopped {
            self.reconfigureTokensWhenStopped = false
            self.reconfigureVisibleRows()
        }
    }

    open dynamic func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            if reconfigureTokensWhenStopped {
                self.reconfigureTokensWhenStopped = false
                self.reconfigureVisibleRows()
            }
        }
    }

    // MARK: - Skeleton and empty view

    public func updateSkeletonState() {
        wasShowingSkeletons = skeletonState == .loading
        skeletonState = if activityViewModel?.idsByDate == nil {
            .loading
        } else if activityViewModel?.isEndReached == true {
            .loadedAll
        } else {
            .loadingMore
        }
        tableView.isScrollEnabled = skeletonState != .loading
        UIView.animate(withDuration: 0.3) { [self] in
            skeletonTableView.alpha = skeletonState == .loading ? 1 : 0
        }
    }

    open func updateSkeletonViewsIfNeeded(animateAlondside: ((_ isLoading: Bool) -> ())?) {
        let dataAvailable = isGeneralDataAvailable && activityViewModel?.idsByDate != nil

        if !dataAvailable, !skeletonView.isAnimating, !isInitializingCache {
            // Bring the skeleton view to front
            view.bringSubviewToFront(skeletonView)
            if let bottomBarBlurView {
                view.bringSubviewToFront(bottomBarBlurView)
            }
            // Show skeleton rows
            skeletonTableView.alpha = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                // After 500 miliseconds, start the glare effect if loading yet
                let dataAvailable = isGeneralDataAvailable && activityViewModel?.idsByDate != nil
                if !dataAvailable, !skeletonView.isAnimating {
                    updateSkeletonViewMask()
                    skeletonView.startAnimating()
                    animateAlondside?(true)
                }
            }
        } else if dataAvailable {
            // Stop the glare animation
            if skeletonView.isAnimating {
                skeletonView.stopAnimating()
                animateAlondside?(false)
            }
            // Hide the skeleton table view
            UIView.animate(withDuration: 0.3) {
                self.skeletonTableView.alpha = 0
            }
        }
        // Always update the skeleton views to make sure the glare effect doesn't break
        if skeletonView.isAnimating {
            self.updateSkeletonViewMask()
        }
    }

    open func updateSkeletonViewMask() {
    }

    public func updateEmptyView() {
        if activityViewModel?.activitiesById?.isEmpty == true {
            emptyWalletView.set(state: .empty(address: account?.firstAddress ?? ""), animated: true)
        } else {
            emptyWalletView.set(state: .hidden, animated: true)
        }
    }
}
