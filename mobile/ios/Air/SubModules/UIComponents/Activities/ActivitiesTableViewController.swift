
import UIKit
import WalletCore
import WalletContext

private let log = Log("ActivitiesTableViewController")

private let appearAnimationDuration = 0.4
private let emptyWalletRowHeight: CGFloat = 300

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
    public var wasShowingSkeletons: Bool = false
    public private(set) var skeletonState: SkeletonState?
    open var isInitializingCache = true
    public var forceAnimation = false

    open var headerPlaceholderHeight: CGFloat { fatalError("abstract") }
    open var firstRowPlaceholderHeight: CGFloat { 0 }
    open var firstRow: UITableViewCell.Type? { nil }
    open func configureFirstRow(cell: UITableViewCell) {}
    open var isGeneralDataAvailable: Bool { true }

    open var activityViewModel: ActivityViewModel? { fatalError("abstract") }

    private var reconfigureTokensWhenStopped: Bool = false

    public let processorQueue = DispatchQueue(label: "activities.background_processor")
    public let processorQueueLock = DispatchSemaphore(value: 1)

    private let queue = DispatchQueue(label: "ActivitiesTableView", qos: .userInteractive)

    // MARK: - Misc

    open override var hideNavigationBar: Bool {
        !IOS_26_MODE_ENABLED
    }

    public func onSelect(transaction: ApiActivity) {
        guard let account = activityViewModel?.accountContext.account else { return }
        tableView.beginUpdates()
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.tableView.endUpdates()
            }
        }
        if case .swap(let swap) = transaction, (swap.status == .pending || swap.status == .pendingTrusted), getSwapType(from: swap.from, to: swap.to, accountChains: account.supportedChains) == .crosschainToWallet, swap.cex?.status.uiStatus == .pending {
            AppActions.showCrossChainSwapVC(transaction, accountId: account.id)
        } else {
            AppActions.showActivityDetails(accountId: account.id, activity: transaction, context: .normal)
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
        if let firstRow {
            tableView.register(firstRow, forCellReuseIdentifier: "FirstRow")
        }
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "Transaction")
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "LoadingMoreSkeleton")
        tableView.register(ActivityDateCell.self, forHeaderFooterViewReuseIdentifier: "Date")
        tableView.register(EmptyWalletCell.self, forCellReuseIdentifier: "EmptyWallet")
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.allowsSelection = false
        tableView.isScrollEnabled = false
        tableView.delaysContentTouches = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        if IOS_26_MODE_ENABLED {
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 12)
        } else {
            tableView.separatorColor = WTheme.separator
            tableView.separatorInset.left = 62
        }
        tableView.accessibilityIdentifier = "tableView"

        skeletonTableView.translatesAutoresizingMaskIntoConstraints = false
        skeletonTableView.delegate = self
        skeletonTableView.showsVerticalScrollIndicator = false
        skeletonTableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderPlaceholder")
        skeletonTableView.register(FirstRowCell.self, forCellReuseIdentifier: "FirstRow")
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
        if IOS_26_MODE_ENABLED {
            skeletonTableView.separatorInset = UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 12)
        } else {
            skeletonTableView.separatorColor = WTheme.separator
            skeletonTableView.separatorInset.left = 62
        }
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

            case .transaction(_, let transactionId):
                let cell = tableView.dequeueReusableCell(withIdentifier: "Transaction", for: indexPath) as! ActivityCell
                if let activityViewModel, let showingTransaction = activityViewModel.activity(forStableId: transactionId) {
                    cell.configure(
                        with: showingTransaction,
                        accountContext: activityViewModel.accountContext,
                        delegate: self,
                        shouldFadeOutSkeleton: false
                    )
                } else {
                    cell.configureSkeleton()
                }
                return cell

            case .loadingMore:
                let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingMoreSkeleton", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell

            case .emptyPlaceholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyWallet", for: indexPath) as! EmptyWalletCell
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                cell.set(animated: true)
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
    
    private func requestMoreRowsIfNeeded(indexPath: IndexPath) {
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
        guard let dataSource else { return }
        queue.async {
            dataSource.apply(snapshot, animatingDifferences: animatingDifferences ?? animated)
        }
        if skeletonState == .loading {
            skeletonTableView.beginUpdates()
            skeletonTableView.endUpdates()
        }
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureHeaderPlaceholder(animated: Bool) {
        guard dataSource != nil, skeletonDataSource != nil, activityViewModel != nil else { return }
        if var snapshot = activityViewModel?.snapshot {
            queue.async { [weak dataSource] in
                snapshot.reconfigureItems([.headerPlaceholder])
                dataSource?.apply(snapshot, animatingDifferences: animated)
            }
        }
        if skeletonState == .loading {
            let updates = {
                self.skeletonTableView.beginUpdates()
                self.skeletonTableView.endUpdates()
            }
            if animated {
                updates()
            } else {
                UIView.performWithoutAnimation { updates() }
            }
        }
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureFirstRowCell() {
        guard dataSource != nil, skeletonDataSource != nil else { return }
        if var snapshot = activityViewModel?.snapshot {
            queue.async { [self] in
                if snapshot.itemIdentifiers.contains(.firstRow) {
                    snapshot.reconfigureItems([.firstRow])
                    dataSource?.apply(snapshot)
                }
            }
        }
        if skeletonState == .loading {
            skeletonTableView.beginUpdates()
            skeletonTableView.endUpdates()
        }
        updateSkeletonViewsIfNeeded(animateAlondside: nil)
    }

    public func reconfigureVisibleRows() {
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
        let wasEmpty = if let dataSource, dataSource.snapshot().indexOfSection(.emptyPlaceholder) == nil { false } else { true }
        let newSnapshot = self.makeSnapshot()
        applySnapshot(newSnapshot, animated: true, animatingDifferences: !accountChanged && !wasEmpty)
        self.updateSkeletonState()
    }

    public func tokensChanged() {
        reconfigureVisibleRows()
    }

    // MARK: - Table view delegate

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView == self.tableView, let sectionId = dataSource?.sectionIdentifier(for: section), case .transactions(_, let date) = sectionId {
            let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: "Date") as! ActivityDateCell
            cell.configure(with: date, shouldFadeOutSkeleton: false)
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
                return emptyWalletRowHeight
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
        
        requestMoreRowsIfNeeded(indexPath: indexPath)
        
        guard forceAnimation, let cell = cell as? ActivityCell else { return }
        
        cell.contentView.alpha = 0
        UIView.animate(withDuration: appearAnimationDuration, delay: 0, options: [.curveLinear, .overrideInheritedCurve, .overrideInheritedOptions, .overrideInheritedDuration]) {
            cell.contentView.alpha = 1
        }
    }
    
    public func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {

        guard forceAnimation, let view = view as? ActivityDateCell else { return }
        
        view.contentView.alpha = 0
        UIView.animate(withDuration: appearAnimationDuration, delay: 0, options: [.curveLinear, .overrideInheritedCurve, .overrideInheritedOptions, .overrideInheritedDuration]) {
            view.contentView.alpha = 1
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
}


// MARK: - First Row cell

open class FirstRowCell: UITableViewCell {
    open override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { }
    }
}
