
import Dependencies
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let log = Log("WalletTokens")
private let contextMenuPreviewCornerRadius: CGFloat = 26
private let contextMenuPreviewShadowInset = CGSize(width: 12, height: 10)

public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, UICollectionViewDelegate, Sendable, WSegmentedControllerContent {
    @AccountContext private var account: MAccount

    private let layoutMode: LayoutMode
    
    private var collectionView: UICollectionView!
    private lazy var dataSource: CollectionViewDataSource = makeDataSource()
    private var currentHeight: CGFloat = WalletTokenCell.defaultHeight * 4
    private var pendingInteractiveSwitchAccountId: String?
    private var contextMenuExtraBlurView: UIView?

    public var onHeightChanged: ((_ animated: Bool) -> Void)?

    var skeletonViewCandidates: [UIView] {
        collectionView.visibleCells.compactMap { ($0 as? ActivitySkeletonCollectionCell)?.contentView }
    }

    public var calculatedHeight: CGFloat {
        currentHeight
    }

    public var hostedHeight: CGFloat {
        switch layoutMode {
        case .expanded:
            return currentHeight
        case .compact, .compactLarge:
            let maxVisibleRowsHeight = CGFloat(layoutMode.visibleRowsLimit) * WalletTokenCell.defaultHeight
            return max(currentHeight, maxVisibleRowsHeight + WalletSeeAllCell.defaultHeight)
        }
    }

    // MARK: - Init

    public init(accountSource: AccountSource, mode: LayoutMode) {
        self._account = AccountContext(source: accountSource)
        self.layoutMode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
        updateWalletTokens(animated: false)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onHeightChanged?(false)
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear

        let collectionViewClass = layoutMode.isCompact ? _NoInsetsCollectionView.self : UICollectionView.self
        collectionView = collectionViewClass.init(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes

        if case .compact = layoutMode {
            collectionView.bounces = false
            collectionView.isScrollEnabled = false
            collectionView.showsHorizontalScrollIndicator = false
        }

        view.addStretchedToBounds(subview: collectionView)
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            self?.makeSectionLayout(sectionIndex: sectionIndex, layoutEnvironment: layoutEnvironment)
        }
    }

    private func makeSectionLayout(sectionIndex _: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = true
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        if !IOS_26_MODE_ENABLED {
            configuration.separatorConfiguration.color = layoutMode.isCompact ? .air.separator : .air.separatorDarkBackground
        }
        configuration.itemSeparatorHandler = { [weak self] indexPath, separatorConfiguration in
            guard let self else { return separatorConfiguration }
            guard let section = self.section(at: indexPath.section) else { return separatorConfiguration }

            var separatorConfiguration = separatorConfiguration
            let itemsInSection = self.dataSource.snapshot().itemIdentifiers(inSection: section)
            let isLastItemInSection = indexPath.item == itemsInSection.count - 1
            if isLastItemInSection {
                separatorConfiguration.bottomSeparatorVisibility = .hidden
            }
            return separatorConfiguration
        }
        return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
    }

    private func section(at index: Int) -> Section? {
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(index) else {
            return nil
        }
        return sections[index]
    }

    private func makeDataSource() -> CollectionViewDataSource {
        let placeholderRegistration = UICollectionView.CellRegistration<ActivitySkeletonCollectionCell, Int> { cell, _, _ in
            cell.configure()
        }
        let seeAllRegistration = UICollectionView.CellRegistration<WalletSeeAllCell, Int> { [unowned self] cell, _, tokensCount in
            let visibleTokensMenu: UIMenu? = switch layoutMode {
            case .compact:
                makeVisibleTokensLimitMenu()
            case .compactLarge, .expanded:
                nil
            }
            cell.configure(tokensCount: tokensCount, menu: visibleTokensMenu)
            cell.configurationUpdateHandler = { seeAllCell, state in
                seeAllCell.isHighlighted = state.isHighlighted
            }
        }

        let dataSource: CollectionViewDataSource
        if layoutMode.isCompact {
            let tokenRegistration = UICollectionView.CellRegistration<WalletTokenCell, TokenBalanceItem> { [unowned self] cell, indexPath, item in
                configureTokenCell(cell, indexPath: indexPath, item: item)
                cell.configurationUpdateHandler = { tokenCell, state in
                    tokenCell.isHighlighted = state.isHighlighted
                }
            }
            dataSource = CollectionViewDataSource(collectionView: collectionView) { collectionView, indexPath, item in
                switch item {
                case .token(let item):
                    collectionView.dequeueConfiguredReusableCell(using: tokenRegistration, for: indexPath, item: item)
                case .placeholder(let placeholderID):
                    collectionView.dequeueConfiguredReusableCell(using: placeholderRegistration, for: indexPath, item: placeholderID)
                case .seeAll(let tokensCount):
                    collectionView.dequeueConfiguredReusableCell(using: seeAllRegistration, for: indexPath, item: tokensCount)
                }
            }
        } else {
            let tokenRegistration = UICollectionView.CellRegistration<AssetsWalletTokenCell, TokenBalanceItem> { [unowned self] cell, indexPath, item in
                configureTokenCell(cell, indexPath: indexPath, item: item)
                cell.configurationUpdateHandler = { tokenCell, state in
                    tokenCell.isHighlighted = state.isHighlighted
                }
            }
            dataSource = CollectionViewDataSource(collectionView: collectionView) { collectionView, indexPath, item in
                switch item {
                case .token(let item):
                    collectionView.dequeueConfiguredReusableCell(using: tokenRegistration, for: indexPath, item: item)
                case .placeholder(let placeholderID):
                    collectionView.dequeueConfiguredReusableCell(using: placeholderRegistration, for: indexPath, item: placeholderID)
                case .seeAll(let tokensCount):
                    collectionView.dequeueConfiguredReusableCell(using: seeAllRegistration, for: indexPath, item: tokensCount)
                }
            }
        }

        return dataSource
    }

    private func configureTokenCell(_ cell: WalletTokenCell, indexPath: IndexPath, item: TokenBalanceItem) {
        let account = self.account
        let token = item.tokenBalance
        let badgeContent = getBadgeContent(accountContext: _account, slug: token.tokenSlug, isStaking: token.isStaking)

        let highlightBackgroundWhenPinned = !layoutMode.isCompact
        let showUnderNavbarPinningColor = indexPath.item == 0 && item.isPinned && highlightBackgroundWhenPinned
        cell.underNavigationBarColorView.isVisible = showUnderNavbarPinningColor

        cell.configure(with: item.tokenBalance,
                       animated: item.animatedAmounts,
                       badgeContent: badgeContent,
                       isMultichain: account.isMultichain,
                       isPinned: item.isPinned,
                       highlightBackgroundWhenPinned: highlightBackgroundWhenPinned)
    }

    private func applySnapshot(animatedAmounts: Bool, walletTokensViewState: WalletTokensViewState) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        snapshot.appendSections([.main])
        let items: [Item] = switch walletTokensViewState {
        case .loaded(let rows, _):
            rows.map { .token(item: $0) }
        case .placeholders(let count):
            (0 ..< count).map(Item.placeholder)
        }
        snapshot.appendItems(items)
        snapshot.reconfigureItems(items)

        switch walletTokensViewState {
        case .loaded(let rows, let allTokensCount):
            if allTokensCount > rows.count {
                snapshot.appendSections([.seeAll])
                snapshot.appendItems([.seeAll(tokensCount: allTokensCount)])
            }
        case .placeholders:
            break
        }

        currentHeight = snapshot.itemIdentifiers.reduce(into: CGFloat(0)) { totalHeight, item in
            totalHeight += item.defaultHeight
        }
        dataSource.apply(snapshot, animatingDifferences: animatedAmounts)
    }

    // MARK: - Data Updates

    private func updateWalletTokens(animated: Bool) {
        let walletTokensViewState = makeWalletTokensViewState(animatedAmounts: animated)
        applySnapshot(animatedAmounts: animated, walletTokensViewState: walletTokensViewState)
        onHeightChanged?(animated)
    }

    private func makeWalletTokensViewState(animatedAmounts: Bool) -> WalletTokensViewState {
        guard let walletTokensData = $account.walletTokensData else {
            return .placeholders(count: 4)
        }

        let assetsData = AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty
        let tokenBalances = makeTokenBalances(walletTokensData: walletTokensData)
        let sortedTokens = MTokenBalance.sortedForUI(
            tokenBalances: tokenBalances,
            assetsAndActivityData: assetsData,
            balances: $account.balances,
            defaultTokenSlugs: ApiToken.defaultSlugs(forNetwork: account.network)
        )
        let visibleTokens = makeVisibleTokens(from: sortedTokens)
        let rows = visibleTokens.map { tokenBalance in
            TokenBalanceItem(
                tokenBalance: tokenBalance,
                accountId: account.id,
                isPinned: isTokenPinned(tokenBalance, assetsAndActivityData: assetsData),
                animatedAmounts: animatedAmounts
            )
        }

        return .loaded(rows: rows, allTokensCount: sortedTokens.count)
    }

    private func makeTokenBalances(walletTokensData: MAccountWalletTokensData) -> [MTokenBalance] {
        (walletTokensData.walletStaked + walletTokensData.walletTokens).map { tokenBalance in
            MTokenBalance(
                tokenSlug: tokenBalance.tokenSlug,
                balance: tokenBalance.balance,
                isStaking: tokenBalance.isStaking
            )
        }
    }

    private func makeVisibleTokens(from sortedTokens: [MTokenBalance]) -> [MTokenBalance] {
        if layoutMode.isCompact {
            return Array(sortedTokens.prefix(layoutMode.visibleRowsLimit))
        } else {
            return sortedTokens
        }
    }

    private func isTokenPinned(_ tokenBalance: MTokenBalance, assetsAndActivityData: MAssetsAndActivityData) -> Bool {
        switch assetsAndActivityData.isTokenPinned(slug: tokenBalance.tokenSlug, isStaked: tokenBalance.isStaking) {
        case .pinned:
            true
        case .notPinned:
            false
        }
    }

    private func reloadStakeCells(animated _: Bool) { // Improvement: this should simply be an apply snapshot
        for cell in collectionView.visibleCells {
            if let cell = cell as? WalletTokenCell, let walletToken = cell.walletToken {
                let badgeContent = getBadgeContent(accountContext: _account, slug: walletToken.tokenSlug, isStaking: walletToken.isStaking)
                cell.configureBadge(badgeContent: badgeContent)
            }
        }
    }

    public func switchAccountTo(accountId: String, animated: Bool) {
        pendingInteractiveSwitchAccountId = accountId
        $account.accountId = accountId
        updateWalletTokens(animated: animated)
    }

    // MARK: - WalletCoreData.EventsObserver

    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated { // Improvement: replace with safe construct
            switch event {
            case .accountChanged:
                if $account.source == .current {
                    let shouldSkipUpdate = pendingInteractiveSwitchAccountId == account.id
                    pendingInteractiveSwitchAccountId = nil
                    if !shouldSkipUpdate {
                        updateWalletTokens(animated: false)
                    }
                    reloadStakeCells(animated: false)
                }

            case .stakingAccountData(let data):
                if data.accountId == self.account.id {
                    reloadStakeCells(animated: true)
                }

            case .tokensChanged:
                updateWalletTokens(animated: true)

            case .assetsAndActivityDataUpdated:
                updateWalletTokens(animated: true)

            case .balanceChanged(let accountId):
                if accountId == self.account.id {
                    updateWalletTokens(animated: true)
                }

            case .homeWalletVisibleTokensLimitChanged:
                updateWalletTokens(animated: true)

            default:
                break
            }
        }
    }

    // MARK: - Token Selection

    private func didSelectToken(_ walletToken: MTokenBalance) {
        let slug = walletToken.tokenSlug
        if slug == STAKED_TON_SLUG || slug == STAKED_MYCOIN_SLUG || slug == TON_TSUSDE_SLUG || walletToken.isStaking {
            goToStakedPage(slug: slug)
        } else {
            didSelect(slug: slug)
        }
    }

    private func didSelect(slug: String) {
        guard let token = TokenStore.tokens[slug] else { return Log.shared.error("Token \(slug) not found") }
        AppActions.showToken(accountSource: $account.source, token: token, isInModal: !layoutMode.isCompact)
    }

    private func stakingBaseSlug(for slug: String) -> String? {
        switch slug {
        case TONCOIN_SLUG, STAKED_TON_SLUG:
            TONCOIN_SLUG
        case MYCOIN_SLUG, STAKED_MYCOIN_SLUG:
            MYCOIN_SLUG
        case TON_USDE_SLUG, TON_TSUSDE_SLUG:
            TON_USDE_SLUG
        default:
            nil
        }
    }

    private func goToStakedPage(slug: String) {
        AppActions.showEarn(accountContext: $account, tokenSlug: stakingBaseSlug(for: slug))
    }

    private func showEarnForToken(slug: String, isStaking: Bool) {
        if isStaking {
            goToStakedPage(slug: slug)
        } else {
            AppActions.showEarn(accountContext: $account, tokenSlug: slug)
        }
    }

    private func makeVisibleTokensLimitMenu() -> UIMenu {
        UIMenu(
            title: "",
            options: [.displayInline, .singleSelection],
            children: [
                UIDeferredMenuElement.uncached { completion in
                    let currentLimit = AppStorageHelper.homeWalletVisibleTokensLimit
                    let actions = HomeWalletVisibleTokensLimit.allCases.map { limit in
                        UIAction(
                            title: limit.title,
                            state: currentLimit == limit ? .on : .off
                        ) { _ in
                            AppStorageHelper.homeWalletVisibleTokensLimit = limit
                        }
                    }
                    completion(actions)
                }
            ]
        )
    }

    private func makeTokenMenu(walletToken: MTokenBalance) -> UIMenu {
        let tokenSlug = walletToken.tokenSlug
        let baseSlug = walletToken.isStaking ? (stakingBaseSlug(for: tokenSlug) ?? tokenSlug) : tokenSlug
        guard let token = TokenStore.getToken(slug: tokenSlug) ?? TokenStore.getToken(slug: baseSlug) else {
            return UIMenu(title: "", children: [])
        }
        let account = self.account
        let accountID = account.id
        let isViewMode = account.isView
        let isServiceToken = token.type == .lp_token || token.isStakedToken || token.isPricelessToken
        let isSwapAvailable = account.supportsSwap && (TokenStore.swapAssets?.contains(where: { $0.slug == token.slug }) ?? false)
        
        let stakingState: ApiStakingState? = if walletToken.isStaking {
            if let state = $account.stakingData?.byStakedSlug(walletToken.tokenSlug) {
                state
            } else if let state = $account.stakingData?.bySlug(walletToken.tokenSlug) {
                state
            } else {
                nil
            }
        } else {
            nil
        }
        
        let canBeClaimed = stakingState.map { getStakingStateStatus(state: $0) == .readyToClaim } ?? false
        let hasUnclaimedRewards = stakingState?.type == .jetton ? (stakingState?.unclaimedRewards ?? 0) > 0 : false
        let isStakingAvailable = !walletToken.isStaking
            && account.supportsEarn
            && token.earnAvailable
            && $account.stakingData?.bySlug(token.slug) != nil
        let isStakingToken = walletToken.isStaking

        var primaryActions: [UIAction] = []
        var secondaryActions: [UIAction] = []

        if !isViewMode {
            if let stakingState {
                primaryActions.append(UIAction(title: lang("Stake More"), image: UIImage(systemName: "arrow.up")) { [weak self] _ in
                    self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                })
                if stakingState.type != .ethena || !canBeClaimed {
                    let title = stakingState.type == .ethena ? lang("Request Unstaking") : lang("Unstake")
                    primaryActions.append(UIAction(title: title, image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                        self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                    })
                }
                if canBeClaimed || hasUnclaimedRewards {
                    let image = UIImage(systemName: "bubbles.and.sparkles")
                    primaryActions.append(UIAction(title: lang("Claim Rewards"), image: image) { [weak self] _ in
                        self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                    })
                }
            } else {
                if !isServiceToken {
                    primaryActions.append(UIAction(title: lang("Fund"), image: UIImage(systemName: "plus")) { _ in
                        AppActions.showReceive(accountContext: self.$account, chain: token.chain, title: nil)
                    })
                }
                primaryActions.append(UIAction(title: lang("Send"), image: UIImage(systemName: "arrow.up")) { _ in
                    AppActions.showSend(accountContext: self.$account, prefilledValues: .init(token: token.slug))
                })
                if isSwapAvailable {
                    primaryActions.append(UIAction(title: lang("Swap"), image: UIImage(systemName: "arrow.left.arrow.right")) { _ in
                        let defaultBuying = token.slug == TONCOIN_SLUG ? nil : TONCOIN_SLUG
                        AppActions.showSwap(accountContext: self.$account,
                                            defaultSellingToken: token.slug,
                                            defaultBuyingToken: defaultBuying,
                                            defaultSellingAmount: nil,
                                            push: nil)
                    })
                }
                if isStakingAvailable {
                    primaryActions.append(UIAction(title: lang("Stake"), image: UIImage(systemName: "cylinder.split.1x2")) { _ in
                        AppActions.showEarn(accountContext: self.$account, tokenSlug: token.slug)
                    })
                }
            }
        }

        let assetsAndActivityData = AssetsAndActivityDataStore.data(accountId: accountID) ?? .empty
        let isStaking = walletToken.isStaking
        switch assetsAndActivityData.isTokenPinned(slug: walletToken.tokenSlug, isStaked: walletToken.isStaking) {
        case .pinned:
            secondaryActions.append(UIAction(title: lang("Unpin"), image: UIImage(systemName: "pin.slash")) { _ in
                AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                    settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: false)
                })
            })
        case .notPinned:
            secondaryActions.append(UIAction(title: lang("Pin"), image: UIImage(systemName: "pin")) { _ in
                AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                    settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: true)
                })
            })
        }
        
        let settingsImage = UIImage.airBundle("MenuSettings")
            .withTintColor(.air.background, renderingMode: .alwaysTemplate)
        
        secondaryActions.append(UIAction(title: lang("Manage Tokens"), image: settingsImage) { _ in
            AppActions.showAssetsAndActivity()
        })

        var menus: [UIMenuElement] = []
        if !primaryActions.isEmpty {
            menus.append(UIMenu(title: "", options: .displayInline, children: primaryActions))
        }
        if !secondaryActions.isEmpty {
            menus.append(UIMenu(title: "", options: .displayInline, children: secondaryActions))
        }
        return UIMenu(title: "", children: menus)
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return false
        }

        switch item {
        case .placeholder:
            return false
        case .token, .seeAll:
            return true
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .token(let item):
            didSelectToken(item.tokenBalance)
        case .seeAll:
            didSelectSeeAll()
        case .placeholder:
            break
        }
    }

    public func collectionView(_: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            Log.shared.error("Not found item for indexPath: \(indexPath)")
            return nil
        }

        return switch item {
        case .placeholder: nil
        case .seeAll: nil
        case .token(let item):
            UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
                self.makeTokenMenu(walletToken: item.tokenBalance)
            }
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard collectionView === self.collectionView else {
            return nil
        }
        return contextMenuPreview(for: configuration)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard collectionView === self.collectionView else {
            return nil
        }
        return contextMenuPreview(for: configuration)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplayContextMenu configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        guard collectionView === self.collectionView else {
            return
        }
        contextMenuExtraBlurView?.removeFromSuperview()
        contextMenuExtraBlurView = ContextMenuBackdropBlur.show(in: view.window, animator: animator)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        guard collectionView === self.collectionView else {
            return
        }
        let blurView = contextMenuExtraBlurView
        contextMenuExtraBlurView = nil
        ContextMenuBackdropBlur.hide(blurView, animator: animator)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
    }

    public func scrollViewWillBeginDragging(_: UIScrollView) {
        onScrollStart?()
    }

    public func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
        onScrollEnd?()
    }

    // MARK: - WSegmentedControllerContent

    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?

    public var scrollingView: UIScrollView? { collectionView }

    private func contextMenuPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? NSIndexPath,
              let cell = collectionView.cellForItem(at: indexPath as IndexPath) else {
            return nil
        }

        let previewView = cell.snapshotView(afterScreenUpdates: false) ?? UIView(frame: cell.bounds)
        previewView.frame = cell.bounds

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: contextMenuPreviewCornerRadius
        )
        let shadowRect = cell.bounds.insetBy(
            dx: contextMenuPreviewShadowInset.width,
            dy: contextMenuPreviewShadowInset.height
        )
        parameters.shadowPath = UIBezierPath(
            roundedRect: shadowRect,
            cornerRadius: max(0, contextMenuPreviewCornerRadius - contextMenuPreviewShadowInset.height)
        )

        let targetContainer: UIView
        if let window = view.window {
            targetContainer = window
        } else {
            targetContainer = collectionView
        }
        let targetCenter = targetContainer.convert(cell.bounds.center, from: cell)
        let target = UIPreviewTarget(container: targetContainer, center: targetCenter)
        return UITargetedPreview(view: previewView, parameters: parameters, target: target)
    }
}

// MARK: - Actions

extension WalletTokensVC {
    private func didSelectSeeAll() {
        AppActions.showAssets(accountSource: $account.source, selectedTab: 0, collectionsFilter: .none)
    }
}

// MARK: - Diffable Data Source Types

extension WalletTokensVC {
    private typealias CollectionViewDataSource = UICollectionViewDiffableDataSource<Section, Item>
    
    private enum Section: Hashable {
        case main
        case seeAll
    }
    
    private enum Item: Hashable {
        case token(item: TokenBalanceItem)
        case placeholder(Int)
        case seeAll(tokensCount: Int)
        
        var defaultHeight: CGFloat {
            switch self {
            case .token: WalletTokenCell.defaultHeight
            case .placeholder: ActivitySkeletonCollectionCell.defaultHeight
            case .seeAll: WalletSeeAllCell.defaultHeight
            }
        }
    }
    
    struct TokenBalanceItem: Hashable {
        // payload invisible to datasource
        @HashableExcluded var tokenBalance: MTokenBalance

        private let identity: Identity
        let animatedAmounts: Bool
        let isPinned: Bool

        init(tokenBalance: MTokenBalance, accountId: String, isPinned: Bool, animatedAmounts: Bool) {
            self.tokenBalance = tokenBalance
            self.identity = Identity(
                accountId: accountId,
                tokenIdentity: Self.makeTokenIdentity(slug: tokenBalance.tokenSlug, isStaking: tokenBalance.isStaking),
                isPinned: isPinned
            )
            self.animatedAmounts = animatedAmounts
            self.isPinned = isPinned
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }

        private struct Identity: Hashable {
            let accountId: String
            let tokenIdentity: String
            let isPinned: Bool
        }

        private static func makeTokenIdentity(slug: String, isStaking: Bool) -> String {
            if isStaking {
                return "staking-" + slug
            } else {
                return slug
            }
        }
    }
    
    private enum WalletTokensViewState {
        case loaded(rows: [TokenBalanceItem], allTokensCount: Int)
        case placeholders(count: Int)
    }
    
    public enum LayoutMode {
        case expanded
        case compact
        case compactLarge

        fileprivate var isCompact: Bool {
            self != .expanded
        }

        fileprivate var visibleRowsLimit: Int {
            switch self {
            case .expanded: .max
            case .compact:
                AppStorageHelper.homeWalletVisibleTokensLimit.rawValue
            case .compactLarge:
                6
            }
        }
    }
}
    
// MARK: - iPad fixup

//final class _NoInsetsTableView: UITableView {
//    override var safeAreaInsets: UIEdgeInsets { .zero }
//}
