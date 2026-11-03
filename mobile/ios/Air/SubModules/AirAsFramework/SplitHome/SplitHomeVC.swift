import UIKit
import UIActivityList
import UIComponents
import UIAssets
import UIHome
import WalletCore
import WalletContext

@MainActor
final class SplitHomeVC: ActivityListViewController, ActivityListViewModelDelegate, WalletCoreData.EventsObserver, SplitHomeAssetsRowViewDelegate {
    @AccountContext private var account: MAccount

    var splitHomeAccountContext: AccountContext { $account }
    var onWalletAssetsEditingStateChange: (() -> Void)?
    private var didReportDataReady = false

    private var switchAccountTask: Task<Void, Never>?
    private weak var accountSwitchSnapshotView: UIView?
    private var removesTemporaryAccountOnDeinit = true
    private let actionsCustomSectionID = "actions"
    private let assetsCustomSectionID = "assets"
    private weak var splitHomeAssetsSectionCell: SplitHomeAssetsSectionCell?
    private var actionsCustomSectionDescriptor: SplitHomeRowSection<SplitHomeActionsSectionCell>?
    private var assetsCustomSectionDescriptor: SplitHomeRowSection<SplitHomeAssetsSectionCell>?
    private var actionsLayout: SplitHomeActionsLayout?

    override var hideBottomBar: Bool { false }
    override var headerPlaceholderHeight: CGFloat { 0 }
    override var customSections: [any CustomSectionDataProvider] {
        let sections: [(any CustomSectionDataProvider)?] = [
            actionsCustomSectionDescriptor, assetsCustomSectionDescriptor,
        ]
        return sections.compactMap { $0 }
    }

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

    nonisolated deinit {
        guard removesTemporaryAccountOnDeinit else { return }
        // Avoid isolated-deinit back-deployment on older runtimes. Keep the
        // account context alive until cleanup can read it on the main actor.
        Task { @MainActor [accountContext = _account] in
            guard case .accountId(let accountId) = accountContext.source else { return }
            try? await AccountStore.removeAccountIfTemporary(accountId: accountId)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Wallet")
        navigationItem.titleView = UIView()
        StartupTrace.markOnce("home.viewDidLoad", details: "layout=split")
        setupViews()
        registerForOtherViewControllerAppearNotifications()
        WalletCoreData.add(eventObserver: self)
        Task {
            await reloadActivityViewModel(accountChanged: true)
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateTopInset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTopInset()
    }

    private func updateTopInset() {
        // Like Search, keep the empty bar in native transitions without reserving
        // a row above Home. Editing, pushed accounts and UIKit's sidebar toggle
        // still need that row when the primary column is not beside Home.
        var topInset: CGFloat = 0
        let hasSidebarToggle = splitViewController.map { $0.displayMode != .oneBesideSecondary } ?? false
        if navigationController?.viewControllers.first === self,
           editingNavigator?.state.editingState == nil, !hasSidebarToggle,
           let bar = navigationController?.navigationBar, !bar.isHidden {
            topInset = -bar.bounds.height
        }
        if additionalSafeAreaInsets.top != topInset {
            additionalSafeAreaInsets.top = topInset
        }
        if #available(iOS 26, *) {
            // The empty transparent bar must not blur content occupying its row.
            collectionView.topEdgeEffect.isHidden = topInset < 0
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        (splitViewController as? SplitRootViewController)?.syncSidebarFocusWithHomeStack(animated: animated)
        StartupTrace.markOnce("home.visible", details: "layout=split")
        StartupTrace.endInterval("startup.toHomeVisible", details: "layout=split")
        // Deep links can proceed while activity history is loading; the runtime still requires unlock.
        if WalletContextManager.delegate?.isWalletReady == false {
            WalletContextManager.delegate?.walletIsReady(isReady: true)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let layout = currentActionsLayout
        guard actionsLayout != layout else { return }
        actionsLayout = layout
        (visibleCustomSectionCell(id: actionsCustomSectionID) as? SplitHomeActionsSectionCell)?.configure(layout: layout)
        invalidateCustomSectionLayout(id: actionsCustomSectionID)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            view.setNeedsLayout()
        }
    }

    private var currentActionsLayout: SplitHomeActionsLayout {
        SplitHomeActionsLayout(
            windowHeight: view.window?.bounds.height ?? view.bounds.height,
            traitCollection: traitCollection
        )
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
        actionsCustomSectionDescriptor = SplitHomeRowSection(id: actionsCustomSectionID) { [unowned self] cell in
            cell.backgroundColor = .clear
            cell.configure(layout: currentActionsLayout)
        }
        assetsCustomSectionDescriptor = SplitHomeRowSection(id: assetsCustomSectionID) { [unowned self] cell in
            cell.backgroundColor = .clear
            configureAssetsCustomSection(cell: cell)
        }
    }

    private func updateTheme() {
        view.backgroundColor = .air.groupedBackground
    }

    override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        if activityViewModel?.idsByDate != nil && !didReportDataReady {
            didReportDataReady = true
            StartupTrace.markOnce("home.dataReady", details: "layout=split")
            StartupTrace.endInterval("startup.toHomeReady", details: "layout=split")
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
            didReportDataReady = false
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

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground
        updateNavigationItem()

        configureNavigationItemWithTransparentBackground()

        super.setupCollectionView(collectionViewBottomConstraint: 0)
        additionalSafeAreaInsets.left = 4
        additionalSafeAreaInsets.right = 4

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
            didReportDataReady = false
            return
        }
        activityViewModel = await ActivityListViewModel(accountId: accountId, token: nil, customSectionIDs: customSectionIDs, delegate: self)
        transactionsUpdated(accountChanged: accountChanged, isUpdateEvent: false)
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
            trailingItemGroups += editingNavigator!.cancelXEditingBarButtonItem.asSingleItemGroup()
            isEditing = true

        case nil:
            isEditing = false
        }

        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups

        navigationController?.allowBackSwipeToDismiss(!isEditing)
        navigationController?.isModalInPresentation = isEditing
        updateTopInset()
    }

    var editingNavigator: NftsEditingNavigator? {
        didSet {
            if editingNavigator !== oldValue {
                editingNavigator?.onStateChange = { [weak self] _, newState in
                    guard let self else { return }
                    if newState.editingState == .selection {
                        self.editingNavigator?.installToolbar(into: navigationController?.view ?? view)
                    }
                    self.updateNavigationItem()
                    self.onWalletAssetsEditingStateChange?()
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
    func prepareAccountSwitchCrossfade() -> UIView? {
        cleanupAccountSwitchCrossfade(snapshot: accountSwitchSnapshotView)
        guard shouldAnimateContentUpdates else { return nil }
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        // Keep the live glass actions outside the crossfade, including their shadows.
        let hasActions = firstItemFrame(inCustomSection: actionsCustomSectionID) != nil
        guard hasActions == !account.isView,
              let assetsFrame = firstItemFrame(inCustomSection: assetsCustomSectionID) else { return nil }
        var rect = collectionView.bounds
        let top = max(rect.minY, assetsFrame.minY)
        rect.size.height = max(0, rect.maxY - top)
        rect.origin.y = top
        guard !rect.isEmpty,
              let content = collectionView.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }

        let snapshot = UIView(frame: collectionView.convert(rect, to: view))
        snapshot.backgroundColor = view.backgroundColor
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.frame = snapshot.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.addSubview(content)
        view.addSubview(snapshot)
        accountSwitchSnapshotView = snapshot
        return snapshot
    }

    func finishAccountSwitchCrossfade(snapshot: UIView?) {
        guard let snapshot, accountSwitchSnapshotView === snapshot else { return }
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            snapshot.alpha = 0
        } completion: { [weak self] _ in
            snapshot.removeFromSuperview()
            if self?.accountSwitchSnapshotView === snapshot {
                self?.accountSwitchSnapshotView = nil
            }
        }
    }

    func cleanupAccountSwitchCrossfade(snapshot: UIView?) {
        guard let snapshot, accountSwitchSnapshotView === snapshot else { return }
        snapshot.removeFromSuperview()
        accountSwitchSnapshotView = nil
    }

    override var activeCustomSectionIDs: [String] {
        var ids = account.isView ? [] : [actionsCustomSectionID]
        ids.append(assetsCustomSectionID)
        return ids
    }
}

extension SplitHomeVC: HomeRootLayoutMigrating {
    var homeRootAccountSource: AccountSource {
        splitHomeAccountContext.source
    }

    func prepareForRootLayoutMigration() {
        removesTemporaryAccountOnDeinit = false
    }
}
