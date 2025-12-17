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

    var homeVM: HomeViewModel!
    var headerViewModel: HomeHeaderViewModel!
    
    var _activityViewModel: ActivityViewModel?
    public override var activityViewModel: ActivityViewModel? { self._activityViewModel }

    var calledReady = false

    var popRecognizer: InteractivePopRecognizer?
    /// `headerContainerView` is used to set colored background under safe area and also under tableView when scrolling down. (bounce mode)
    var headerContainerView: WTouchPassView!
    /// `headerContainerViewHeightConstraint` is used to animate the header background on the first load's animation.
    var headerContainerViewHeightConstraint: NSLayoutConstraint? = nil
    
    var headerContainer: HomeHeaderContainer = HomeHeaderContainer()
    
    // navbar buttons
    lazy var lockItem: UIBarButtonItem = UIBarButtonItem(title: lang("Lock"), image: .airBundle("HomeLock24"), target: self, action: #selector(lockPressed))
    lazy var hideItem: UIBarButtonItem = {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        let image = UIImage.airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
        return UIBarButtonItem(title: lang("Hide"), image: image, target: self, action: #selector(hidePressed))
    }()

    /// The header containing balance and other actions like send/receive/scan/settings and balance in other currencies.
    var balanceHeaderView: BalanceHeaderView?
    var headerBlurView: WBlurView!
    var bottomSeparatorView: UIView!
    let headerTouchTarget = UILabel()
    
    var windowSafeAreaGuide = UILayoutGuide()
    var windowSafeAreaGuideContraint: NSLayoutConstraint!

    let actionsVC = ActionsVC()
    var actionsTopConstraint: NSLayoutConstraint!
    var walletAssetsVC: WalletAssetsVC!
    var assetsHeightConstraint: NSLayoutConstraint!
    
    var headerBottomConstraint: NSLayoutConstraint!
    var headerGradientLeading = GradientView()
    var headerGradientTrailing = GradientView()
    
    // Temporary set to true when user taps on wallet card icon to expand it!
    var isExpandingProgrammatically: Bool = false

    private var appearedOneTime = false
    
    public init(accountId: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.homeVM = HomeViewModel(accountId: accountId, delegate: self)
        self.headerViewModel = HomeHeaderViewModel(accountId: accountId)
    }

    public override var hideNavigationBar: Bool { false }
    public override var hideBottomBar: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    isolated deinit {
        if homeVM.isTrackingActiveAccount {
            let accountId = homeVM.accountViewModel.accountId
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

        //startMonitoring()
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
        
        if navigationController?.viewControllers.count == 1 {
            navigationItem.leadingItemGroups = [
                UIBarButtonItemGroup(
                    barButtonItems: [
                        UIBarButtonItem(title: lang("Scan"), image: .airBundle("HomeScan24"), target: self, action: #selector(scanPressed))
                    ],
                    representativeItem: nil
                )
            ]
        }
        navigationItem.trailingItemGroups = [
            UIBarButtonItemGroup(barButtonItems: [lockItem, hideItem], representativeItem: nil)
        ]
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
        let balanceHeaderView = BalanceHeaderView(headerViewModel: headerViewModel, accountId: homeVM.accountId, delegate: self)
        self.balanceHeaderView = balanceHeaderView
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

        bottomSeparatorView = UIView()
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
        tableView.addSubview(actionsContainerView)
        actionsTopConstraint = actionsContainerView.topAnchor.constraint(equalTo: tableView.contentLayoutGuide.topAnchor, constant: headerHeightWithoutAssets).withPriority(.init(950))
        NSLayoutConstraint.activate([
            actionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionsTopConstraint,
            
            actionsContainerView.heightAnchor.constraint(equalToConstant: actionsRowHeight),
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor,
                                             constant: 50).withPriority(.init(900)), // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)
        
        walletAssetsVC = WalletAssetsVC(accountSource: homeVM.accountSource, compactMode: true)
        addChild(walletAssetsVC)
        let assetsView = walletAssetsVC.view!
        tableView.addSubview(assetsView)
        assetsHeightConstraint = assetsView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            assetsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            assetsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            assetsView.topAnchor.constraint(equalTo: actionsView.bottomAnchor, constant: 16),
            assetsView.topAnchor.constraint(equalTo: balanceHeaderView.bottomAnchor, constant: 16).withPriority(.init(949)),

            assetsHeightConstraint,
        ])
        walletAssetsVC.didMove(toParent: self)
        
        let spacing: CGFloat = IOS_26_MODE_ENABLED ? -124 : -100
        NSLayoutConstraint.activate([
            balanceHeaderView.updateStatusView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                constant: spacing)
        ])
        balanceHeaderView.updateStatusView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // show `loading` or `wallet created` view if needed, based on situation
        emptyWalletView.set(state: .hidden, animated: false)

        addBottomBarBlur()
        
        // fix gesture recognizer over BHV
        tableView.superview?.addGestureRecognizer(tableView.panGestureRecognizer)

        NSLayoutConstraint.activate([
            emptyWalletView.topAnchor.constraint(equalTo: walletAssetsVC.view.bottomAnchor, constant: 8)
        ])
        
        isInitializingCache = false
        applySnapshot(makeSnapshot(), animated: false)
        applySkeletonSnapshot(makeSkeletonSnapshot(), animated: false)
        updateSkeletonState()

        updateTheme()
        
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)
        
        headerBottomConstraint = headerContainer.bottomAnchor.constraint(equalTo: walletAssetsVC.view.topAnchor, constant: -16).withPriority(.defaultHigh)
        
        NSLayoutConstraint.activate([
            headerContainer.heightAnchor.constraint(equalToConstant: itemHeight),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            headerBottomConstraint,
            headerContainer.bottomAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
//            headerContainer.bottomAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 200),
        ])
        
        let accountSelector = _AccountSelectorView(viewModel: headerViewModel, onIsScrolling: { _ in }, ns: nil)
        headerContainer.addSubview(accountSelector)
        accountSelector.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accountSelector.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            accountSelector.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            accountSelector.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            accountSelector.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
        ])

        headerGradientLeading.isUserInteractionEnabled = false
        headerGradientLeading.translatesAutoresizingMaskIntoConstraints = false
        headerGradientLeading.colors = [
            WTheme.groupedBackground.withAlphaComponent(0.6),
            WTheme.groupedBackground.withAlphaComponent(0),
        ]
        headerGradientLeading.gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        headerGradientLeading.gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        view.addSubview(headerGradientLeading)
        NSLayoutConstraint.activate([
            headerGradientLeading.leadingAnchor.constraint(equalTo: accountSelector.leadingAnchor),
            headerGradientLeading.widthAnchor.constraint(equalToConstant: 16),
            headerGradientLeading.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientLeading.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])

        headerGradientTrailing.isUserInteractionEnabled = false
        headerGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        headerGradientTrailing.colors = [
            WTheme.groupedBackground.withAlphaComponent(0.6),
            WTheme.groupedBackground.withAlphaComponent(0),
        ]
        headerGradientTrailing.gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
        headerGradientTrailing.gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
        view.addSubview(headerGradientTrailing)
        NSLayoutConstraint.activate([
            headerGradientTrailing.trailingAnchor.constraint(equalTo: accountSelector.trailingAnchor),
            headerGradientTrailing.widthAnchor.constraint(equalToConstant: 16),
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
    }
    
    func appearedForFirstTime() {
        Task {
            await changeAccountTo(accountId: homeVM.accountId, isNew: false)
        }
        
        emptyWalletView.alpha = 0
        balanceHeaderView?.alpha = 0
        tableView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.emptyWalletView.alpha = 1
            self.balanceHeaderView?.alpha = 1
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
            headerHeightChanged(animated: false)
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
        balanceHeaderView?.updateStatusViewContainerTopConstraint.constant = (navBarHeight - 44) / 2 - S.updateStatusViewTopAdjustment
        scrollViewDidScroll(tableView)
    }

    func contentOffsetChanged() {
        // `tableView.contentInset` is not be applied until `scrollViewWillEndDragging` so inset is calculated here based on expansion state
        let topContentInset = headerViewModel.state == .expanded ? expansionInset : 0
        balanceHeaderView?.updateHeight(scrollOffset: tableView.contentOffset.y + topContentInset, isExpandingProgrammatically: isExpandingProgrammatically)
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
        (balanceHeaderView?.calculatedHeight ?? 0) + S.bhvTopAdjustment
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
                headerBottomConstraint.constant = actionsHeight > 0 ? -actionsRowHeight - 32 : -16
                actionsTopConstraint.constant = headerHeightWithoutAssets + (actionsHeight > 0 ? 0 :  -(actionsRowHeight + 16))
                assetsHeightConstraint.constant = max(0, assetsHeight - 16)
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
        AppActions.scanQR()
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

    // MARK: HomeVMDelegate
    func update(state: UpdateStatusView.State, animated: Bool) {
        DispatchQueue.main.async {
            self.balanceHeaderView?.update(status: state, animatedWithDuration: animated ? 0.3 : nil)
        }
    }

    func changeAccountTo(accountId: String, isNew: Bool) async {
        _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, delegate: self)
        transactionsUpdated(accountChanged: true, isUpdateEvent: false)
        emptyWalletView.hide(animated: false)
        actionsVC.setAccountId(accountId: accountId, animated: true)
        if isNew {
            expandHeader()
        }
        scrollViewDidScroll(tableView)

        let canLock = AuthSupport.accountsSupportAppLock
        navigationItem.trailingItemGroups = [
            UIBarButtonItemGroup(barButtonItems: canLock ? [lockItem, hideItem] : [hideItem], representativeItem: nil)
        ]
    }
    
    private var activateAccountTask: Task<Void, any Error>?
    private var switchActivitiesTask: Task<Void, any Error>?
    
    func interactivelySwitchAccountTo(accountId: String) {
        
        guard homeVM.isTrackingActiveAccount else { return }
                
        walletAssetsVC.interactivelySwitchAccountTo(accountId: accountId)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            UIView.animate(withDuration: 0.30) { [self] in
                actionsVC.setAccountId(accountId: accountId, animated: true)
                headerHeightChanged(animated: true)
                
                @Dependency(\.accountSettings) var _accountSettings
                let accountSettings = _accountSettings.for(accountId: accountId)
                changeThemeColors(to: accountSettings.accentColorIndex)
                UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
            }
            if let balanceHeaderView {
                balanceHeaderView.updateStatusView.accountId = accountId
                balanceHeaderView.updateStatusView.setState(newState: balanceHeaderView.updateStatusView.state, animatedWithDuration: 0.2)
            }
        }
        
        switchActivitiesTask?.cancel()
        switchActivitiesTask = Task {
            
            self.forceAnimation = true
            
            UIView.animate(withDuration: 0.25) { [self] in
                for (_, subview) in tableView.subviews.enumerated() {
                    if let cell = subview as? ActivityDateCell {
                        cell.contentView.alpha = 0
                    }
                }
                for cell in tableView.visibleCells {
                    if let cell = cell as? ActivityCell {
                        cell.contentView.alpha = 0
                    }
                }
            }
            
            try await Task.sleep(for: .seconds(0.15))
            _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, delegate: self)
            transactionsUpdated(accountChanged: false, isUpdateEvent: false)

            try await Task.sleep(for: .seconds(0.008))
            
            try await Task.sleep(for: .seconds(0.3))
            try await AccountStore.activateAccount(accountId: accountId)
            
            self.forceAnimation = false
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
