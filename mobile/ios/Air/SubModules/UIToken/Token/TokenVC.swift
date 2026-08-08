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
public class TokenVC: ActivityListViewController {

    @MainActor
    private enum TradeActionsLayout {
        static var buttonHeight: CGFloat {
            WButton.height(for: .primary)
        }
        static let buttonSpacing: CGFloat = 12
        static let bottomSpacing: CGFloat = 10
        static let horizontalMargin: CGFloat = 36
        static let maxWidth: CGFloat = 500

        static var reservedHeight: CGFloat {
            buttonHeight + bottomSpacing
        }
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
            self?.presentSwap(isBuying: true)
        }, for: .touchUpInside)
        return button
    }()

    private lazy var sellButton: WButton = {
        let button = WButton(style: .primary)
        button.customTintColor = .air.negativeAmount
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(lang("Sell"), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.presentSwap(isBuying: false)
        }, for: .touchUpInside)
        return button
    }()

    private lazy var tradeActionsView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [buyButton, sellButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = TradeActionsLayout.buttonSpacing
        stackView.distribution = .fillEqually
        return stackView
    }()

    private lazy var tradeActionsHostView: UIView = {
        guard #available(iOS 26, *) else {
            return tradeActionsView
        }

        let effect = UIGlassContainerEffect()
        effect.spacing = 0
        let effectView = UIVisualEffectView(effect: effect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(tradeActionsView)
        NSLayoutConstraint.activate([
            tradeActionsView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            tradeActionsView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            tradeActionsView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            tradeActionsView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
        ])
        return effectView
    }()

    private lazy var expandableContentView = TokenExpandableContentView(accountContext: accountContext)

    private let actionsCustomSectionID = "actions"
    private var actionsCustomSectionDescriptor: CustomSectionDescriptor?

    private let chartCustomSectionID = "chart"
    private var chartCustomSectionDescriptor: CustomSectionDescriptor?

    private let infoCustomSectionID = "info"
    private lazy var tokenInfoModel = TokenInfoModel(state: tokenVM.tokenInfoState)
    private var infoCustomSectionDescriptor: CustomSectionDescriptor?

    private var suppressScrollUpdates = false

    private struct NavigationHeaderSnapshot: Equatable {
        var title: String
        var badgeLabel: String?
        var isRwaStock: Bool
    }

    private var navigationHeaderSnapshot: NavigationHeaderSnapshot?

    private func updateCustomSectionHeight(id: String) {
        suppressScrollUpdates = true
        defer {
            suppressScrollUpdates = false
            updateNavigationBarChrome(scrollOffset: scrollOffset(for: collectionView))
        }

        let savedOffset = collectionView.contentOffset
        UIView.performWithoutAnimation {
            self.invalidateCustomSectionLayout(id: id)
            self.collectionView.layoutIfNeeded()
            if self.collectionView.contentOffset.y != savedOffset.y {
                self.collectionView.contentOffset = savedOffset
            }
        }
    }

    public override var headerPlaceholderHeight: CGFloat {
        expandableContentView.metrics.headerPlaceholderHeight
    }

    public override var customSections: [CustomSectionDescriptor] {
        if isLpToken {
            return [actionsCustomSectionDescriptor, infoCustomSectionDescriptor].compactMap { $0 }
        }
        return [actionsCustomSectionDescriptor, chartCustomSectionDescriptor, infoCustomSectionDescriptor].compactMap { $0 }
    }

    public override var activeCustomSectionIDs: [String] {
        if isLpToken {
            return tokenVM.tokenInfoState.isSectionVisible
                ? [actionsCustomSectionID, infoCustomSectionID]
                : [actionsCustomSectionID]
        }
        if tokenVM.tokenInfoState.isSectionVisible {
            return [actionsCustomSectionID, chartCustomSectionID, infoCustomSectionID]
        }
        return [actionsCustomSectionID, chartCustomSectionID]
    }

    private func configureActionsCustomSection(cell: TokenActionsCell) {
        let token = currentToken
        cell.setup(accountContext: accountContext, token: token)
        cell.configure(
            token: token,
            sendAvailable: account.supportsSend,
            earnAvailable: accountContext.isEarnAvailable(forTokenSlug: token.slug)
        )
    }
    private func configureChartCustomSection(cell: TokenChartCell) {
        let token = currentToken
        cell.setup(onHeightChange: { [weak self] in
            guard let self else { return }
            updateCustomSectionHeight(id: chartCustomSectionID)
        })
        cell.configure(token: token,
                       historyData: tokenVM.historyData) { [weak self] period in
            guard let self else { return }
            tokenVM.selectedPeriod = period
        }
    }
    private func configureInfoCustomSection(cell: TokenInfoCell) {
        tokenInfoModel.configure(state: tokenVM.tokenInfoState)
        cell.configure(model: tokenInfoModel, onHeightChange: { [weak self] in
            guard let self else { return }
            updateCustomSectionHeight(id: infoCustomSectionID)
        })
    }
    private func configureCustomSections() {
        let actionsCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenActionsCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureActionsCustomSection(cell: cell)
        }
        actionsCustomSectionDescriptor = CustomSectionDescriptor(id: actionsCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: actionsCustomSectionCellRegistration, for: indexPath, item: .custom(actionsCustomSectionID))
        }

        let chartCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenChartCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureChartCustomSection(cell: cell)
        }
        chartCustomSectionDescriptor = CustomSectionDescriptor(id: chartCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: chartCustomSectionCellRegistration, for: indexPath, item: .custom(chartCustomSectionID))
        }

        let infoCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenInfoCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureInfoCustomSection(cell: cell)
        }
        infoCustomSectionDescriptor = CustomSectionDescriptor(id: infoCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: infoCustomSectionCellRegistration, for: indexPath, item: .custom(infoCustomSectionID))
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
            tradeActionsHostView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -TradeActionsLayout.bottomSpacing
            ),
            preferredWidthConstraint,
            maxWidthConstraint,
        ])
        expandableContentView.configure(token: currentToken)
        updateTradeActions()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tokenVM.refreshTransactions()
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
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
            + 16
            + (areTradeActionsAvailable ? TradeActionsLayout.reservedHeight : 0)

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
        let minimumBottomInset = safeBottom
            + 16
            + (areTradeActionsAvailable ? TradeActionsLayout.reservedHeight : 0)
        collectionView.contentInset.bottom = max(minimumBottomInset, requiredBottomInset)
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

    private func updateTradeActions() {
        guard isViewLoaded else { return }

        let actionsAvailable = areTradeActionsAvailable
        tradeActionsHostView.isHidden = !actionsAvailable
        sellButton.isHidden = !hasSellableBalance

        updateSafeAreaInsets()
    }

    private func presentSwap(isBuying: Bool) {
        let counterTokenSlug = currentToken.slug == TONCOIN_SLUG ? TON_USDT_SLUG : TONCOIN_SLUG
        AppActions.showSwap(
            accountContext: accountContext,
            defaultSellingToken: isBuying ? counterTokenSlug : currentToken.slug,
            defaultBuyingToken: isBuying ? currentToken.slug : counterTokenSlug,
            defaultSellingAmount: nil,
            push: nil
        )
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
        if ConfigStore.shared.shouldRestrictSwapsAndOnRamp {
            navigationItem.rightBarButtonItem = nil
            return
        }

        let menu = makeMenu()
        navigationItem.rightBarButtonItem = menu.children.isEmpty
            ? nil
            : UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
    }

    private func makeMenu() -> UIMenu {
        let openUrl: (URL) -> () = { url in
            AppActions.openInBrowser(url)
        }
        let token = currentToken
        let details = tokenVM.tokenInfoState.details
        var sections: [UIMenu] = []

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
            sections.append(UIMenu(options: .displayInline, children: [openInExplorer]))
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
            applySnapshot(makeSnapshot(), animatingDifferences: true)
            updateTradeActions()
            tokenVM.refreshTokenDetails()
        case .tokensChanged:
            updateNavigationHeader()
        case .stakingAccountData(let data):
            if data.accountId == accountContext.accountId {
                reconfigureCustomSection(id: actionsCustomSectionID)
            }
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
        updateTradeActions()
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
        updateTradeActions()
    }
    func tokenDetailsUpdated() {
        tokenInfoModel.configure(state: tokenVM.tokenInfoState)
        updateNavigationMenu()
        applySnapshot(makeSnapshot(), animatingDifferences: true)
        (visibleCustomSectionCell(id: infoCustomSectionID) as? TokenInfoCell)?.modelStateDidChange()
    }
    func accountChanged() {
        guard accountContext.source == .current else { return }
        let newAccountId = accountContext.accountId
        Task {
            self.tokenVM = TokenVM(accountId: newAccountId, selectedToken: token, tokenVMDelegate: self)
            self.activityViewModel = await ActivityListViewModel(accountId: newAccountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
            self.tokenVM.refreshTransactions()
            self.updateNavigationHeader()
            self.updateTradeActions()
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
