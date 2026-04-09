import UIKit
import UIActivityList
import UIComponents
import UIAssets
import WalletCore
import WalletContext

@MainActor
final class SplitHomeVC: ActivityListViewController, WSensitiveDataProtocol, ActivityListViewModelDelegate, WalletCoreData.EventsObserver, SplitHomeAssetsRowViewDelegate {
    @AccountContext private var account: MAccount
    
    var splitHomeAccountContext: AccountContext { $account }
    private var calledReady = false
    
    private var switchAccountTask: Task<Void, Never>?
    private weak var accountSwitchSnapshotView: UIView?
    private let actionsCustomSectionID = "actions"
    private let assetsCustomSectionID = "assets"
    private weak var splitHomeAssetsSectionCell: SplitHomeAssetsSectionCell?
    private var actionsCustomSectionCellRegistration: UICollectionView.CellRegistration<SplitHomeActionsSectionCell, Row>!
    private var actionsCustomSectionDescriptor: CustomSectionDescriptor!
    private var assetsCustomSectionCellRegistration: UICollectionView.CellRegistration<SplitHomeAssetsSectionCell, Row>!
    private var assetsCustomSectionDescriptor: CustomSectionDescriptor!
    
    override var hideBottomBar: Bool { false }
    override var headerPlaceholderHeight: CGFloat { 0 }
    override var customSections: [CustomSectionDescriptor] { [actionsCustomSectionDescriptor, assetsCustomSectionDescriptor] }
    
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
        
    init(accountSource: AccountSource = .current) {
        self._account = AccountContext(source: accountSource)
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        
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
        StartupTrace.markOnce("home.viewDidLoad", details: "layout=split")
        setupViews()
        registerForOtherViewControllerAppearNotifications()
        WalletCoreData.add(eventObserver: self)
        Task {
            await reloadActivityViewModel(accountChanged: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        StartupTrace.markOnce("home.visible", details: "layout=split")
        StartupTrace.endInterval("startup.toHomeVisible", details: "layout=split")
    }
    
    override func otherViewControllerDidAppear(_ vc: UIViewController) {
        super.otherViewControllerDidAppear(vc)
        
        var topVC: UIViewController = vc
        while topVC != self, let parent = topVC.parent {
            topVC = parent
        }
        if topVC != self {
            editingNavigator?.cancelEditing()
        }
    }
    
    private func cancelEditing() {
        editingNavigator?.cancelEditing()
    }
    
    private func configureAssetsCustomSection(cell: SplitHomeAssetsSectionCell) {
        splitHomeAssetsSectionCell = cell
        updateNavigationItem()
    }
    
    private func configureCustomSections() {
        actionsCustomSectionCellRegistration = UICollectionView.CellRegistration<SplitHomeActionsSectionCell, Row> { cell, _, _ in
            cell.backgroundColor = .clear
        }
        actionsCustomSectionDescriptor = CustomSectionDescriptor(id: actionsCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: actionsCustomSectionCellRegistration, for: indexPath, item: .custom(actionsCustomSectionID))
        }
        assetsCustomSectionCellRegistration = UICollectionView.CellRegistration<SplitHomeAssetsSectionCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureAssetsCustomSection(cell: cell)
        }
        assetsCustomSectionDescriptor = CustomSectionDescriptor(id: assetsCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: assetsCustomSectionCellRegistration, for: indexPath, item: .custom(assetsCustomSectionID))
        }
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.groupedBackground
    }
    
    override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        if activityViewModel?.idsByDate != nil && !calledReady {
            calledReady = true
            StartupTrace.markOnce("home.dataReady", details: "layout=split")
            StartupTrace.endInterval("startup.toHomeReady", details: "layout=split")
            WalletContextManager.delegate?.walletIsReady(isReady: true)
        }
        super.applySnapshot(snapshot, animatingDifferences: animatingDifferences)
    }
    
    func activityViewModelChanged() {
        transactionsUpdated(accountChanged: false, isUpdateEvent: true)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(_, _):
            guard $account.source == .current else { return }
            cancelEditing()
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
            cancelEditing()
            calledReady = false
        case .balanceChanged(let accountId):
            if accountId == resolvedAccountId, activityViewModel == nil {
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
        view.backgroundColor = .air.groupedBackground
        updateNavigationItem()
        
        if !IOS_26_MODE_ENABLED {
            configureNavigationItemWithTransparentBackground()
        }
        
        super.setupTableViews(tableViewBottomConstraint: 0)
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        
        applySnapshot(makeSnapshot(), animatingDifferences: false)
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
            activityViewModel = nil
            applySnapshot(makeSnapshot(), animatingDifferences: true)
            updateSkeletonState()
            calledReady = false
            return
        }
        activityViewModel = await ActivityListViewModel(accountId: accountId, token: nil, customSectionIDs: customSectionIDs, delegate: self)
        transactionsUpdated(accountChanged: accountChanged, isUpdateEvent: false)
    }
    
    @objc private func lockPressed() {
        AppActions.lockApp(animated: true)
    }
    
    @objc private func hidePressed() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }
    
    private func updateNavigationItem() {
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        
        let editingState = editingNavigator?.state.editingState
        let isEditing: Bool
        switch editingState {
        case .reordering:
            leadingItemGroups += editingNavigator!.cancelEditingBarButtonItem.asSingleItemGroup()
            trailingItemGroups += editingNavigator!.commitEditingBarButtonItem.asSingleItemGroup()
            isEditing = true

        case .selection:
            leadingItemGroups += editingNavigator!.selectAllBarButtonItem.asSingleItemGroup()
            trailingItemGroups += editingNavigator!.commitEditingBarButtonItem.asSingleItemGroup()
            isEditing = true

        case nil:
            isEditing = false
            if AuthSupport.accountsSupportAppLock {
                trailingItemGroups += lockItem.asSingleItemGroup()
            }
            trailingItemGroups += hideItem.asSingleItemGroup()
        }
        
        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups
        
        navigationController?.allowBackSwipeToDismiss(!isEditing)
        navigationController?.isModalInPresentation = isEditing
    }
    
    var editingNavigator: NftsEditingNavigator? {
        didSet {
            if editingNavigator !== oldValue {
                editingNavigator?.onStateChange = { [weak self] _, newState in
                    guard let self else { return }
                    if newState.editingState == .selection {
                        self.editingNavigator?.installToolbar(into: view)
                    }
                    self.updateNavigationItem()
                }
            }
        }
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
        collectionView.layoutIfNeeded()
        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.alpha = 1
            return nil
        }
        snapshot.frame = collectionView.frame
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(snapshot)
        view.bringSubviewToFront(snapshot)
        accountSwitchSnapshotView = snapshot
        collectionView.alpha = 0
        return snapshot
    }

    private func finishAccountSwitchCrossfade(snapshot: UIView?) {
        guard let snapshot else {
            collectionView.alpha = 1
            return
        }
        guard accountSwitchSnapshotView === snapshot else { return }
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { [self] in
            collectionView.alpha = 1
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
        collectionView.alpha = 1
    }
}
