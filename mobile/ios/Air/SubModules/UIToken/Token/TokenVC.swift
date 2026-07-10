//
//  TokenVC.swift
//
//  Created by Sina on 11/1/24.
//

import UIKit
import SwiftUI
import Perception
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

private let log = Log("TokenVC")

@MainActor
public class TokenVC: ActivityListViewController {

    private var tokenVM: TokenVM!

    @AccountContext private var account: MAccount
    private let token: ApiToken
    private let isInModal: Bool
    private var accountContext: AccountContext { $account }
    private var isLpToken: Bool { token.type == .lp_token }
    private var currentToken: ApiToken {
        TokenStore.getToken(slug: token.slug) ?? token
    }

    public init(accountSource: AccountSource, token: ApiToken, isInModal: Bool) async {
        self._account = AccountContext(source: accountSource)
        self.token = token
        self.isInModal = isInModal
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        let accountId = $account.accountId
        self.activityViewModel = await ActivityListViewModel(accountId: accountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
        tokenVM = TokenVM(accountId: accountId,
                                           selectedToken: token,
                                           tokenVMDelegate: self)
        WalletCoreData.add(eventObserver: self)
        tokenVM.refreshTransactions()
    }
    
    public override var hideBottomBar: Bool {
        false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let navigationHeader = NavigationHeader2()

    private lazy var expandableContentView = TokenExpandableContentView(accountContext: accountContext)
    
    private let actionsCustomSectionID = "actions"
    private var actionsCustomSectionCellRegistration: UICollectionView.CellRegistration<TokenActionsCell, Row>!
    private var actionsCustomSectionDescriptor: CustomSectionDescriptor!

    private let chartCustomSectionID = "chart"
    private var chartCustomSectionCellRegistration: UICollectionView.CellRegistration<TokenChartCell, Row>!
    private var chartCustomSectionDescriptor: CustomSectionDescriptor!

    private var suppressScrollUpdates = false

    private struct NavigationHeaderSnapshot: Equatable {
        var title: String
        var badgeLabel: String?
        var isRwaStock: Bool
    }

    private var navigationHeaderSnapshot: NavigationHeaderSnapshot?

    private func updateHeaderHeight() {
        suppressScrollUpdates = true
        defer { suppressScrollUpdates = false }

        let savedOffset = collectionView.contentOffset
        UIView.performWithoutAnimation {
            invalidateCustomSectionLayout(id: chartCustomSectionID)
            collectionView.layoutIfNeeded()
            if collectionView.contentOffset.y != savedOffset.y {
                collectionView.contentOffset = savedOffset
            }
        }
    }

    public override var headerPlaceholderHeight: CGFloat {
        expandableContentView.metrics.headerPlaceholderHeight
    }

    public override var customSections: [CustomSectionDescriptor] {
        if isLpToken {
            return [actionsCustomSectionDescriptor]
        }
        return [actionsCustomSectionDescriptor, chartCustomSectionDescriptor]
    }
    
    private func configureActionsCustomSection(cell: TokenActionsCell) {
        let token = currentToken
        cell.setup(accountContext: accountContext, token: token)
        cell.configure(
            token: token,
            sendAvailable: account.supportsSend,
            swapAvailable: account.supportsSwap && !isLpToken,
            earnAvailable: account.supportsEarn && token.earnAvailable
        )
    }
    private func configureChartCustomSection(cell: TokenChartCell) {
        let token = currentToken
        cell.setup(onHeightChange: { [weak self] in
            self?.updateHeaderHeight()
        })
        cell.configure(token: token,
                       historyData: tokenVM.historyData) { [weak self] period in
            guard let self else { return }
            tokenVM.selectedPeriod = period
        }
    }
    private func configureCustomSections() {
        actionsCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenActionsCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureActionsCustomSection(cell: cell)
        }
        actionsCustomSectionDescriptor = CustomSectionDescriptor(id: actionsCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: actionsCustomSectionCellRegistration, for: indexPath, item: .custom(actionsCustomSectionID))
        }

        chartCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenChartCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureChartCustomSection(cell: cell)
        }
        chartCustomSectionDescriptor = CustomSectionDescriptor(id: chartCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: chartCustomSectionCellRegistration, for: indexPath, item: .custom(chartCustomSectionID))
        }
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        updateNavigationHeader()

        navigationHeader.viewToRedirectTouchesTo = expandableContentView
        navigationHeader.onSizeChanged = { [weak self] in
            self?.updateScroll()
        }
        navigationHeader.onMovedToWindow = { [weak self] window in
            if window != nil {
                self?.updateScroll()
            }
        }
        navigationItem.titleView = navigationHeader
        
        updateNavigationMenu()
        navigationController?.setNavigationBarHidden(false, animated: false)

        super.setupCollectionView(collectionViewBottomConstraint: 0)
        
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            collectionView.topEdgeEffect.isHidden = true
        }
        
        UIView.performWithoutAnimation {
            applySnapshot(makeSnapshot(), animatingDifferences: false)
            updateSkeletonState()
        }

        view.backgroundColor = isInModal ? .air.sheetBackground : .air.groupedBackground
        addCustomNavigationBarBackground(color: view.backgroundColor)

        view.addSubview(expandableContentView)
        NSLayoutConstraint.activate([
            expandableContentView.topAnchor.constraint(equalTo: view.topAnchor),
            expandableContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandableContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        expandableContentView.configure(token: currentToken)
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateSafeAreaInsets()
        updateSkeletonViewMask()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    private func updateSafeAreaInsets() {
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 16
        
        if !IOS_26_MODE_ENABLED {
            scrollViewDidScroll(collectionView)
        }
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
        skeletonView.applyMask(with: skeletonViews)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        let automaticTopInset = scrollView.adjustedContentInset.top - scrollView.contentInset.top
        let safeBottom = view.safeAreaInsets.bottom
        let fullScrollRange = expandableContentView.metrics.fullScrollRange
        let requiredBottomInset = fullScrollRange
            - collectionView.contentSize.height
            + collectionView.frame.height
            - automaticTopInset
            - safeBottom
        collectionView.contentInset.bottom = max(safeBottom + 16, requiredBottomInset)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !suppressScrollUpdates else { return }
        updateScroll()
    }
    
    private func updateScroll() {
        let scrollOffset = scrollOffset(for: collectionView)

        if navigationHeader.window != nil {
            let navBarShift = navigationHeader.distanceFromNavigationBarBottomToContentCenter
            expandableContentView.update(scrollOffset: scrollOffset, navBarShift: navBarShift)
        }
        
        updateNavigationBarChrome(scrollOffset: scrollOffset)
        updateVisibleActivityNftAnimationPlayback()
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let automaticTopInset = scrollView.adjustedContentInset.top - scrollView.contentInset.top
        let realTargetY = targetContentOffset.pointee.y + automaticTopInset
        let metrics = expandableContentView.metrics
        let fullScrollRange = metrics.fullScrollRange
        let isScrollable = collectionView.contentSize.height
            + scrollView.adjustedContentInset.top
            + scrollView.adjustedContentInset.bottom > collectionView.frame.height
        if realTargetY > 0 && isScrollable {
            if realTargetY < fullScrollRange {
                var isGoingDown = targetContentOffset.pointee.y > scrollView.contentOffset.y
                if abs(velocity.y) < 5 {
                    isGoingDown = realTargetY < fullScrollRange * metrics.collapseThreshold
                }
                targetContentOffset.pointee.y = (isGoingDown ? 0 : metrics.adjustedFullScrollRange) - automaticTopInset
            }
        }
    }

    private func scrollOffset(for scrollView: UIScrollView) -> CGFloat {
        scrollView.contentOffset.y + scrollView.adjustedContentInset.top - scrollView.contentInset.top
    }

    private func updateNavigationBarChrome(scrollOffset: CGFloat) {
        if let cell = visibleCustomSectionCell(id: actionsCustomSectionID) as? TokenActionsCell {
            cell.reduceButtonHeightFor(expandableContentView.metrics.adjustedFullScrollRange - scrollOffset)
        }

        navigationHeader.visibilityAlpha = min(1, max(0, (30 - scrollOffset) / 14 + 1))
    }

    private func updateNavigationHeader() {
        let token = currentToken
        let badgeLabel = token.label?.nilIfEmpty
        let title = token.displayName(strippingLabelWhenShown: badgeLabel != nil)
        let snapshot = NavigationHeaderSnapshot(
            title: title,
            badgeLabel: badgeLabel,
            isRwaStock: token.isRwaStock
        )

        guard snapshot != navigationHeaderSnapshot else { return }
        navigationHeaderSnapshot = snapshot

        guard let badgeLabel else {
            navigationHeader.setTitle(title)
            return
        }

        let titleLabel = NavigationHeader2.makeTitleLabel(title)
        let badge = BadgeView(style: .large)
        badge.configureTokenLabel(text: badgeLabel, style: token.isRwaStock ? .stock : .regular)
        navigationHeader.setStack(of: [titleLabel, badge], spacing: 4)
    }

    private func updateNavigationMenu() {
        navigationItem.rightBarButtonItem = ConfigStore.shared.shouldRestrictSwapsAndOnRamp
            ? nil
            : UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMenu())
    }

    private func makeMenu() -> UIMenu {

        let openUrl: (URL) -> () = { url in
            AppActions.openInBrowser(url)
        }
        let token = self.token

        let openInExplorer = UIAction(title: lang("Open in Explorer"), image: UIImage(named: "SendGlobe", in: AirBundle, with: nil)) { _ in
            openUrl(ExplorerHelper.tokenUrl(token: token))
        }
        let explorerSection = UIMenu(options: .displayInline, children: [openInExplorer])

        let websiteActions = ExplorerHelper.websitesForToken(token).map { website in
            UIAction(title: website.title) { _ in
                openUrl(website.address)
            }
        }
        let websiteSection = UIMenu(options: .displayInline, children: websiteActions)

        return UIMenu(children: [explorerSection, websiteSection])
    }
}

extension TokenVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            updateNavigationMenu()
        case .tokensChanged:
            updateNavigationHeader()
        default:
            break
        }
    }
}

extension TokenVC: TokenVMDelegate {
    func dataUpdated(isUpdateEvent: Bool) {
        expandableContentView.configure(token: currentToken)
        updateNavigationHeader()
        reconfigureCustomSection(id: actionsCustomSectionID)
        reconfigureCustomSection(id: chartCustomSectionID)
        super.transactionsUpdated(accountChanged: false, isUpdateEvent: isUpdateEvent)
    }
    func priceDataUpdated() {
        expandableContentView.configure(token: currentToken)
        reconfigureCustomSection(id: chartCustomSectionID)
    }
    func stateChanged() {
        expandableContentView.configure(token: currentToken)
        updateNavigationHeader()
        reconfigureCustomSection(id: actionsCustomSectionID)
        reconfigureCustomSection(id: chartCustomSectionID)
    }
    func accountChanged() {
        guard accountContext.source == .current else { return }
        let newAccountId = accountContext.accountId
        Task {
            self.activityViewModel = await ActivityListViewModel(accountId: newAccountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
            self.tokenVM = TokenVM(accountId: newAccountId, selectedToken: token, tokenVMDelegate: self)
            self.tokenVM.refreshTransactions()
            self.updateNavigationHeader()
        }
    }
}

extension TokenVC: TabItemTappedProtocol {
    public func tabItemTapped() -> Bool {
        return false
    }
}


extension TokenVC: ActivityListViewModelDelegate {
    public func activityViewModelChanged() {
        super.transactionsUpdated(accountChanged: false, isUpdateEvent: false)
    }
}
