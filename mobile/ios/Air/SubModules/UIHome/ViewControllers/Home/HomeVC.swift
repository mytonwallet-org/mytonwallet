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
import ContextMenuKit
import Perception
import SwiftUI
import Dependencies

let homeBottomInset: CGFloat = 200

@MainActor
public protocol HomeRootLayoutMigrating: AnyObject {
    var homeRootAccountSource: AccountSource { get }
    func prepareForRootLayoutMigration()
}

public enum HomeRootNavigationStyle: Sendable {
    case standard
    case topTabsNavigationBar
}

@MainActor
public class HomeVC: ActivityListViewController, WSensitiveDataProtocol, HomeVMDelegate, HomeRootLayoutMigrating, Sendable {

    let homeVM: HomeViewModel
    let headerViewModel: HomeHeaderViewModel
    let rootNavigationStyle: HomeRootNavigationStyle
    private var removesTemporaryAccountOnDeinit = true

    private var calledReady = false

    var popRecognizer: InteractivePopRecognizer?
    /// `headerContainerView` is used to set colored background under safe area and also under the collection view when scrolling down. (bounce mode)
    private var headerContainerView = WTouchPassView()

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
    private var headerBlurView: UIView?
    private var titleMenuInteraction: ContextMenuInteraction?
    private var windowSafeAreaGuide = UILayoutGuide()
    private var windowSafeAreaGuideContraint: NSLayoutConstraint?

    private let actionsVC: ActionsVC
    private weak var actionsHostView: UIView?
    private var actionsBottomConstraint: NSLayoutConstraint?
    private var walletAssetsVC: WalletAssetsVC?
    private weak var accountSelector: HomeAccountSelector?

    public var drawerOpeningGesturePriorityRegions: [DrawerOpeningGesturePriorityRegion] {
        var regions: [DrawerOpeningGesturePriorityRegion] = []
        if let accountSelector {
            regions.append(.init(view: accountSelector))
        }
        if let walletAssetsView = walletAssetsVC?.viewIfLoaded {
            regions.append(.init(
                view: walletAssetsView,
                contentInsets: UIEdgeInsets(
                    top: 0,
                    left: 2 * compactInsetSectionHorizontalPadding,
                    bottom: 0,
                    right: 2 * compactInsetSectionHorizontalPadding
                )
            ))
        }
        return regions
    }

    private var headerBottomConstraint: NSLayoutConstraint?
    private var headerContainerHeightConstraint: NSLayoutConstraint?
    private var headerGradientLeading = EdgeGradientView()
    private var headerGradientTrailing = EdgeGradientView()
    private var headerGradientLeadingWidthConstraint: NSLayoutConstraint?
    private var headerGradientTrailingWidthConstraint: NSLayoutConstraint?

    // Temporary set to true when user taps on wallet card icon to expand it!
    var isExpandingProgrammatically: Bool = false

    private var appearedOneTime = false
    private var hasCompletedInitialTopTabsAppearance = false
    private let multisigWalletWarningCustomSectionID = "multisig-wallet-warning"
    private let assetsCustomSectionID = "assets"
    private var multisigWalletWarningCustomSectionDescriptor: CustomSectionDescriptor?
    private var assetsCustomSectionDescriptor: CustomSectionDescriptor?

    public init(
        accountSource: AccountSource = .current,
        rootNavigationStyle: HomeRootNavigationStyle = .standard
    ) {
        self.actionsVC = ActionsVC(accountSource: accountSource)
        self.rootNavigationStyle = rootNavigationStyle
        homeVM = HomeViewModel(accountSource: accountSource)
        headerViewModel = HomeHeaderViewModel(
            accountSource: accountSource,
            rootNavigationStyle: rootNavigationStyle
        )
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        homeVM.delegate = self
    }

    public override var hideBottomBar: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        guard removesTemporaryAccountOnDeinit else { return }
        let accountId = homeVM.account.id
        Task {
            try? await AccountStore.removeAccountIfTemporary(accountId: accountId)
        }
    }

    public var homeRootAccountSource: AccountSource {
        homeVM.$account.source
    }

    public func prepareForRootLayoutMigration() {
        removesTemporaryAccountOnDeinit = false
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
            walletAssetsVC?.editingNavigator.cancelEditing()
        }
    }

    // MARK: - Setup home views
    
    private func setupViews() {
        view.backgroundColor = .air.headerBackground

        if rootNavigationStyle.usesNavigationBarTopTabs {
            navigationItem.titleView = nil
        } else {
            navigationItem.titleView = {
                let header = NavigationHeader2()
                let g = UITapGestureRecognizer(target: self, action: #selector(onHeaderTap(_:)))
                header.addGestureRecognizer(g)
                let titleMenuInteraction = ContextMenuInteraction(
                    triggers: [.longPress],
                    pressAnimation: .default(transformMode: .sublayerTransform),
                    activationViewProvider: { [weak self] _ in
                        self?.balanceHeaderView.updateStatusView
                    },
                    activationHitTestProvider: { [weak self] sourceView, point in
                        self?.isPointInUpdateStatusView(point, from: sourceView) ?? false
                    }
                ) { [weak self] _ in
                    self?.makeTitleMenuConfiguration()
                }
                titleMenuInteraction.attach(to: header)
                self.titleMenuInteraction = titleMenuInteraction
                return header
            }()
        }

        navigationController?.setNavigationBarHidden(false, animated: false)

        view.addLayoutGuide(windowSafeAreaGuide)
        let windowSafeAreaGuideContraint = windowSafeAreaGuide.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        self.windowSafeAreaGuideContraint = windowSafeAreaGuideContraint
        windowSafeAreaGuideContraint.isActive = true

        // Must be created before the collection view's data source, because the assets custom
        // section cell registration reads `walletAssetsVC.view` / `walletAssetsVC.computedHeight()`.
        // This keeps the first dequeue/layout pass consistent with the assets section.
        let walletAssetsVC = WalletAssetsVC(accountSource: homeVM.$account.source)
        self.walletAssetsVC = walletAssetsVC
        addChild(walletAssetsVC)
        walletAssetsVC.loadViewIfNeeded()
        walletAssetsVC.didMove(toParent: self)
        walletAssetsVC.editingNavigator.onStateChange = { [weak self] _, newState in
            guard let self else { return }
            if newState.editingState == .selection {
                self.walletAssetsVC?.editingNavigator.installToolbar(into: self.view)
            }
            self.updateNavigationItem()
        }

        super.setupCollectionView(collectionViewBottomConstraint: homeBottomInset)
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            collectionView.topEdgeEffect.isHidden = true
        }

        // header container view (used to make animating views on start, possible)
        headerContainerView.accessibilityIdentifier = "headerContainerView"
        headerContainerView.shouldAcceptTouchesOutside = true
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainerView.layer.masksToBounds = true
        view.addSubview(headerContainerView)
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // balance header view
        balanceHeaderView.alpha = 0
        headerContainerView.addSubview(balanceHeaderView)
        NSLayoutConstraint.activate([
            balanceHeaderView.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor),
            balanceHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            balanceHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            balanceHeaderView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor).withPriority(.defaultHigh)
        ])

        headerBlurView = addCustomNavigationBarBackground(color: .air.headerBackground)
        headerBlurView?.alpha = 0

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
        self.actionsHostView = actionsHostView
        actionsHostView.isHidden = rootNavigationStyle.usesTopTabs
        actionsHostView.isUserInteractionEnabled = rootNavigationStyle == .standard
        updateActionsHostViewTransform()
        let actionsBottomConstraint = actionsHostView.bottomAnchor.constraint(equalTo: collectionView.contentLayoutGuide.topAnchor, constant: headerPlaceholderHeight).withPriority(.init(950))
        self.actionsBottomConstraint = actionsBottomConstraint
        NSLayoutConstraint.activate([
            actionsHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: compactInsetSectionHorizontalPadding),
            actionsHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -compactInsetSectionHorizontalPadding),
            actionsBottomConstraint,
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor,
                                             constant: 50).withPriority(.init(900)), // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)

        let spacing: CGFloat = IOS_26_MODE_ENABLED ? -112 : -100
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

        let headerBottomConstraint = headerContainer.bottomAnchor.constraint(
            equalTo: actionsHostView.bottomAnchor,
            constant: 0
        ).withPriority(.defaultHigh)
        self.headerBottomConstraint = headerBottomConstraint
        let headerContainerHeightConstraint = headerContainer.heightAnchor.constraint(equalToConstant: HomeCardLayoutMetrics.screen.itemHeight)
        self.headerContainerHeightConstraint = headerContainerHeightConstraint

        NSLayoutConstraint.activate([
            headerContainerHeightConstraint,
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerBottomConstraint,
            rootNavigationStyle.usesNavigationBarTopTabs
                ? headerContainer.bottomAnchor.constraint(greaterThanOrEqualTo: view.topAnchor)
                : headerContainer.bottomAnchor.constraint(
                    greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor
                ),
        ])

        let accountSelector = HomeAccountSelector(viewModel: headerViewModel)
        self.accountSelector = accountSelector
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
        let leadingGradientWidthConstraint = headerGradientLeading.widthAnchor.constraint(equalToConstant: 0)
        headerGradientLeadingWidthConstraint = leadingGradientWidthConstraint
        NSLayoutConstraint.activate([
            headerGradientLeading.leadingAnchor.constraint(equalTo: accountSelector.leadingAnchor),
            leadingGradientWidthConstraint,
            headerGradientLeading.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientLeading.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])

        headerGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        headerGradientTrailing.color = .air.groupedBackground.withAlphaComponent(0.6)
        headerGradientTrailing.direction = .trailing
        view.addSubview(headerGradientTrailing)
        let trailingGradientWidthConstraint = headerGradientTrailing.widthAnchor.constraint(equalToConstant: 0)
        headerGradientTrailingWidthConstraint = trailingGradientWidthConstraint
        NSLayoutConstraint.activate([
            headerGradientTrailing.trailingAnchor.constraint(equalTo: accountSelector.trailingAnchor),
            trailingGradientWidthConstraint,
            headerGradientTrailing.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            headerGradientTrailing.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
        ])
        updateHeaderCardLayout()

        collectionView.contentInset.top = expansionInset
        collectionView.contentOffset.y = -expansionInset

        headerViewModel.onSelect = { [weak self] in
            guard let self else { return }
            interactivelySwitchAccountTo(accountId: $0)
        }

        walletAssetsVC.delegate = self

        updateNavigationItem()
    }

    private func appearedForFirstTime() {
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
        if rootNavigationStyle.usesTopTabs, !hasCompletedInitialTopTabsAppearance {
            updateSafeAreaInsets()
            hasCompletedInitialTopTabsAppearance = true
        }
        StartupTrace.markOnce("home.visible", details: "layout=tab")
        StartupTrace.endInterval("startup.toHomeVisible", details: "layout=tab")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateActionsHostViewTransform()
        updateHeaderCardLayout()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    private func updateSafeAreaInsets() {
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 16 + homeBottomInset
        guard let navigationController else { return }
        let navBarHeight = navigationController.navigationBar.frame.height
        windowSafeAreaGuideContraint?.constant = view.safeAreaInsets.top - navBarHeight
        let titleBarHeight = max(44, navBarHeight)
        balanceHeaderView.updateStatusViewContainerTopConstraint.constant = (titleBarHeight - 44) / 2 - S.updateStatusViewTopAdjustment
        if rootNavigationStyle.usesTopTabs, !hasCompletedInitialTopTabsAppearance {
            headerViewModel.state = .expanded
            collectionView.contentInset.top = expansionInset
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        }
        scrollViewDidScroll(collectionView)
    }

    private func updateActionsHostViewTransform() {
        // UICollectionView compensates its cells when its content is mirrored for RTL, but
        // Actions is a direct scrolling subview. Counter the inherited mirror at this Home-only
        // host boundary so the shared Actions toolbar keeps its normal RTL layout and rendering.
        let isRTL = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let transform = isRTL ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if actionsHostView?.transform != transform {
            actionsHostView?.transform = transform
        }
    }

    private func updateHeaderCardLayout() {
        let width = headerContainer.bounds.width > 0 ? headerContainer.bounds.width : view.bounds.width
        guard width > 0 else { return }
        let metrics = HomeCardLayoutMetrics.forContainerWidth(width)
        let metricsChanged = balanceHeaderView.cardLayoutMetrics != metrics
        balanceHeaderView.cardLayoutMetrics = metrics
        if headerContainerHeightConstraint?.constant != metrics.itemHeight {
            headerContainerHeightConstraint?.constant = metrics.itemHeight
        }
        let gradientWidth = metrics.inset
        if headerGradientLeadingWidthConstraint?.constant != gradientWidth {
            headerGradientLeadingWidthConstraint?.constant = gradientWidth
        }
        if headerGradientTrailingWidthConstraint?.constant != gradientWidth {
            headerGradientTrailingWidthConstraint?.constant = gradientWidth
        }
        if metricsChanged, view.window != nil {
            contentOffsetChanged()
            updateTableViewHeaderFrame(animated: false)
        }
    }

    func contentOffsetChanged() {
        // `contentInset` is not applied until `scrollViewWillEndDragging` so inset is calculated here based on expansion state
        let topContentInset = (collectionView.adjustedContentInset.top - collectionView.contentInset.top) + (headerViewModel.state == .expanded ? expansionInset : 0.0)
        balanceHeaderView.updateHeight(scrollOffset: collectionView.contentOffset.y + topContentInset, isExpandingProgrammatically: isExpandingProgrammatically)
        updateHeaderBlur()
        headerViewModel.scrollOffsetChanged(to: collectionView.contentOffset.y + (collectionView.adjustedContentInset.top - collectionView.contentInset.top))
    }

    private func updateHeaderBlur() {
        if rootNavigationStyle.usesNavigationBarTopTabs {
            headerBlurView?.alpha = 1
            return
        }
        var progress = 0.0
        if let walletAssetsVC {
            let waFrame = walletAssetsVC.view.convert(walletAssetsVC.view.bounds, to: view)
            let y = view.safeAreaInsets.top - waFrame.origin.y + navigationBarProgressiveBlurDelta
            progress = calculateNavigationBarProgressiveBlurProgress(y)
        }
        headerBlurView?.alpha = progress
    }

    // MARK: - Variable height

    var bhvHeight: CGFloat {
        balanceHeaderView.calculatedHeight
    }
    var actionsHeight: CGFloat {
        rootNavigationStyle == .standard ? actionsVC.calculatedHeight : 0
    }
    var actionsHeightWithSpacer: CGFloat {
        let actionsHeight = self.actionsHeight
        return actionsHeight > 0 ? actionsHeight + 16 : 0
    }
    var assetsHeight: CGFloat {
        walletAssetsVC?.computedHeight() ?? 0
    }

    // MARK: Collection view placeholders

    public override var headerPlaceholderHeight: CGFloat {
        return max(0, bhvHeight + actionsHeightWithSpacer)
    }
    private var assetsCustomSectionHeight: CGFloat {
        return max(0, assetsHeight - sectionSpacing)
    }
    public override var customSections: [CustomSectionDescriptor] {
        [multisigWalletWarningCustomSectionDescriptor, assetsCustomSectionDescriptor].compactMap { $0 }
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
        guard let walletAssetsVC else { return }
        cell.configure(assetsView: walletAssetsVC.view, height: assetsCustomSectionHeight)
    }
    private func configureCustomSections() {
        let multisigWalletWarningCustomSectionCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Row> { cell, _, _ in
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
        let assetsCustomSectionCellRegistration = UICollectionView.CellRegistration<HomeAssetsRowCell, Row> { [unowned self] cell, _, _ in
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
                actionsBottomConstraint?.constant = headerPlaceholderHeight
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

    @objc private func scanPressed() {
        AppActions.scanAndHandleQR(accountContext: actionsVC.$account)
    }

    @objc private func settingsPressed() {
        AppActions.showSettings(section: nil)
    }

    @objc private func lockPressed() {
        AppActions.lockApp(animated: true)
    }

    @objc private func hidePressed() {
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
        for view in walletAssetsVC?.skeletonViewCandidates ?? [] {
            skeletonViews.append(view)
        }
        skeletonView.applyMask(with: skeletonViews)
    }

    @objc private func onHeaderTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard let sourceView = recognizer.view else { return }

        if isPointInUpdateStatusView(recognizer.location(in: sourceView), from: sourceView) {
            AppActions.showWalletSettings()
        }
    }

    private func isPointInUpdateStatusView(_ point: CGPoint, from sourceView: UIView) -> Bool {
        guard let targetView = balanceHeaderView.updateStatusView else { return false }
        let ptAtTarget = sourceView.convert(point, to: targetView)
        return targetView.bounds.insetBy(dx: -10, dy: -10).contains(ptAtTarget)
    }

    private func makeTitleMenuConfiguration() -> ContextMenuConfiguration {
        WalletNameContextMenu.makeConfiguration(accountId: { [homeVM] in
            homeVM.account.id
        })
    }

    private func updateNavigationItem() {
        guard let navigator = walletAssetsVC?.editingNavigator else { return }
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []

        switch navigator.state.editingState {
        case .reordering:
            leadingItemGroups += navigator.cancelEditingBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
        case .selection:
            leadingItemGroups += navigator.selectAllBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.cancelXEditingBarButtonItem.asSingleItemGroup()
        case nil:
            if navigationController?.viewControllers.count == 1 {
                switch rootNavigationStyle {
                case .standard:
                    if let leadingItem = WNavigationBarIconGroup(items: [scanNavigationItem]).barButtonItem {
                        leadingItemGroups += leadingItem.asSingleItemGroup()
                    }
                case .topTabsNavigationBar:
                    break
                }
            }
            if rootNavigationStyle != .topTabsNavigationBar {
                let trailingItems = AuthSupport.accountsSupportAppLock
                    ? [lockNavigationItem, hideNavigationItem]
                    : [hideNavigationItem]
                if let trailingItem = WNavigationBarIconGroup(items: trailingItems).barButtonItem {
                    trailingItemGroups += trailingItem.asSingleItemGroup()
                }
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

    private var switchActivitiesTask: Task<Void, any Error>?

    func interactivelySwitchAccountTo(accountId: String) {

        guard homeVM.isTrackingActiveAccount else { return }

        walletAssetsVC?.interactivelySwitchAccountTo(accountId: accountId)

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
                assetsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: compactInsetSectionHorizontalPadding),
                assetsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -compactInsetSectionHorizontalPadding),
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
