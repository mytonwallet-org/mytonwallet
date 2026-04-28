//
//  HomeVC.swift
//  UIHome
//
//  Created by Sina on 3/20/24.
//

import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext
import UIAssets
import UISettings
import Perception
import SwiftUI
import Dependencies

private let log = Log("HomeVC")
let homeBottomInset: CGFloat = 200

@MainActor
public class HomeVC: ActivityListViewController, WSensitiveDataProtocol, HomeVMDelegate, Sendable {

    let homeVM: HomeViewModel
    let headerViewModel: HomeHeaderViewModel
    
    private var calledReady = false

    var popRecognizer: InteractivePopRecognizer?
    /// `headerContainerView` is used to set colored background under safe area and also under tableView when scrolling down. (bounce mode)
    private var headerContainerView: WTouchPassView!
    /// `headerContainerViewHeightConstraint` is used to animate the header background on the first load's animation.
    private var headerContainerViewHeightConstraint: NSLayoutConstraint? = nil
    
    private let headerContainer: HomeHeaderContainer = HomeHeaderContainer()
    
    // navbar buttons
    private lazy var lockNavigationItem = WNavigationBarIconGroup.Item(
        title: lang("Lock"),
        image: .airBundle("HomeLock")
    ) { [weak self] in
        self?.lockPressed()
    }
    private lazy var hideNavigationItem = WNavigationBarIconGroup.Item(
        title: lang("Hide"),
        image: .airBundle(AppStorageHelper.isSensitiveDataHidden ? "HomeUnhide" : "HomeHide")
    ) { [weak self] in
        self?.hidePressed()
    }
    private lazy var scanNavigationItem = WNavigationBarIconGroup.Item(
        title: lang("Scan"),
        image: .airBundle("HomeScan")
    ) { [weak self] in
        self?.scanPressed()
    }

    /// The header containing balance and other actions like send/receive/scan/settings and balance in other currencies.
    private(set) lazy var balanceHeaderView = BalanceHeaderView(headerViewModel: headerViewModel,
                                                                accountSource: homeVM.$account.source,
                                                                delegate: self)
    private var headerBlurView: WBlurView!
    private let bottomSeparatorView = UIView()
    private let headerTouchTarget = UILabel()
    
    private var windowSafeAreaGuide = UILayoutGuide()
    private var windowSafeAreaGuideContraint: NSLayoutConstraint!

    private let actionsVC: ActionsVC
    private var actionsBottomConstraint: NSLayoutConstraint!
    private var walletAssetsVC: WalletAssetsVC!
    
    private var headerBottomConstraint: NSLayoutConstraint!
    private var headerGradientLeading = EdgeGradientView()
    private var headerGradientTrailing = EdgeGradientView()
    
    // Temporary set to true when user taps on wallet card icon to expand it!
    var isExpandingProgrammatically: Bool = false

    private var appearedOneTime = false
    private let multisigWalletWarningCustomSectionID = "multisig-wallet-warning"
    private let assetsCustomSectionID = "assets"
    private var multisigWalletWarningCustomSectionCellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, Row>!
    private var multisigWalletWarningCustomSectionDescriptor: CustomSectionDescriptor!
    private var assetsCustomSectionCellRegistration: UICollectionView.CellRegistration<HomeAssetsRowCell, Row>!
    private var assetsCustomSectionDescriptor: CustomSectionDescriptor!
    
    public init(accountSource: AccountSource = .current) {
        self.actionsVC = ActionsVC(accountSource: accountSource)
        homeVM = HomeViewModel(accountSource: accountSource)
        headerViewModel = HomeHeaderViewModel(accountSource: accountSource)
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        homeVM.delegate = self
    }

    public override var hideBottomBar: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    isolated deinit {
        if homeVM.isTrackingActiveAccount {
            let accountId = homeVM.account.id
            Task {
                try await AccountStore.removeAccountIfTemporary(accountId: accountId)
            }
        }
    }

    public override func loadView() {
        super.loadView()
        StartupTrace.markOnce("home.loadView", details: "layout=tab")

        setupViews()

        homeVM.initWalletInfo()
        StartupTrace.markOnce("home.initWalletInfo.begin", details: "layout=tab")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        StartupTrace.markOnce("home.viewDidLoad", details: "layout=tab")
        registerForOtherViewControllerAppearNotifications()
    }
    
    public override func otherViewControllerDidAppear(_ vc: UIViewController) {
        super.otherViewControllerDidAppear(vc)
        
        // We are interested only in other VCs, not in itself or its children
        // Any foreign VC is considered as an action/navigation and a signal to stop current reordering
        var topVC: UIViewController = vc
        while topVC != self, let parent = topVC.parent {
            topVC = parent
        }
        if topVC != self {
            walletAssetsVC.editingNavigator.cancelEditing()
        }
    }
    
    // MARK: - Setup home views
    func setupViews() {
        view.backgroundColor = .air.headerBackground

        headerTouchTarget.translatesAutoresizingMaskIntoConstraints = false
        headerTouchTarget.text = lang("Wallet")
        headerTouchTarget.textColor = .clear
        headerTouchTarget.isUserInteractionEnabled = true
        headerTouchTarget.accessibilityElementsHidden = true
        navigationItem.titleView = headerTouchTarget

        navigationController?.setNavigationBarHidden(false, animated: false)
        if !IOS_26_MODE_ENABLED {
            configureNavigationItemWithTransparentBackground()
        }
        
        view.addLayoutGuide(windowSafeAreaGuide)
        windowSafeAreaGuideContraint = windowSafeAreaGuide.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        windowSafeAreaGuideContraint.isActive = true
        
        super.setupTableViews(tableViewBottomConstraint: homeBottomInset)

        // header container view (used to make animating views on start, possible)
        headerContainerView = WTouchPassView()
        headerContainerView.accessibilityIdentifier = "headerContainerView"
        headerContainerView.shouldAcceptTouchesOutside = true
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainerView.layer.masksToBounds = true
        view.addSubview(headerContainerView)
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            headerContainerView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        // balance header view
        balanceHeaderView.alpha = 0
        headerContainerView.addSubview(balanceHeaderView)
        NSLayoutConstraint.activate([
            balanceHeaderView.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor),
            balanceHeaderView.leftAnchor.constraint(equalTo: view.leftAnchor),
            balanceHeaderView.rightAnchor.constraint(equalTo: view.rightAnchor),
            balanceHeaderView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor).withPriority(.defaultHigh)
        ])
        
        headerBlurView = WBlurView()
        headerContainerView.insertSubview(headerBlurView, at: 0)
        NSLayoutConstraint.activate([
            headerBlurView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerBlurView.topAnchor.constraint(equalTo: headerContainerView.topAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor, constant: BalanceHeaderView.minHeight)
        ])

        headerBlurView.alpha = 0

        bottomSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparatorView.isUserInteractionEnabled = false
        bottomSeparatorView.backgroundColor = UIColor { .air.separator.withAlphaComponent($0.userInterfaceStyle == .dark ? 0.8 : 0.2) }
        bottomSeparatorView.alpha = 0
        view.addSubview(bottomSeparatorView)
        NSLayoutConstraint.activate([
            bottomSeparatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            bottomSeparatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            bottomSeparatorView.heightAnchor.constraint(equalToConstant: 0.333),
            bottomSeparatorView.bottomAnchor.constraint(equalTo: headerBlurView.bottomAnchor),
        ])
        
        if IOS_26_MODE_ENABLED {
            headerBlurView.isHidden = true
            bottomSeparatorView.isHidden = true
        }
        
        navigationBarProgressiveBlurDelta = 16
        
        // activate swipe back for presenting views on navigation controller (with hidden navigation bar)
        setInteractiveRecognizer()

        addChild(actionsVC)
        let actionsContainerView = actionsVC.actionsContainerView
        let actionsView = actionsVC.actionsView
        let actionsHostView: UIView
        if #available(iOS 26, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = actionsView.spacing * 1.0 // merge effect intensity
            let glassContainerView = UIVisualEffectView(effect: effect)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            glassContainerView.contentView.addSubview(actionsContainerView)
            NSLayoutConstraint.activate([
                actionsContainerView.leadingAnchor.constraint(equalTo: glassContainerView.contentView.leadingAnchor),
                actionsContainerView.trailingAnchor.constraint(equalTo: glassContainerView.contentView.trailingAnchor),
                actionsContainerView.topAnchor.constraint(equalTo: glassContainerView.contentView.topAnchor),
                actionsContainerView.bottomAnchor.constraint(equalTo: glassContainerView.contentView.bottomAnchor),
            ])
            actionsHostView = glassContainerView
        } else {
            actionsHostView = actionsContainerView
        }
        collectionView.addSubview(actionsHostView)
        actionsBottomConstraint = actionsHostView.bottomAnchor.constraint(equalTo: collectionView.contentLayoutGuide.topAnchor, constant: headerPlaceholderHeight).withPriority(.init(950))
        NSLayoutConstraint.activate([
            actionsHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            actionsHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            actionsBottomConstraint,
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor,
                                             constant: 50).withPriority(.init(900)), // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)
        
        walletAssetsVC = WalletAssetsVC(accountSource: homeVM.$account.source)
        addChild(walletAssetsVC)
        walletAssetsVC.loadViewIfNeeded()
        walletAssetsVC.didMove(toParent: self)
        walletAssetsVC.editingNavigator.onStateChange = { [weak self] _, newState in
            guard let self else { return }
            if newState.editingState == .selection {
                walletAssetsVC.editingNavigator.installToolbar(into: view)
            }
            updateNavigationItem()
        }
        
        let spacing: CGFloat = IOS_26_MODE_ENABLED ? -124 : -100
        NSLayoutConstraint.activate([
            balanceHeaderView.updateStatusView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                constant: spacing)
        ])
        balanceHeaderView.updateStatusView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // fix gesture recognizer over BHV
        collectionView.superview?.addGestureRecognizer(collectionView.panGestureRecognizer)

        isInitializingCache = false
        applySnapshot(makeSnapshot(), animatingDifferences: false)
        updateSkeletonState()

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

//        headerContainer.alpha = 0.5
//        headerContainer.backgroundColor = .yellow
//        actionsHostView.backgroundColor = .green
        
        headerBottomConstraint = headerContainer.bottomAnchor.constraint(
            equalTo: actionsHostView.bottomAnchor,
            constant: 0
        ).withPriority(.defaultHigh)
        
        NSLayoutConstraint.activate([
            headerContainer.heightAnchor.constraint(equalToConstant: itemHeight),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            headerBottomConstraint,
            headerContainer.bottomAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
        ])
        
        let accountSelector = HomeAccountSelector(viewModel: headerViewModel)
        headerContainer.addSubview(accountSelector)
        accountSelector.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accountSelector.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            accountSelector.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            accountSelector.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            accountSelector.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
        ])

        headerGradientLeading.translatesAutoresizingMaskIntoConstraints = false
        headerGradientLeading.color = .air.groupedBackground.withAlphaComponent(0.6)
        headerGradientLeading.direction = .leading
        view.addSubview(headerGradientLeading)
        NSLayoutConstraint.activate([
            headerGradientLeading.leadingAnchor.constraint(equalTo: accountSelector.leadingAnchor),
            headerGradientLeading.widthAnchor.constraint(equalToConstant: horizontalPadding),
            headerGradientLeading.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientLeading.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])

        headerGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        headerGradientTrailing.color = .air.groupedBackground.withAlphaComponent(0.6)
        headerGradientTrailing.direction = .trailing
        view.addSubview(headerGradientTrailing)
        NSLayoutConstraint.activate([
            headerGradientTrailing.trailingAnchor.constraint(equalTo: accountSelector.trailingAnchor),
            headerGradientTrailing.widthAnchor.constraint(equalToConstant: horizontalPadding),
            headerGradientTrailing.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientTrailing.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])
        
        collectionView.contentInset.top = expansionInset
        collectionView.contentOffset.y = -expansionInset

        headerViewModel.onSelect = { [weak self] in
            guard let self else { return }
            interactivelySwitchAccountTo(accountId: $0)
        }
        
        walletAssetsVC.delegate = self
        
        updateNavigationItem()
    }
    
    func appearedForFirstTime() {
        Task {
            await changeAccountTo(accountId: homeVM.account.id, isNew: false)
        }
        
        balanceHeaderView.alpha = 0
        collectionView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.balanceHeaderView.alpha = 1
            self.collectionView.alpha = 1
        }
    }

    private func setInteractiveRecognizer() {
        guard let controller = navigationController else { return }
        popRecognizer = InteractivePopRecognizer(controller: controller)
        controller.interactivePopGestureRecognizer?.delegate = popRecognizer
    }

    public override func scrollToTop(animated: Bool) {
        if animated {
            collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
        } else {
            collectionView.layer.removeAllAnimations()
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        }
        scrollViewDidScroll(collectionView)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if appearedOneTime {
            return
        }
        appearedOneTime = true
        StartupTrace.markOnce("home.viewWillAppear.first", details: "layout=tab")
        appearedForFirstTime()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateSafeAreaInsets()
        UIView.performWithoutAnimation {
            walletAssetDidChangeHeight(animated: false)
            view.layoutIfNeeded()
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        StartupTrace.markOnce("home.visible", details: "layout=tab")
        StartupTrace.endInterval("startup.toHomeVisible", details: "layout=tab")
        if headerTouchTarget.gestureRecognizers?.nilIfEmpty == nil {
            let g = UITapGestureRecognizer(target: self, action: #selector(onHeaderTap))
            headerTouchTarget.addGestureRecognizer(g)
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    private func updateSafeAreaInsets() {
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 16 + homeBottomInset
        let navBarHeight = navigationController!.navigationBar.frame.height
        windowSafeAreaGuideContraint.constant = view.safeAreaInsets.top - navBarHeight
        balanceHeaderView.updateStatusViewContainerTopConstraint.constant = (navBarHeight - 44) / 2 - S.updateStatusViewTopAdjustment
        scrollViewDidScroll(collectionView)
    }

    func contentOffsetChanged() {
        // `tableView.contentInset` is not be applied until `scrollViewWillEndDragging` so inset is calculated here based on expansion state
        let topContentInset = (collectionView.adjustedContentInset.top - collectionView.contentInset.top) + (headerViewModel.state == .expanded ? expansionInset : 0.0)
        balanceHeaderView.updateHeight(scrollOffset: collectionView.contentOffset.y + topContentInset, isExpandingProgrammatically: isExpandingProgrammatically)
        updateHeaderBlur(y: collectionView.contentOffset.y + collectionView.contentInset.top)
        headerViewModel.scrollOffsetChanged(to: collectionView.contentOffset.y + (collectionView.adjustedContentInset.top - collectionView.contentInset.top))
    }

    func updateHeaderBlur(y: CGFloat) {
        let progress = calculateNavigationBarProgressiveBlurProgress(y)
        bottomSeparatorView.alpha = progress
        headerBlurView.alpha = progress
    }

    // MARK: - Variable height

    var bhvHeight: CGFloat {
        balanceHeaderView.calculatedHeight
    }
    var actionsHeight: CGFloat {
        actionsVC.calculatedHeight
    }
    var actionsHeightWithSpacer: CGFloat {
        let actionsHeight = self.actionsHeight
        return actionsHeight > 0 ? actionsHeight + 16 : 0
    }
    var assetsHeight: CGFloat {
        walletAssetsVC.computedHeight()
    }
    
    // MARK: Collection view placeholders
    
    public override var headerPlaceholderHeight: CGFloat {
        return max(0, bhvHeight + actionsHeightWithSpacer)
    }
    private var assetsCustomSectionHeight: CGFloat {
        return max(0, assetsHeight - sectionSpacing)
    }
    public override var customSections: [CustomSectionDescriptor] {
        [multisigWalletWarningCustomSectionDescriptor, assetsCustomSectionDescriptor]
    }
    private var displayedActivitiesAccountId: String {
        activityViewModel?.accountId ?? homeVM.account.id
    }
    private func customSectionIDs(for accountId: String) -> [String] {
        let account = AccountStore.get(accountId: accountId)
        var ids: [String] = []
        if account.byChain.values.contains(where: { $0.isMultisig == true }) {
            ids.append(multisigWalletWarningCustomSectionID)
        }
        ids.append(assetsCustomSectionID)
        return ids
    }
    public override var activeCustomSectionIDs: [String] {
        customSectionIDs(for: displayedActivitiesAccountId)
    }
    private func configureAssetsCustomSection(cell: HomeAssetsRowCell) {
        cell.configure(assetsView: walletAssetsVC.view, height: assetsCustomSectionHeight)
    }
    private func configureCustomSections() {
        multisigWalletWarningCustomSectionCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Row> { cell, _, _ in
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                MultisigWalletWarning()
            }
            .background {
                Color.clear
            }
            .margins(.all, 0)
        }
        multisigWalletWarningCustomSectionDescriptor = CustomSectionDescriptor(id: multisigWalletWarningCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: multisigWalletWarningCustomSectionCellRegistration, for: indexPath, item: .custom(multisigWalletWarningCustomSectionID))
        }
        assetsCustomSectionCellRegistration = UICollectionView.CellRegistration<HomeAssetsRowCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureAssetsCustomSection(cell: cell)
        }
        assetsCustomSectionDescriptor = CustomSectionDescriptor(id: assetsCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: assetsCustomSectionCellRegistration, for: indexPath, item: .custom(assetsCustomSectionID))
        }
    }
    private var appliedHeaderHeightWithoutAssets: CGFloat?
    private var appliedHeaderPlaceholderHeight: CGFloat?
    private var appliedAssetsCustomSectionHeight: CGFloat?

    public override var navigationBarProgressiveBlurMinY: CGFloat {
        get { bhvHeight + actionsHeightWithSpacer - 50 }
        set { _ = newValue }
    }

    private func updateHeaderBottomConstraint() {
        headerBottomConstraint?.constant = -actionsHeightWithSpacer
    }

    func updateTableViewHeaderFrame(animated: Bool = true) {
        if headerPlaceholderHeight != appliedHeaderPlaceholderHeight ||
            bhvHeight != appliedHeaderHeightWithoutAssets ||
            assetsCustomSectionHeight != appliedAssetsCustomSectionHeight {
            appliedHeaderPlaceholderHeight = headerPlaceholderHeight
            appliedHeaderHeightWithoutAssets = bhvHeight
            appliedAssetsCustomSectionHeight = assetsCustomSectionHeight
            let updates = { [self] in
                actionsBottomConstraint.constant = headerPlaceholderHeight
                updateHeaderBottomConstraint()
                if let cell = visibleCustomSectionCell(id: assetsCustomSectionID) as? HomeAssetsRowCell {
                    configureAssetsCustomSection(cell: cell)
                }
                reconfigureHeaderPlaceholder(animated: true)
            }
            if animated && skeletonState != .loading {
                UIView.animateAdaptive(duration: isExpandingProgrammatically == true ? 0.2 : 0.3) { [self] in
                    updates()
                    view.layoutIfNeeded()
                }
            } else {
                UIView.performWithoutAnimation {
                    updates()
                }
            }
        }
    }
    
    public func updateSensitiveData() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        let image = UIImage.airBundle(isHidden ? "HomeUnhide" : "HomeHide")
        hideNavigationItem.setImage(image)
        scrollViewDidScroll(collectionView)
    }

    public override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        if activityViewModel?.idsByDate != nil && !calledReady {
            calledReady = true
            StartupTrace.markOnce("home.dataReady", details: "layout=tab")
            StartupTrace.endInterval("startup.toHomeReady", details: "layout=tab")
            WalletContextManager.delegate?.walletIsReady(isReady: true)
        }
        super.applySnapshot(snapshot, animatingDifferences: animatingDifferences)
    }

    @objc func scanPressed() {
        Task {
            if let result = await AppActions.scanQR() {
                switch result {
                case .url(let url):
                    let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
                    if !deeplinkHandled {
                        AppActions.showError(error: BridgeCallError.customMessage(lang("This QR Code is not supported"), nil))
                    }
                    
                case .address(address: let addr, possibleChains: let chains):
                    AppActions.showSend(accountContext: actionsVC.$account, prefilledValues: .init(
                        address: addr,
                        token: chains.first?.nativeToken.slug
                    ))
                }
            }
        }
    }

    @objc func lockPressed() {
        AppActions.lockApp(animated: true)
    }

    @objc func hidePressed() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }
    
    public override func updateSkeletonViewMask() {
        var skeletonViews = [UIView]()
        for cell in collectionView.visibleCells {
            if let transactionCell = cell as? ActivityCell {
                skeletonViews.append(transactionCell.contentView)
            }
        }
        for view in collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
            if let headerCell = view as? ActivityDateCell, let skeletonView = headerCell.skeletonView {
                skeletonViews.append(skeletonView)
            }
        }
        for view in walletAssetsVC.skeletonViewCandidates {
            skeletonViews.append(view)
        }
        skeletonView.applyMask(with: skeletonViews)
    }

    @objc func onHeaderTap() {
        AppActions.showWalletSettings()
    }
    
    func updateNavigationItem() {
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        
        let navigator = walletAssetsVC.editingNavigator
        switch navigator.state.editingState {
        case .reordering:
            leadingItemGroups += navigator.cancelEditingBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
        case .selection:
            leadingItemGroups += navigator.selectAllBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
        case nil:
            if navigationController?.viewControllers.count == 1 {
                if let leadingItem = WNavigationBarIconGroup(items: [scanNavigationItem]).barButtonItem {
                    leadingItemGroups += leadingItem.asSingleItemGroup()
                }
            }
            let trailingItems = AuthSupport.accountsSupportAppLock
                ? [lockNavigationItem, hideNavigationItem]
                : [hideNavigationItem]
            if let trailingItem = WNavigationBarIconGroup(items: trailingItems).barButtonItem {
                trailingItemGroups += trailingItem.asSingleItemGroup()
            }
        }
        
       navigationItem.leadingItemGroups = leadingItemGroups
       navigationItem.trailingItemGroups = trailingItemGroups
    }

    // MARK: HomeVMDelegate
    func update(state: UpdateStatusView.State, animated: Bool) {
        DispatchQueue.main.async {
            self.balanceHeaderView.update(status: state, animatedWithDuration: animated ? 0.3 : nil)
        }
    }

    func changeAccountTo(accountId: String, isNew: Bool) async {
        if activityViewModel?.accountId != accountId {
            activityViewModel = await ActivityListViewModel(accountId: accountId, token: nil, customSectionIDs: customSectionIDs(for: accountId), delegate: self)
            transactionsUpdated(accountChanged: true, isUpdateEvent: false)
        }
        actionsVC.setAccountId(accountId: accountId, animated: true)
        if isNew {
            expandHeader()
        }
        scrollViewDidScroll(collectionView)

        updateNavigationItem()
    }
    
    private var activateAccountTask: Task<Void, any Error>?
    private var switchActivitiesTask: Task<Void, any Error>?
    
    func interactivelySwitchAccountTo(accountId: String) {
        
        guard homeVM.isTrackingActiveAccount else { return }
                
        walletAssetsVC.interactivelySwitchAccountTo(accountId: accountId)
        
        switchActivitiesTask?.cancel()
        switchActivitiesTask = Task {
            UIView.animate(withDuration: 0.30) { [self] in
                actionsVC.setAccountId(accountId: accountId, animated: true)
                walletAssetDidChangeHeight(animated: true)
                
                @Dependency(\.accountSettings) var _accountSettings
                let accountSettings = _accountSettings.for(accountId: accountId)
                changeThemeColors(to: accountSettings.accentColorIndex)
                UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
            }
            balanceHeaderView.updateStatusAccountContext.accountId = accountId

            let nextActivityViewModel = await ActivityListViewModel(accountId: accountId, token: nil, customSectionIDs: customSectionIDs(for: accountId), delegate: self)
            guard !Task.isCancelled else { return }
            activityViewModel = nextActivityViewModel
            transactionsUpdated(accountChanged: false, isUpdateEvent: false)

            try await Task.sleep(for: .seconds(0.45))
            try await AccountStore.activateAccount(accountId: accountId)
        }
    }
    
    func removeSelfFromStack() {
        if let navigationController {
            if navigationController.topViewController === self {
                navigationController.popViewController(animated: true)
            } else {
                navigationController.viewControllers = navigationController.viewControllers.filter { $0 !== self }
            }
        }
    }
}

extension HomeVC: ActivityListViewModelDelegate {
    public func activityViewModelChanged() {
        transactionsUpdated(accountChanged: false, isUpdateEvent: true)
    }
}

@MainActor
private final class HomeAssetsRowCell: FirstRowCell {
    private var assetsHeightConstraint: NSLayoutConstraint?
    private weak var hostedView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(assetsView: UIView, height: CGFloat) {
        if hostedView !== assetsView {
            hostedView?.removeFromSuperview()
            hostedView = assetsView
            assetsView.removeFromSuperview()
            assetsView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(assetsView)
            let heightConstraint = assetsView.heightAnchor.constraint(equalToConstant: height)
            assetsHeightConstraint = heightConstraint
            NSLayoutConstraint.activate([
                assetsView.topAnchor.constraint(equalTo: contentView.topAnchor),
                assetsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
                assetsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
                assetsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                heightConstraint,
            ])
        }
        assetsHeightConstraint?.constant = height
        self.height = height
    }
}

extension S {
    static var bhvTopAdjustment: CGFloat {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            6
        } else {
            0
        }
    }
    static var updateStatusViewTopAdjustment: CGFloat {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            3.33
        } else {
            0
        }
    }
}
