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

private let log = Log("HomeVC")
let homeBottomInset: CGFloat = 200

@MainActor
public class HomeVC: ActivitiesTableViewController, WSensitiveDataProtocol {

    // MARK: - View Model and UI Components
    lazy var homeVM = HomeVM(homeVMDelegate: self)

    var _activityViewModel: ActivityViewModel?
    public override var activityViewModel: ActivityViewModel? { self._activityViewModel }

    var calledReady = false

    var popRecognizer: InteractivePopRecognizer?
    /// `headerContainerView` is used to set colored background under safe area and also under tableView when scrolling down. (bounce mode)
    var headerContainerView: WTouchPassView!
    /// `headerContainerViewHeightConstraint` is used to animate the header background on the first load's animation.
    var headerContainerViewHeightConstraint: NSLayoutConstraint? = nil

    // navbar buttons
    lazy var lockItem: UIBarButtonItem = UIBarButtonItem(title: lang("Lock"), image: .airBundle("HomeLock24"), target: self, action: #selector(lockPressed))
    lazy var hideItem: UIBarButtonItem = {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        let image = UIImage.airBundle(isHidden ? "HomeUnhide24" : "HomeHide24")
        return UIBarButtonItem(title: lang("Hide"), image: image, target: self, action: #selector(hidePressed))
    }()

    /// The header containing balance and other actions like send/receive/scan/settings and balance in other currencies.
    var balanceHeaderVC: BalanceHeaderVC!
    var balanceHeaderView: BalanceHeaderView { balanceHeaderVC.balanceHeaderView }
    var headerBlurView: WBlurView!
    var bottomSeparatorView: UIView!

    var windowSafeAreaGuide = UILayoutGuide()
    var windowSafeAreaGuideContraint: NSLayoutConstraint!

    let actionsVC = ActionsVC()
    var actionsTopConstraint: NSLayoutConstraint!
    var walletAssetsVC = WalletAssetsVC()
    var assetsHeightConstraint: NSLayoutConstraint!

    // Temporary set to true when user taps on wallet card icon to expand it!
    var isExpandingProgrammatically: Bool = false
    var scrollExtraOffset = CGFloat(0)

    private var appearedOneTime = false

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    public override var hideNavigationBar: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        self.scrollViewDidScroll(tableView)
        updateSafeAreaInsets()
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

    func contentOffsetChanged(to y: CGFloat) {
        _ = balanceHeaderView.updateHeight(scrollOffset: y,
                                           isExpandingProgrammatically: isExpandingProgrammatically)
        updateHeaderBlur(y: y)
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
        return bhvHeight - scrollExtraOffset +
            (view.safeAreaInsets.top - (navigationController?.navigationBar.frame.height ?? 0)) - S.bhvTopAdjustment
    }
    public override var headerPlaceholderHeight: CGFloat {
        return max(0, headerHeight - scrollExtraOffset + 8) // TODO: where does this 8 come from?
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
//            log.info("updateTableViewHeaderFrame reconfiguring height: \(appliedHeaderPlaceholderHeight as Any, .public) -> \(headerPlaceholderHeight) animated=\(animated)")
//            log.info("headerPlaceholderHeight: \(headerHeight) - \(scrollExtraOffset) - \(tableView.contentInset.top) + 8")
//            log.info("headerHeight: \(bhvHeight) + \(actionsHeight) + \(assetsHeight)")
            appliedHeaderPlaceholderHeight = headerPlaceholderHeight
            appliedHeaderHeightWithoutAssets = headerHeightWithoutAssets
            let updates = { [self] in
                actionsTopConstraint.constant = headerHeightWithoutAssets + (actionsHeight > 0 ? 0 : -76)
                assetsHeightConstraint.constant = max(0, assetsHeight - 16)
                reconfigureHeaderPlaceholder()
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

    public override func updateSkeletonViewsIfNeeded(animateAlondside: ((Bool) -> ())?) {
        super.updateSkeletonViewsIfNeeded(animateAlondside: { isLoading in
            self.balanceHeaderVC.setLoading(isLoading)
        })
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
}

extension HomeVC: HomeVMDelegate {
    func update(state: UpdateStatusView.State, animated: Bool) {
        DispatchQueue.main.async {
            log.info("new state: \(state, .public) animted=\(animated)", fileOnly: true)
            self.balanceHeaderView.update(status: state, animatedWithDuration: animated ? 0.3 : nil)
        }
    }

    func updateBalance(balance: Double?, balance24h: Double?, walletTokens: [MTokenBalance]) {
            let assetsAnimated = balance != nil && skeletonState != .loading && !wasShowingSkeletons
            balanceHeaderView.update(balance: balance,
                                     balance24h: balance24h,
                                     animated: true,
                                     onCompletion: { [weak self] in
                guard let self else { return }
            })
    }

    func changeAccountTo(accountId: String, isNew: Bool) async {
        _activityViewModel = await ActivityViewModel(accountId: accountId, token: nil, delegate: self)
        transactionsUpdated(accountChanged: true, isUpdateEvent: false)
        emptyWalletView.hide(animated: false)
        balanceHeaderView.accountChanged()
        if isNew {
            expandHeader()
        }
        scrollViewDidScroll(tableView)

        let canLock = AuthSupport.accountsSupportAppLock
        navigationItem.trailingItemGroups = [
            UIBarButtonItemGroup(barButtonItems: canLock ? [lockItem, hideItem] : [hideItem], representativeItem: nil)
        ]
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
