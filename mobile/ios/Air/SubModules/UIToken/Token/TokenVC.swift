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

@MainActor
public class TokenVC: ActivityListViewController, SharedBottomToolbarContentProviding {

    private enum SharedToolbarActionID {
        static let buy = "token.buy"
        static let sell = "token.sell"
        static let receive = "token.receive"
    }

    @MainActor
    private enum TradeActionsLayout {
        static var buttonHeight: CGFloat {
            WButton.height(for: .primary)
        }
        static let buttonSpacing: CGFloat = 12
        static let bottomSpacing: CGFloat = 10
        static let horizontalMargin: CGFloat = 36
        static let maxWidth: CGFloat = 500
    }

    private lazy var tokenVM = TokenVM(
        accountId: $account.accountId,
        selectedToken: token,
        tokenVMDelegate: self
    )

    @AccountContext private var account: MAccount
    private let token: ApiToken
    private let isInModal: Bool
    private var accountContext: AccountContext { $account }
    private var isLpToken: Bool { token.type == .lp_token }
    private var currentToken: ApiToken {
        TokenStore.getToken(slug: token.slug) ?? token
    }
    private var areTradeActionsAvailable: Bool {
        account.supportsSwap && !isLpToken
    }
    private var hasSellableBalance: Bool {
        ($account.balances[token.slug] ?? 0) > 0
    }
    private lazy var hasBalance = hasSellableBalance
    private var canReceiveToken: Bool {
        account.supportsReceive && account.supports(chain: currentToken.chain)
    }
    private var isSharedBottomToolbarHosted = false
    private var tradeActionsBottomConstraint: NSLayoutConstraint?
    private let registeredRangeInteractionBlockers = NSHashTable<UIGestureRecognizer>.weakObjects()

    public var onSharedBottomToolbarActionsChange: (() -> Void)?

    public var sharedBottomToolbarSearchAccessibilityIdentifier: String? { "token_search_input" }

    public var sharedBottomToolbarActions: [SharedBottomToolbarAction] {
        var actions: [SharedBottomToolbarAction] = []
        if !hasBalance && canReceiveToken {
            actions.append(SharedBottomToolbarAction(
                id: SharedToolbarActionID.receive,
                title: lang("Receive"),
                accessibilityIdentifier: "token_receive",
                style: .neutral
            ))
        }
        if areTradeActionsAvailable {
            actions.append(SharedBottomToolbarAction(
                id: SharedToolbarActionID.buy,
                title: lang("Buy"),
                accessibilityIdentifier: "token_buy",
                style: .positive
            ))
        }
        if hasBalance && areTradeActionsAvailable {
            actions.append(SharedBottomToolbarAction(
                id: SharedToolbarActionID.sell,
                title: lang("Sell"),
                accessibilityIdentifier: "token_sell",
                style: .negative
            ))
        }
        return actions
    }

    public init(accountSource: AccountSource, token: ApiToken, isInModal: Bool) async {
        self._account = AccountContext(source: accountSource)
        self.token = token
        self.isInModal = isInModal
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        let accountId = $account.accountId
        self.activityViewModel = await ActivityListViewModel(accountId: accountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
        WalletCoreData.add(eventObserver: self)
    }

    public override var hideBottomBar: Bool {
        false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let navigationHeader = NavigationHeader2()

    private lazy var buyButton: WButton = {
        let button = WButton(style: .primary)
        button.customTintColor = .air.positiveAmount
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(lang("Buy"), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.presentTokenTrade(isBuying: true)
        }, for: .touchUpInside)
        return button
    }()

    private lazy var sellButton: WButton = {
        let button = WButton(style: .primary)
        button.customTintColor = .air.negativeAmount
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(lang("Sell"), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.performSharedBottomToolbarAction(id: SharedToolbarActionID.sell)
        }, for: .touchUpInside)
        return button
    }()

    private lazy var receiveButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration: UIButton.Configuration
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = .air.secondaryFill
            configuration.background.cornerRadius = 12
            configuration.cornerStyle = .fixed
        }
        configuration.baseForegroundColor = .label
        let font = WButton.capsuleFont
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }
        button.configuration = configuration
        button.setTitle(lang("Receive"), for: .normal)
        button.accessibilityIdentifier = "token_receive"
        button.addAction(UIAction { [weak self] _ in
            self?.performSharedBottomToolbarAction(id: SharedToolbarActionID.receive)
        }, for: .touchUpInside)
        return button
    }()

    private lazy var tradeActionsHostView = WActionButtonBar(
        buttons: [receiveButton, buyButton, sellButton],
        spacing: TradeActionsLayout.buttonSpacing
    )

    private lazy var expandableContentView = TokenExpandableContentView(accountContext: accountContext)

    private let actionsCustomSectionID = "actions"
    private var actionsCustomSectionDescriptor: CustomSectionDescriptor?

    private let chartCustomSectionID = "chart"
    private var chartCustomSectionDescriptor: CustomSectionDescriptor?

    private let infoCustomSectionID = "info"
    private lazy var tokenInfoModel = TokenInfoModel(state: tokenVM.tokenInfoState, hasBalance: hasBalance)
    private var infoCustomSectionDescriptor: CustomSectionDescriptor?

    private var suppressScrollUpdates = false
    private var infoTransitionScrollAnchor: CGPoint?

    private struct NavigationHeaderSnapshot: Equatable {
        var title: String
        var badgeLabel: String?
        var isRwaStock: Bool
    }

    private var navigationHeaderSnapshot: NavigationHeaderSnapshot?
    private struct NavigationMenuSnapshot: Equatable {
        var links: [ApiTokenDetails.Link]?
        var explorerURL: URL?
        var isRestricted: Bool
    }
    private var navigationMenuSnapshot: NavigationMenuSnapshot?
    private var activitySnapshot: NSDiffableDataSourceSnapshot<Section, Row>?
    private var minimumBottomContentInsetSnapshot: CGFloat?

    private struct ActionsSnapshot: Equatable {
        var accountId: String
        var canReceive: Bool
        var canSend: Bool
        var canTrade: Bool
        var canEarn: Bool
    }

    private var actionsSnapshot: ActionsSnapshot?
    private var tradeActionsSnapshot: [SharedBottomToolbarAction]?

    private var currentActionsSnapshot: ActionsSnapshot {
        ActionsSnapshot(
            accountId: accountContext.accountId,
            canReceive: account.supportsReceive,
            canSend: account.supportsSend,
            canTrade: areTradeActionsAvailable,
            canEarn: accountContext.isEarnAvailable(forTokenSlug: token.slug)
        )
    }

    private func updateActionsCustomSection() {
        let snapshot = currentActionsSnapshot
        guard snapshot != actionsSnapshot else { return }
        actionsSnapshot = snapshot
        reconfigureCustomSection(id: actionsCustomSectionID)
    }

    private func updateChartCustomSection() {
        if let cell = visibleCustomSectionCell(id: chartCustomSectionID) as? TokenChartCell {
            configureChartCustomSection(cell: cell)
        }
    }

    private func updateActivities(animated: Bool) {
        guard isViewLoaded else { return }
        let snapshot = makeSnapshot(reconfiguringCustomSections: [])
        let hasChanges = activitySnapshot.map { previous in
            previous.sectionIdentifiers != snapshot.sectionIdentifiers
                || snapshot.sectionIdentifiers.contains {
                    previous.itemIdentifiers(inSection: $0) != snapshot.itemIdentifiers(inSection: $0)
                }
                || !snapshot.reconfiguredItemIdentifiers.isEmpty
        } ?? true
        activitySnapshot = snapshot
        if hasChanges {
            applySnapshot(snapshot, animatingDifferences: animated)
        }
        updateSkeletonState()
    }

    private func updateCustomSectionHeight(id: String) {
        suppressScrollUpdates = true
        defer {
            suppressScrollUpdates = false
            updateNavigationBarChrome(scrollOffset: scrollOffset(for: collectionView))
        }

        let savedOffset = if id == infoCustomSectionID, let infoTransitionScrollAnchor {
            infoTransitionScrollAnchor
        } else {
            collectionView.contentOffset
        }
        UIView.performWithoutAnimation {
            self.invalidateCustomSectionLayout(id: id)
            self.collectionView.layoutIfNeeded()
            var offset = savedOffset
            let maximumOffset = max(-self.collectionView.adjustedContentInset.top,
                                    self.collectionView.contentSize.height + self.collectionView.adjustedContentInset.bottom - self.collectionView.bounds.height)
            offset.y = min(offset.y, maximumOffset)
            if self.infoTransitionScrollAnchor != nil {
                self.infoTransitionScrollAnchor = offset
            }
            if self.collectionView.contentOffset.y != offset.y {
                self.collectionView.contentOffset = offset
            }
        }
    }

    private func setInfoTransitionActive(_ isActive: Bool) {
        if isActive {
            infoTransitionScrollAnchor = infoTransitionScrollAnchor ?? collectionView.contentOffset
        } else {
            infoTransitionScrollAnchor = nil
            updateScroll()
        }
    }

    public override var headerPlaceholderHeight: CGFloat {
        hasBalance ? expandableContentView.metrics.headerPlaceholderHeight : 8
    }

    public override var headerPlaceholderBottomSpacing: CGFloat { hasBalance ? 16 : 0 }
    public override var displaysActivitySections: Bool {
        hasBalance || activityViewModel?.snapshot?.itemIdentifiers.contains {
            if case .transaction = $0.value { return true }
            return false
        } == true
    }
    public override var displaysActivityPlaceholders: Bool { hasBalance }
    public override var usesBackgroundSnapshotDiffing: Bool { false }
    public override var isActivityDataAvailableForSkeleton: Bool {
        !hasBalance || super.isActivityDataAvailableForSkeleton
    }
    public override var isActivityHistoryEndReachedForSkeleton: Bool {
        !hasBalance || super.isActivityHistoryEndReachedForSkeleton
    }

    public override var customSections: [any CustomSectionDataProvider] {
        if isLpToken {
            return [actionsCustomSectionDescriptor, infoCustomSectionDescriptor].compactMap { $0 }
        }
        return [actionsCustomSectionDescriptor, chartCustomSectionDescriptor, infoCustomSectionDescriptor].compactMap { $0 }
    }

    public override var activeCustomSectionIDs: [String] {
        (hasBalance ? [actionsCustomSectionID] : [])
            + (isLpToken ? [] : [chartCustomSectionID])
            + [infoCustomSectionID]
    }

    private func configureActionsCustomSection(cell: TokenActionsCell) {
        let token = currentToken
        actionsSnapshot = currentActionsSnapshot
        cell.setup(accountContext: accountContext, token: token)
        cell.configure(
            token: token,
            sendAvailable: account.supportsSend,
            swapAvailable: areTradeActionsAvailable,
            earnAvailable: accountContext.isEarnAvailable(forTokenSlug: token.slug)
        )
    }
    private func configureChartCustomSection(cell: TokenChartCell) {
        let token = currentToken
        cell.setup(onHeightChange: { [weak self] in
            guard let self else { return }
            updateCustomSectionHeight(id: chartCustomSectionID)
        })
        registerRangeGestureDependencies(for: cell)
        cell.configure(
            token: token,
            showsTokenIcon: !hasBalance,
            historyData: tokenVM.historyData,
            isHistoryRestored: tokenVM.isHistoryRestored,
            historyLoadingState: tokenVM.historyLoadingState,
            onPeriodChange: { [weak self] period in
                guard let self else { return }
                tokenVM.selectedPeriod = period
            },
            onAnalyze: nil
        )
    }

    private func registerRangeGestureDependencies(for cell: TokenChartCell) {
        guard let navigationController,
              let blocker = cell.rangeInteractionBlockingGestureRecognizer,
              !registeredRangeInteractionBlockers.contains(blocker) else { return }

        registeredRangeInteractionBlockers.add(blocker)
        collectionView.panGestureRecognizer.require(toFail: blocker)
        navigationController.interactivePopGestureRecognizer?.require(toFail: blocker)
        if #available(iOS 26.0, *) {
            navigationController.interactiveContentPopGestureRecognizer?.require(toFail: blocker)
        }
        (navigationController as? WNavigationController)?.fullWidthBackGestureRecognizerRequireToFail(blocker)
    }

    private func configureInfoCustomSection(cell: TokenInfoCell) {
        tokenInfoModel.configure(state: tokenVM.tokenInfoState, hasBalance: hasBalance)
        cell.configure(
            model: tokenInfoModel,
            onHeightChange: { [weak self] in
                guard let self else { return }
                updateCustomSectionHeight(id: infoCustomSectionID)
            },
            onUserToggleAnimationChange: { [weak self] isActive in
                self?.setInfoTransitionActive(isActive)
            }
        )
    }
    private func configureCustomSections() {
        let actionsCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenActionsCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureActionsCustomSection(cell: cell)
        }
        actionsCustomSectionDescriptor = CustomSectionDescriptor(id: actionsCustomSectionID, usesInsetGroupedMargins: true) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: actionsCustomSectionCellRegistration, for: indexPath, item: .custom(actionsCustomSectionID))
        }

        let chartCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenChartCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureChartCustomSection(cell: cell)
        }
        chartCustomSectionDescriptor = CustomSectionDescriptor(id: chartCustomSectionID, usesInsetGroupedMargins: true) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: chartCustomSectionCellRegistration, for: indexPath, item: .custom(chartCustomSectionID))
        }

        let infoCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenInfoCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureInfoCustomSection(cell: cell)
        }
        infoCustomSectionDescriptor = CustomSectionDescriptor(id: infoCustomSectionID, usesInsetGroupedMargins: true) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: infoCustomSectionCellRegistration, for: indexPath, item: .custom(infoCustomSectionID))
        }
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        hasBalance = hasSellableBalance
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
            updateActivities(animated: false)
        }

        view.backgroundColor = isInModal ? .air.sheetBackground : .air.groupedBackground
        addCustomNavigationBarBackground(color: view.backgroundColor)

        view.addSubview(expandableContentView)
        view.addSubview(tradeActionsHostView)

        let preferredWidthConstraint = tradeActionsHostView.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -2 * TradeActionsLayout.horizontalMargin
        )
        preferredWidthConstraint.priority = .defaultHigh

        let maxWidthConstraint = tradeActionsHostView.widthAnchor.constraint(
            equalToConstant: TradeActionsLayout.maxWidth
        )
        maxWidthConstraint.priority = .defaultLow
        let bottomConstraint = tradeActionsHostView.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -TradeActionsLayout.bottomSpacing
        )
        tradeActionsBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            expandableContentView.topAnchor.constraint(equalTo: view.topAnchor),
            expandableContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandableContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tradeActionsHostView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            tradeActionsHostView.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: TradeActionsLayout.horizontalMargin
            ),
            tradeActionsHostView.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -TradeActionsLayout.horizontalMargin
            ),
            tradeActionsHostView.widthAnchor.constraint(lessThanOrEqualToConstant: TradeActionsLayout.maxWidth),
            tradeActionsHostView.heightAnchor.constraint(equalToConstant: TradeActionsLayout.buttonHeight),
            bottomConstraint,
            preferredWidthConstraint,
            maxWidthConstraint,
        ])
        expandableContentView.configure(token: currentToken)
        updateHeroVisibility()
        updateTradeActions()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tokenVM.refreshTransactions()
        loadActivityHistoryInBackgroundIfNeeded()
    }

    private func loadActivityHistoryInBackgroundIfNeeded() {
        guard !hasBalance, let activityViewModel, activityViewModel.isEndReached != true else { return }
        Task {
            await activityViewModel.requestMoreIfNeeded()
        }
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        for case let cell as TokenChartCell in collectionView.visibleCells {
            registerRangeGestureDependencies(for: cell)
        }
        updateSafeAreaInsets()
        // The title view can join the bar after the native push has started.
        UIView.performWithoutAnimation {
            updateScroll()
            view.layoutIfNeeded()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var bottom = -TradeActionsLayout.bottomSpacing
        if #available(iOS 27.1, *), !isInModal, !isSharedBottomToolbarHosted,
           let container = navigationController?.view,
           let frame = container.verticalToolbarBottomButtonFrame {
            let centerY = view.convert(frame, from: container).midY
            bottom = centerY + TradeActionsLayout.buttonHeight / 2 - view.safeAreaLayoutGuide.layoutFrame.maxY
        }
        if let constraint = tradeActionsBottomConstraint, constraint.constant != bottom {
            constraint.constant = bottom
            updateSafeAreaInsets()
        }
    }

    private var minimumBottomContentInset: CGFloat {
        let reservesLocalTradeActions = !sharedBottomToolbarActions.isEmpty && !isSharedBottomToolbarHosted
        let bottomSpacing = -(tradeActionsBottomConstraint?.constant ?? -TradeActionsLayout.bottomSpacing)
        let reservedHeight = reservesLocalTradeActions ? TradeActionsLayout.buttonHeight + bottomSpacing : 0
        return view.safeAreaInsets.bottom
            + 16
            + reservedHeight
    }

    private func updateSafeAreaInsets() {
        let minimumInset = minimumBottomContentInset
        // A drag can extend the inset to allow the header to collapse on short lists.
        guard minimumInset != minimumBottomContentInsetSnapshot else { return }
        minimumBottomContentInsetSnapshot = minimumInset
        collectionView.contentInset.bottom = minimumInset

        if !IOS_26_MODE_ENABLED {
            scrollViewDidScroll(collectionView)
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard hasBalance else { return }
        let automaticTopInset = scrollView.adjustedContentInset.top - scrollView.contentInset.top
        let safeBottom = view.safeAreaInsets.bottom
        let fullScrollRange = expandableContentView.metrics.fullScrollRange
        let requiredBottomInset = fullScrollRange
            - collectionView.contentSize.height
            + collectionView.frame.height
            - automaticTopInset
            - safeBottom
        collectionView.contentInset.bottom = max(minimumBottomContentInset, requiredBottomInset)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let infoTransitionScrollAnchor {
            if abs(scrollView.contentOffset.y - infoTransitionScrollAnchor.y) > 0.01 {
                scrollView.contentOffset = infoTransitionScrollAnchor
            }
            return
        }
        guard !suppressScrollUpdates else { return }
        updateScroll()
    }

    private func updateScroll() {
        let scrollOffset = scrollOffset(for: collectionView)

        let navBarShift = navigationHeader.distanceFromNavigationBarBottomToContentCenter
        if hasBalance {
            expandableContentView.update(scrollOffset: scrollOffset, navBarShift: navBarShift)
        }

        updateNavigationBarChrome(scrollOffset: scrollOffset)
        updateVisibleActivityNftAnimationPlayback()
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard hasBalance else { return }
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

        navigationHeader.visibilityAlpha = hasBalance ? min(1, max(0, (30 - scrollOffset) / 14 + 1)) : 1
    }

    private func updateHeroVisibility() {
        expandableContentView.setRenderingVisible(hasBalance)
        expandableContentView.alpha = hasBalance ? 1 : 0
        expandableContentView.transform = hasBalance ? .identity : CGAffineTransform(translationX: 0, y: -16)
        expandableContentView.isUserInteractionEnabled = hasBalance
        expandableContentView.accessibilityElementsHidden = !hasBalance
        navigationHeader.viewToRedirectTouchesTo = hasBalance ? expandableContentView : nil
    }

    @discardableResult
    private func updateOwnershipLayout() -> Bool {
        guard hasBalance != hasSellableBalance else { return false }
        hasBalance = hasSellableBalance
        loadActivityHistoryInBackgroundIfNeeded()
        infoTransitionScrollAnchor = nil
        let animated = shouldAnimateContentUpdates
        let snapshot = makeSnapshot(reconfiguringCustomSections: [])
        activitySnapshot = snapshot
        applyContentReplacementSnapshot(snapshot, animatingDifferences: animated, alongside: { [weak self] in
            guard let self else { return }
            reconfigureHeaderPlaceholder(animated: animated)
            updateHeroVisibility()
            tokenInfoModel.configure(state: tokenVM.tokenInfoState, hasBalance: hasBalance)
            (visibleCustomSectionCell(id: infoCustomSectionID) as? TokenInfoCell)?.modelStateDidChange()
            updateChartCustomSection()
            updateTradeActions()
            collectionView.contentInset.bottom = minimumBottomContentInset
            updateScroll()
        }, completion: { [weak self] in
            guard let self else { return }
            updateSkeletonState()
            updateScroll()
        })
        return true
    }

    private func updateTradeActions() {
        let actions = sharedBottomToolbarActions
        let actionsChanged = actions != tradeActionsSnapshot
        if actionsChanged {
            tradeActionsSnapshot = actions
            onSharedBottomToolbarActionsChange?()
        }
        guard isViewLoaded else { return }

        tradeActionsHostView.isHidden = isSharedBottomToolbarHosted || actions.isEmpty
        receiveButton.isHidden = !actions.contains { $0.id == SharedToolbarActionID.receive }
        buyButton.isHidden = !actions.contains { $0.id == SharedToolbarActionID.buy }
        sellButton.isHidden = !actions.contains { $0.id == SharedToolbarActionID.sell }

        updateSafeAreaInsets()
    }

    public func setSharedBottomToolbarHosted(_ isHosted: Bool) {
        guard isSharedBottomToolbarHosted != isHosted else { return }
        isSharedBottomToolbarHosted = isHosted
        updateTradeActions()
    }

    public func performSharedBottomToolbarAction(id: String) {
        switch id {
        case SharedToolbarActionID.buy:
            guard areTradeActionsAvailable else { return }
            presentTokenTrade(isBuying: true)
        case SharedToolbarActionID.sell:
            guard areTradeActionsAvailable, hasSellableBalance else { return }
            presentTokenTrade(isBuying: false)
        case SharedToolbarActionID.receive:
            guard canReceiveToken else { return }
            AppActions.showReceive(accountContext: accountContext, chain: currentToken.chain, buyingToken: currentToken.slug)
        default:
            break
        }
    }

    private func presentTokenTrade(isBuying: Bool) {
        Task { [accountContext, currentToken] in
            await AppActions.showTokenTrade(accountContext: accountContext, token: currentToken, isBuying: isBuying)
        }
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
        let snapshot = NavigationMenuSnapshot(
            links: tokenVM.tokenInfoState.details?.links,
            explorerURL: ExplorerHelper.tokenUrl(token: currentToken),
            isRestricted: ConfigStore.shared.shouldRestrictSwapsAndOnRamp
        )
        guard snapshot != navigationMenuSnapshot else { return }
        navigationMenuSnapshot = snapshot
        let menu = makeMenu()
        navigationItem.rightBarButtonItem = menu.children.isEmpty
            ? nil
            : UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
    }

    private func makeMenu() -> UIMenu {
        let share = UIAction(title: lang("Share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            guard let self else { return }
            let token = currentToken
            var url = URL(string: SHORT_UNIVERSAL_URL)!.appendingPathComponent("token")
            if let tokenAddress = token.tokenAddress?.nilIfEmpty {
                url = url.appendingPathComponent(token.chain.rawValue).appendingPathComponent(tokenAddress)
            } else {
                url = url.appendingPathComponent(token.slug)
            }
            AppActions.copyString(url.absoluteString, toastMessage: lang("Link Copied"))
        }
        var sections: [UIMenu] = []

        guard !ConfigStore.shared.shouldRestrictSwapsAndOnRamp else {
            return UIMenu(children: [share])
        }

        let openUrl: (URL) -> () = { url in
            AppActions.openInBrowser(url)
        }
        let token = currentToken
        let details = tokenVM.tokenInfoState.details

        let aggregatorActions = details?.links?
            .filter { $0.kind == .aggregator && $0.url.isValidTokenMenuUrl }
            .map { link in
                UIAction(title: link.title) { _ in
                    openUrl(link.url)
                }
            } ?? []
        if !aggregatorActions.isEmpty {
            sections.append(UIMenu(options: .displayInline, children: aggregatorActions))
        }

        let tokenInfoActions = details?.links?
            .filter { [.documentation, .sourceCode].contains($0.kind) && $0.url.isValidTokenMenuUrl }
            .map { link in
                UIAction(title: lang(link.title)) { _ in
                    openUrl(link.url)
                }
            } ?? []
        if !tokenInfoActions.isEmpty {
            sections.append(UIMenu(options: .displayInline, children: tokenInfoActions))
        }

        if let explorerUrl = ExplorerHelper.tokenUrl(token: token) {
            let openInExplorer = UIAction(
                title: lang("Open in Explorer"),
                image: UIImage(named: "SendGlobe", in: AirBundle, with: nil)
            ) { _ in
                openUrl(explorerUrl)
            }
            sections.append(UIMenu(options: .displayInline, children: [openInExplorer, share]))
        } else {
            sections.append(UIMenu(options: .displayInline, children: [share]))
        }

        return UIMenu(children: sections)
    }
}

private extension URL {
    var isValidTokenMenuUrl: Bool {
        guard let scheme = scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              host?.nilIfEmpty != nil else {
            return false
        }
        return true
    }
}

extension TokenVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            updateNavigationMenu()
            updateActionsCustomSection()
            updateTradeActions()
            tokenVM.refreshTokenDetails()
        case .tokensChanged:
            updateNavigationHeader()
        case .stakingAccountData(let data):
            if data.accountId == accountContext.accountId {
                updateActionsCustomSection()
            }
        default:
            break
        }
    }
}

extension TokenVC: TokenVMDelegate {
    func dataUpdated() {
        guard isViewLoaded else { return }
        let ownershipChanged = updateOwnershipLayout()
        expandableContentView.configure(token: currentToken)
        updateNavigationHeader()
        updateActionsCustomSection()
        if !ownershipChanged {
            updateChartCustomSection()
            updateTradeActions()
        }
        updateTokensInVisibleRows()
    }
    func priceDataUpdated() {
        guard isViewLoaded else { return }
        updateChartCustomSection()
    }
    func tokenDetailsUpdated() {
        tokenInfoModel.configure(state: tokenVM.tokenInfoState, hasBalance: hasBalance)
        updateNavigationMenu()
        (visibleCustomSectionCell(id: infoCustomSectionID) as? TokenInfoCell)?.modelStateDidChange()
    }
    func accountChanged() {
        guard accountContext.source == .current else { return }
        let newAccountId = accountContext.accountId
        Task {
            self.tokenVM = TokenVM(accountId: newAccountId, selectedToken: token, tokenVMDelegate: self)
            self.activityViewModel = await ActivityListViewModel(accountId: newAccountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
            self.tokenVM.refreshTransactions()
            self.dataUpdated()
            self.updateActivities(animated: false)
            self.loadActivityHistoryInBackgroundIfNeeded()
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
        updateActivities(animated: true)
    }
}
