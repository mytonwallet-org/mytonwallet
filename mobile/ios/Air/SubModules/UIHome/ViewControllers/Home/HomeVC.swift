//
//  HomeVC.swift
//  UIHome
//
//  Created by Sina on 3/20/24.
//

import UIKit
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
public class HomeVC: ActivitiesTableViewController, WSensitiveDataProtocol, HomeVMDelegate {

    let homeVM: HomeViewModel
    let headerViewModel: HomeHeaderViewModel
    
    private var _activityViewModel: ActivityViewModel?
    public override var activityViewModel: ActivityViewModel? { self._activityViewModel }

    private var calledReady = false

    var popRecognizer: InteractivePopRecognizer?
    /// `headerContainerView` is used to set colored background under safe area and also under tableView when scrolling down. (bounce mode)
    private var headerContainerView: WTouchPassView!
    /// `headerContainerViewHeightConstraint` is used to animate the header background on the first load's animation.
    private var headerContainerViewHeightConstraint: NSLayoutConstraint? = nil
    
    private let headerContainer: HomeHeaderContainer = HomeHeaderContainer()
    
    // navbar buttons
    private lazy var lockItem: UIBarButtonItem = UIBarButtonItem(title: lang("Lock"), image: .airBundle("HomeLock24"), target: self, action: #selector(lockPressed))
    private lazy var hideItem: UIBarButtonItem = {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        let image = UIImage.airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
        return UIBarButtonItem(title: lang("Hide"), image: image, target: self, action: #selector(hidePressed))
    }()
    private lazy var scanItem: UIBarButtonItem = {
        UIBarButtonItem(title: lang("Scan"), image: .airBundle("HomeScan24"), target: self, action: #selector(scanPressed))
    }()
    private lazy var cancelItem = UIBarButtonItem.cancelTextButtonItem {[weak self] in self?.cancelReorderingIfNeeded() }
    private lazy var doneItem = UIBarButtonItem.doneButtonItem {[weak self] in self?.walletAssetsVC.stopReordering(isCanceled: false) }

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
    private var actionsTopConstraint: NSLayoutConstraint!
    private var walletAssetsVC: WalletAssetsVC!
    private var assetsHeightConstraint: NSLayoutConstraint!
    
    private var headerBottomConstraint: NSLayoutConstraint!
    private var headerGradientLeading = EdgeGradientView()
    private var headerGradientTrailing = EdgeGradientView()
    
    // Temporary set to true when user taps on wallet card icon to expand it!
    var isExpandingProgrammatically: Bool = false

    private var appearedOneTime = false
    
    public init(accountSource: AccountSource = .current) {
        self.actionsVC = ActionsVC(accountSource: accountSource)
        homeVM = HomeViewModel(accountSource: accountSource)
        headerViewModel = HomeHeaderViewModel(accountSource: accountSource)
        super.init(nibName: nil, bundle: nil)
        homeVM.delegate = self
    }

    public override var hideNavigationBar: Bool { false }
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

        setupViews()

        homeVM.initWalletInfo()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
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
            cancelReorderingIfNeeded()
        }
    }
    
    // MARK: - Setup home views
    func setupViews() {
        view.backgroundColor = WTheme.groupedItem

        headerTouchTarget.translatesAutoresizingMaskIntoConstraints = false
        headerTouchTarget.text = String(repeating: "A", count: 20)
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
        bottomSeparatorView.backgroundColor = UIColor { WTheme.separator.withAlphaComponent($0.userInterfaceStyle == .dark ? 0.8 : 0.2) }
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
        
        if #available(iOS 26, *) {
            skeletonTableView.topEdgeEffect.isHidden = true
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
        tableView.addSubview(actionsHostView)
        actionsTopConstraint = actionsHostView.topAnchor.constraint(equalTo: tableView.contentLayoutGuide.topAnchor, constant: headerHeightWithoutAssets).withPriority(.init(950))
        NSLayoutConstraint.activate([
            actionsHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            actionsHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            actionsTopConstraint,
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor,
                                             constant: 50).withPriority(.init(900)), // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)
        
        walletAssetsVC = WalletAssetsVC(accountSource: homeVM.$account.source)
        addChild(walletAssetsVC)
        let assetsView = walletAssetsVC.view!
        tableView.addSubview(assetsView)
        assetsHeightConstraint = assetsView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            assetsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalPadding),
            assetsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalPadding),
            assetsView.topAnchor.constraint(equalTo: actionsView.bottomAnchor, constant: sectionSpacing),
            assetsView.topAnchor.constraint(equalTo: balanceHeaderView.bottomAnchor, constant: sectionSpacing).withPriority(.init(949)),

            assetsHeightConstraint,
        ])
        walletAssetsVC.didMove(toParent: self)
        
        let spacing: CGFloat = IOS_26_MODE_ENABLED ? -124 : -100
        NSLayoutConstraint.activate([
            balanceHeaderView.updateStatusView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                constant: spacing)
        ])
        balanceHeaderView.updateStatusView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addBottomBarBlur()
        
        // fix gesture recognizer over BHV
        tableView.superview?.addGestureRecognizer(tableView.panGestureRecognizer)

        isInitializingCache = false
        applySnapshot(makeSnapshot(), animated: false)
        applySkeletonSnapshot(makeSkeletonSnapshot(), animated: false)
        updateSkeletonState()

        updateTheme()
        
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)
        
        headerBottomConstraint = headerContainer.bottomAnchor.constraint(equalTo: walletAssetsVC.view.topAnchor, constant: -sectionSpacing).withPriority(.defaultHigh)
        
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
        headerGradientLeading.color = WTheme.groupedBackground.withAlphaComponent(0.6)
        headerGradientLeading.direction = .leading
        view.addSubview(headerGradientLeading)
        NSLayoutConstraint.activate([
            headerGradientLeading.leadingAnchor.constraint(equalTo: accountSelector.leadingAnchor),
            headerGradientLeading.widthAnchor.constraint(equalToConstant: horizontalPadding),
            headerGradientLeading.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientLeading.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])

        headerGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        headerGradientTrailing.color = WTheme.groupedBackground.withAlphaComponent(0.6)
        headerGradientTrailing.direction = .trailing
        view.addSubview(headerGradientTrailing)
        NSLayoutConstraint.activate([
            headerGradientTrailing.trailingAnchor.constraint(equalTo: accountSelector.trailingAnchor),
            headerGradientTrailing.widthAnchor.constraint(equalToConstant: horizontalPadding),
            headerGradientTrailing.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientTrailing.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])
        
        tableView.contentInset.top = expansionInset
        skeletonTableView.contentInset.top = expansionInset
        tableView.contentOffset.y = -expansionInset
        skeletonTableView.contentOffset.y = -expansionInset

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
        tableView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.balanceHeaderView.alpha = 1
            self.tableView.alpha = 1
        }
    }

    private func setInteractiveRecognizer() {
        guard let controller = navigationController else { return }
        popRecognizer = InteractivePopRecognizer(controller: controller)
        controller.interactivePopGestureRecognizer?.delegate = popRecognizer
    }

    public override func scrollToTop(animated: Bool) {
        if animated {
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
        } else {
            tableView.layer.removeAllAnimations()
            tableView.contentOffset.y = -tableView.adjustedContentInset.top
        }
        scrollViewDidScroll(tableView)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if appearedOneTime {
            return
        }
        appearedOneTime = true
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
        tableView.contentInset.bottom = view.safeAreaInsets.bottom + 16 + homeBottomInset
        let navBarHeight = navigationController!.navigationBar.frame.height
        windowSafeAreaGuideContraint.constant = view.safeAreaInsets.top - navBarHeight
        balanceHeaderView.updateStatusViewContainerTopConstraint.constant = (navBarHeight - 44) / 2 - S.updateStatusViewTopAdjustment
        scrollViewDidScroll(tableView)
    }

    func contentOffsetChanged() {
        // `tableView.contentInset` is not be applied until `scrollViewWillEndDragging` so inset is calculated here based on expansion state
        let topContentInset = headerViewModel.state == .expanded ? expansionInset : 0
        balanceHeaderView.updateHeight(scrollOffset: tableView.contentOffset.y + topContentInset, isExpandingProgrammatically: isExpandingProgrammatically)
        updateHeaderBlur(y: tableView.contentOffset.y + tableView.contentInset.top)
        headerViewModel.scrollOffsetChanged(to: tableView.contentOffset.y)
    }

    func updateHeaderBlur(y: CGFloat) {
        let progress = calculateNavigationBarProgressiveBlurProgress(y)
        bottomSeparatorView.alpha = progress
        headerBlurView.alpha = progress
    }

    // MARK: - Variable height

    var bhvHeight: CGFloat {
        balanceHeaderView.calculatedHeight + S.bhvTopAdjustment
    }
    var actionsHeight: CGFloat {
        actionsVC.calculatedHeight
    }
    var assetsHeight: CGFloat {
        walletAssetsVC.computedHeight()
    }
    var headerHeight: CGFloat {
        return bhvHeight + actionsHeight + assetsHeight
    }
    var headerHeightWithoutAssets: CGFloat {
        return bhvHeight +
            (view.safeAreaInsets.top - (navigationController?.navigationBar.frame.height ?? 0)) - S.bhvTopAdjustment
    }
    public override var headerPlaceholderHeight: CGFloat {
        return max(0, headerHeight + 8) // TODO: where does this 8 come from?
    }
    private var appliedHeaderHeightWithoutAssets: CGFloat?
    private var appliedHeaderPlaceholderHeight: CGFloat?

    public override var navigationBarProgressiveBlurMinY: CGFloat {
        get { bhvHeight + actionsHeight - 50 }
        set { _ = newValue }
    }

    func updateTableViewHeaderFrame(animated: Bool = true) {
        if headerPlaceholderHeight != appliedHeaderPlaceholderHeight ||
            headerHeightWithoutAssets != appliedHeaderHeightWithoutAssets {
            appliedHeaderPlaceholderHeight = headerPlaceholderHeight
            appliedHeaderHeightWithoutAssets = headerHeightWithoutAssets
            let updates = { [self] in
                headerBottomConstraint.constant = actionsHeight > 0 ? -actionsRowHeight - (sectionSpacing * 2) : -sectionSpacing
                actionsTopConstraint.constant = headerHeightWithoutAssets + (actionsHeight > 0 ? 0 :  -(actionsRowHeight + sectionSpacing))
                assetsHeightConstraint.constant = max(0, assetsHeight - sectionSpacing)
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
    
    override public var isGeneralDataAvailable: Bool {
        homeVM.isGeneralDataAvailable
    }

    public override func updateTheme() {
        view.backgroundColor = WTheme.balanceHeaderView.background
        headerGradientLeading.color = WTheme.groupedBackground.withAlphaComponent(0.6)
        headerGradientTrailing.color = WTheme.groupedBackground.withAlphaComponent(0.6)
    }

    public func updateSensitiveData() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        hideItem.image = .airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
        scrollViewDidScroll(tableView)
    }

    public override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool, animatingDifferences: Bool? = nil) {
        if isGeneralDataAvailable && !calledReady {
            calledReady = true
            WalletContextManager.delegate?.walletIsReady(isReady: true)
        }
        super.applySnapshot(snapshot, animated: animated, animatingDifferences: animatingDifferences)
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
                    AppActions.showSend(prefilledValues: .init(
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
        for cell in skeletonTableView.visibleCells {
            if let transactionCell = cell as? ActivityCell {
                skeletonViews.append(transactionCell.contentView)
            }
        }
        for view in skeletonTableView.subviews {
            if let headerCell = view as? ActivityDateCell, let skeletonView = headerCell.skeletonView {
                skeletonViews.append(skeletonView)
            }
        }
        for cell in walletAssetsVC.skeletonViewCandidates {
            if let skeletonCell = cell as? ActivityCell {
                skeletonViews.append(skeletonCell.contentView)
            }
        }
        skeletonView.applyMask(with: skeletonViews)
    }

    @objc func onHeaderTap() {
        AppActions.showWalletSettings()
    }
    
    // MONITORING ////////////////////////////////////////////////////////////////////////////////////////////////////
    var lastTimestamp: CFTimeInterval?
    var displayLink: CADisplayLink?

    func startMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(frameTick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc func frameTick(link: CADisplayLink) {
        if let last = lastTimestamp {
            let delta = link.timestamp - last
            if delta > (1.0 / 120.0) * 1.1 {
                print("Frame drop! Δt = \(delta * 1000) ms")
            }
        }
        lastTimestamp = link.timestamp
    }
    
    func updateNavigationItem() {
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []

        if walletAssetsVC.isReordering {
            leadingItemGroups += cancelItem.asSingleItemGroup()
            trailingItemGroups += doneItem.asSingleItemGroup()
        } else {
            if navigationController?.viewControllers.count == 1 {
                leadingItemGroups += scanItem.asSingleItemGroup()
            }
            if AuthSupport.accountsSupportAppLock {
                trailingItemGroups += lockItem.asSingleItemGroup()
            }
            trailingItemGroups += hideItem.asSingleItemGroup()
        }
        
       navigationItem.leadingItemGroups = leadingItemGroups
       navigationItem.trailingItemGroups = trailingItemGroups
    }
    
    private func cancelReorderingIfNeeded() {
        walletAssetsVC.stopReordering(isCanceled: true)
    }
        
    // MARK: HomeVMDelegate
    func update(state: UpdateStatusView.State, animated: Bool) {
        DispatchQueue.main.async {
            self.balanceHeaderView.update(status: state, animatedWithDuration: animated ? 0.3 : nil)
        }
    }

    func changeAccountTo(accountId: String, isNew: Bool) async {
        _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, delegate: self)
        transactionsUpdated(accountChanged: true, isUpdateEvent: false)
        actionsVC.setAccountId(accountId: accountId, animated: true)
        if isNew {
            expandHeader()
        }
        scrollViewDidScroll(tableView)

        updateNavigationItem()
        
        animateTableViewOpacity(1)
    }
    
    private var activateAccountTask: Task<Void, any Error>?
    private var switchActivitiesTask: Task<Void, any Error>?
    
    func interactivelySwitchAccountTo(accountId: String) {
        
        guard homeVM.isTrackingActiveAccount else { return }
                
        walletAssetsVC.interactivelySwitchAccountTo(accountId: accountId)
        
        switchActivitiesTask?.cancel()
        switchActivitiesTask = Task {
            self.forceAnimation = true
            
            animateTableViewOpacity(0)
            
            try await Task.sleep(for: .seconds(0.03))
            
            UIView.animate(withDuration: 0.30) { [self] in
                actionsVC.setAccountId(accountId: accountId, animated: true)
                walletAssetDidChangeHeight(animated: true)
                
                @Dependency(\.accountSettings) var _accountSettings
                let accountSettings = _accountSettings.for(accountId: accountId)
                changeThemeColors(to: accountSettings.accentColorIndex)
                UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
            }
            balanceHeaderView.updateStatusView.$account.accountId = accountId
            balanceHeaderView.updateStatusView.setState(newState: balanceHeaderView.updateStatusView.state, animatedWithDuration: 0.2)

            try await Task.sleep(for: .seconds(0.12))
            
            _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, delegate: self)
            transactionsUpdated(accountChanged: false, isUpdateEvent: false)

            try await Task.sleep(for: .seconds(0.3))
            try await AccountStore.activateAccount(accountId: accountId)
            
            animateTableViewOpacity(1)
            
            self.forceAnimation = false
        }
    }
    
    func animateTableViewOpacity(_ alpha: CGFloat) {
        UIView.animate(withDuration: 0.25) { [self] in
            for (_, subview) in tableView.subviews.enumerated() {
                if let cell = subview as? ActivityDateCell {
                    cell.contentView.alpha = alpha
                }
            }
            for cell in tableView.visibleCells {
                if let cell = cell as? ActivityCell {
                    cell.contentView.alpha = alpha
                }
            }
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

extension HomeVC: ActivityViewModelDelegate {
    public func activityViewModelChanged() {
        transactionsUpdated(accountChanged: false, isUpdateEvent: true)
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
