import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
final class SplitHomeVC: ActivitiesTableViewController, WSensitiveDataProtocol, ActivityViewModelDelegate, WalletCoreData.EventsObserver, SplitHomeAssetsRowViewDelegate {
    @AccountContext private var account: MAccount
    
    var splitHomeAccountContext: AccountContext { $account }
    private var calledReady = false
    
    private var _activityViewModel: ActivityViewModel?
    override var activityViewModel: ActivityViewModel? { _activityViewModel }
    private var switchAccountTask: Task<Void, Never>?
    private weak var accountSwitchSnapshotView: UIView?
    private weak var splitHomeActionsRowCell: SplitHomeActionsRowCell?
    
    override var hideNavigationBar: Bool { false }
    override var hideBottomBar: Bool { false }
    override var headerPlaceholderHeight: CGFloat { 12 }
    override var firstRowPlaceholderHeight: CGFloat { SplitHomeActionsRowCell.rowHeight }
    override var firstRow: UITableViewCell.Type? { SplitHomeActionsRowCell.self }
    
    override var isGeneralDataAvailable: Bool {
        guard let accountId = resolvedAccountId else { return false }
        let balances = BalanceStore.getAccountBalances(accountId: accountId)
        return TokenStore.swapAssets != nil
            && TokenStore.tokens.count > 1
            && !balances.isEmpty
            && (balances[TONCOIN_SLUG] != nil || balances[TRX_SLUG] != nil)
    }
    
    private lazy var lockItem: UIBarButtonItem = UIBarButtonItem(
        title: lang("Lock"),
        image: .airBundle("HomeLock24"),
        target: self,
        action: #selector(lockPressed)
    )
    
    private lazy var hideItem: UIBarButtonItem = {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        let image = UIImage.airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
        return UIBarButtonItem(title: lang("Hide"), image: image, target: self, action: #selector(hidePressed))
    }()
    
    private lazy var cancelItem = UIBarButtonItem.cancelTextButtonItem { [weak self] in
        self?.stopReordering(isCanceled: true)
    }
    
    private lazy var doneItem = UIBarButtonItem.doneButtonItem { [weak self] in
        self?.stopReordering(isCanceled: false)
    }
    
    init(accountSource: AccountSource = .current) {
        self._account = AccountContext(source: accountSource)
        super.init(nibName: nil, bundle: nil)
        
        if $account.source != .current {
            _account.onAccountDeleted = { [weak self] in
                self?.removeSelfFromStack()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    isolated deinit {
        guard case .accountId(let accountId) = $account.source else { return }
        Task {
            try? await AccountStore.removeAccountIfTemporary(accountId: accountId)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        registerForOtherViewControllerAppearNotifications()
        WalletCoreData.add(eventObserver: self)
        Task {
            await reloadActivityViewModel(accountChanged: true)
        }
    }
    
    override func otherViewControllerDidAppear(_ vc: UIViewController) {
        super.otherViewControllerDidAppear(vc)
        
        var topVC: UIViewController = vc
        while topVC != self, let parent = topVC.parent {
            topVC = parent
        }
        if topVC != self {
            stopReordering(isCanceled: true)
        }
    }
    
    override func configureFirstRow(cell: UITableViewCell) {
        super.configureFirstRow(cell: cell)
        
        guard let splitHomeActionsRowCell = cell as? SplitHomeActionsRowCell else { return }
        self.splitHomeActionsRowCell = splitHomeActionsRowCell
        updateNavigationItem()
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
    
    override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool, animatingDifferences: Bool? = nil) {
        if isGeneralDataAvailable && !calledReady {
            calledReady = true
            WalletContextManager.delegate?.walletIsReady(isReady: true)
        }
        super.applySnapshot(snapshot, animated: animated, animatingDifferences: animatingDifferences)
    }
    
    func activityViewModelChanged() {
        transactionsUpdated(accountChanged: false, isUpdateEvent: true)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(_, _):
            guard $account.source == .current else { return }
            stopReordering(isCanceled: true)
            switchAccountTask?.cancel()
            switchAccountTask = Task { [weak self] in
                guard let self else { return }
                let snapshot = prepareAccountSwitchCrossfade()
                await reloadActivityViewModel(accountChanged: true)
                guard !Task.isCancelled else {
                    cleanupAccountSwitchCrossfade(snapshot: snapshot)
                    return
                }
                finishAccountSwitchCrossfade(snapshot: snapshot)
            }
        case .accountsReset:
            guard $account.source == .current else { return }
            stopReordering(isCanceled: true)
            _activityViewModel = nil
            applySnapshot(makeSnapshot(), animated: false)
            updateSkeletonState()
            calledReady = false
        case .balanceChanged(let accountId, let isFirstUpdate):
            if accountId == resolvedAccountId, isFirstUpdate, _activityViewModel == nil {
                Task {
                    await reloadActivityViewModel(accountChanged: true)
                }
            }
        case .tokensChanged, .baseCurrencyChanged(_), .assetsAndActivityDataUpdated:
            tokensChanged()
        default:
            break
        }
    }
    
    func updateSensitiveData() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        hideItem.image = .airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
    }
    
    private func setupViews() {
        view.backgroundColor = WTheme.groupedBackground
        updateNavigationItem()
        
        if !IOS_26_MODE_ENABLED {
            configureNavigationItemWithTransparentBackground()
        }
        
        super.setupTableViews(tableViewBottomConstraint: 0)
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        tableView.contentInset.top = 0
        skeletonTableView.contentInset.top = 0
        
        applySnapshot(makeSnapshot(), animated: false)
        applySkeletonSnapshot(makeSkeletonSnapshot(), animated: false)
        updateSkeletonState()
        
        updateTheme()
    }
    
    private var resolvedAccountId: String? {
        switch $account.source {
        case .current:
            AccountStore.accountId
        case .accountId(let accountId):
            accountId
        case .constant(let account):
            account.id
        }
    }
    
    private func reloadActivityViewModel(accountChanged: Bool) async {
        guard let accountId = resolvedAccountId else {
            _activityViewModel = nil
            applySnapshot(makeSnapshot(), animated: false)
            updateSkeletonState()
            calledReady = false
            return
        }
        _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, showFirstRow: true, delegate: self)
        transactionsUpdated(accountChanged: accountChanged, isUpdateEvent: false)
    }
    
    @objc private func lockPressed() {
        AppActions.lockApp(animated: true)
    }
    
    @objc private func hidePressed() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }
    
    private func stopReordering(isCanceled: Bool) {
        splitHomeActionsRowCell?.stopAssetsReordering(isCanceled: isCanceled)
    }
    
    private var isReorderingNfts: Bool {
        splitHomeActionsRowCell?.isAssetsReordering == true
    }
    
    private func updateNavigationItem() {
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        
        if isReorderingNfts {
            leadingItemGroups += cancelItem.asSingleItemGroup()
            trailingItemGroups += doneItem.asSingleItemGroup()
        } else {
            if AuthSupport.accountsSupportAppLock {
                trailingItemGroups += lockItem.asSingleItemGroup()
            }
            trailingItemGroups += hideItem.asSingleItemGroup()
        }
        
        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups
        navigationController?.allowBackSwipeToDismiss(!isReorderingNfts)
        navigationController?.isModalInPresentation = isReorderingNfts
    }
    
    func splitHomeAssetsRowViewDidChangeReorderingState(_ view: SplitHomeAssetsRowView) {
        updateNavigationItem()
    }
    
    private func removeSelfFromStack() {
        if let navigationController {
            if navigationController.topViewController === self {
                navigationController.popViewController(animated: true)
            } else {
                navigationController.viewControllers = navigationController.viewControllers.filter { $0 !== self }
            }
        }
    }

    @discardableResult
    private func prepareAccountSwitchCrossfade() -> UIView? {
        cleanupAccountSwitchCrossfade()
        view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        guard let snapshot = tableView.snapshotView(afterScreenUpdates: false) else {
            tableView.alpha = 1
            return nil
        }
        snapshot.frame = tableView.frame
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(snapshot)
        view.bringSubviewToFront(snapshot)
        accountSwitchSnapshotView = snapshot
        tableView.alpha = 0
        return snapshot
    }

    private func finishAccountSwitchCrossfade(snapshot: UIView?) {
        guard let snapshot else {
            tableView.alpha = 1
            return
        }
        guard accountSwitchSnapshotView === snapshot else { return }
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { [self] in
            tableView.alpha = 1
            snapshot.alpha = 0
        } completion: { [weak self] _ in
            snapshot.removeFromSuperview()
            if self?.accountSwitchSnapshotView === snapshot {
                self?.accountSwitchSnapshotView = nil
            }
        }
    }

    private func cleanupAccountSwitchCrossfade(snapshot: UIView? = nil) {
        if let snapshot {
            guard accountSwitchSnapshotView === snapshot else { return }
            snapshot.removeFromSuperview()
            accountSwitchSnapshotView = nil
        } else {
            accountSwitchSnapshotView?.removeFromSuperview()
            accountSwitchSnapshotView = nil
        }
        tableView.alpha = 1
    }
}
