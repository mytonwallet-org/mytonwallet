
import ContextMenuKit
import Dependencies
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let log = Log("WalletTokens")
private let contextMenuSourceCornerRadius: CGFloat = 26
private let walletTokenMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, UICollectionViewDelegate, Sendable, WSegmentedControllerContent {
    @AccountContext private var account: MAccount

    private let layoutMode: LayoutMode
    
    private var collectionView: UICollectionView!
    private lazy var dataSource: CollectionViewDataSource = makeDataSource()
    private var currentHeight: CGFloat = WalletTokenCell.defaultHeight * 4
    private var isShowingEmptyState = false
    private var isWalletAssetsEmptyStateAnimationActive = false
    private var walletAssetsEmptyStateAnimationSessionID = 0
    private var pendingInteractiveSwitchAccountId: String?

    public var onHeightChanged: ((_ animated: Bool) -> Void)?

    var skeletonViewCandidates: [UIView] {
        collectionView.visibleCells.compactMap { ($0 as? ActivitySkeletonCollectionCell)?.contentView }
    }

    public func calculateHeight(isHosted: Bool) -> CGFloat {
        if isHosted {
            switch layoutMode {
            case .expanded:
                return currentHeight
            case .compact, .compactLarge:
                if isShowingEmptyState {
                    return currentHeight
                }
                let maxVisibleRowsHeight = CGFloat(layoutMode.visibleRowsLimit) * WalletTokenCell.defaultHeight
                return max(currentHeight, maxVisibleRowsHeight + WalletSeeAllCell.defaultHeight)
            }
        }
        
        return currentHeight
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
        collectionView.contentInsetAdjustmentBehavior = layoutMode.isCompact ? .never : .scrollableAxes

        if layoutMode.isCompact {
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
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = IOS_26_MODE_ENABLED ? 12 : 0
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
        let emptyRegistration = UICollectionView.CellRegistration<WalletAssetsEmptyCell, Item> { [unowned self] cell, _, _ in
            cell.configure(
                animationName: "duck_no-data",
                title: lang("No tokens yet"),
                description: lang("$no_tokens_description"),
                actionTitle: lang("Add Tokens"),
                height: WalletAssetsEmptyCell.tokensHeight,
                descriptionNumberOfLines: 4
            ) { [weak self] in
                self?.didTapAddTokens()
            }
            applyEmptyStateAnimation(to: cell)
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
                case .empty:
                    collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: item)
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
                case .empty:
                    collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: item)
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
        cell.baseBackgroundColor = layoutMode.containerBackgroundColor

        cell.configure(with: item.tokenBalance,
                       animated: item.animatedAmounts,
                       badgeContent: badgeContent,
                       isMultichain: account.isMultichain,
                       isPinned: item.isPinned)

        let interaction = ContextMenuInteraction(
            triggers: [.longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: contextMenuSourceCornerRadius)
            ),
            pressAnimation: .default(transformMode: .sublayerTransform)
        ) { [weak self, walletToken = item.tokenBalance] _ in
            self?.makeTokenMenuConfiguration(walletToken: walletToken)
        }
        cell.setContextMenuInteraction(interaction)
    }

    private func applySnapshot(animatedAmounts: Bool, walletTokensViewState: WalletTokensViewState) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        snapshot.appendSections([.main])
        let items: [Item] = switch walletTokensViewState {
        case .loaded(let rows, _):
            rows.map { .token(item: $0) }
        case .empty:
            [.empty]
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
        case .empty:
            break
        case .placeholders:
            break
        }

        switch walletTokensViewState {
        case .empty:
            isShowingEmptyState = true
        case .loaded, .placeholders:
            isShowingEmptyState = false
        }
        currentHeight = snapshot.itemIdentifiers.reduce(into: CGFloat(0)) { totalHeight, item in
            totalHeight += item.defaultHeight
        }
        dataSource.apply(snapshot, animatingDifferences: animatedAmounts)
        updateVisibleEmptyStateAnimations()
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
        let pinPartition = MTokenBalance.partitionTokensByPinning(
            tokens: walletTokensData.orderedTokenBalances,
            assetsAndActivityData: assetsData
        )
        let orderedTokens = pinPartition.pinned + pinPartition.unpinned
        if orderedTokens.isEmpty {
            return .empty
        }
        let visibleTokens = makeVisibleTokens(from: orderedTokens)
        let pinnedTokenIDs = Set(pinPartition.pinned.map(\.tokenID))
        let rows = visibleTokens.map { tokenBalance in
            TokenBalanceItem(
                tokenBalance: tokenBalance,
                accountId: account.id,
                isPinned: pinnedTokenIDs.contains(tokenBalance.tokenID),
                animatedAmounts: animatedAmounts
            )
        }

        return .loaded(rows: rows, allTokensCount: orderedTokens.count)
    }

    private func makeVisibleTokens(from sortedTokens: [MTokenBalance]) -> [MTokenBalance] {
        if layoutMode.isCompact {
            return Array(sortedTokens.prefix(layoutMode.visibleRowsLimit))
        } else {
            return sortedTokens
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

    private func makeTokenMenuConfiguration(walletToken: MTokenBalance) -> ContextMenuConfiguration? {
        let tokenSlug = walletToken.tokenSlug
        let baseSlug = walletToken.isStaking ? (stakingBaseSlug(for: tokenSlug) ?? tokenSlug) : tokenSlug
        guard let token = TokenStore.getToken(slug: tokenSlug) ?? TokenStore.getToken(slug: baseSlug) else {
            return nil
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

        var primaryItems: [ContextMenuItem] = []
        var secondaryItems: [ContextMenuItem] = []

        if !isViewMode {
            if let stakingState {
                primaryItems.append(.action(
                    ContextMenuAction(
                        title: lang("Stake More"),
                        icon: .system("arrow.up"),
                        handler: { [weak self] in
                            self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                        }
                    )
                ))
                if stakingState.type != .ethena || !canBeClaimed {
                    let title = stakingState.type == .ethena ? lang("Request Unstaking") : lang("Unstake")
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: title,
                            icon: .system("arrow.down"),
                            handler: { [weak self] in
                                self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                            }
                        )
                    ))
                }
                if canBeClaimed || hasUnclaimedRewards {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Claim Rewards"),
                            icon: .system("bubbles.and.sparkles"),
                            handler: { [weak self] in
                                self?.showEarnForToken(slug: tokenSlug, isStaking: isStakingToken)
                            }
                        )
                    ))
                }
            } else {
                if !isServiceToken {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Fund"),
                            icon: .system("plus"),
                            handler: { [weak self] in
                                guard let self else { return }
                                AppActions.showReceive(accountContext: self.$account, chain: token.chain)
                            }
                        )
                    ))
                }
                primaryItems.append(.action(
                    ContextMenuAction(
                        title: lang("Send"),
                        icon: .system("arrow.up"),
                        handler: { [weak self] in
                            guard let self else { return }
                            AppActions.showSend(accountContext: self.$account, prefilledValues: .init(token: token.slug))
                        }
                    )
                ))
                if isSwapAvailable {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Swap"),
                            icon: .system("arrow.left.arrow.right"),
                            handler: { [weak self] in
                                guard let self else { return }
                                let defaultBuying = token.slug == TONCOIN_SLUG ? nil : TONCOIN_SLUG
                                AppActions.showSwap(accountContext: self.$account,
                                                    defaultSellingToken: token.slug,
                                                    defaultBuyingToken: defaultBuying,
                                                    defaultSellingAmount: nil,
                                                    push: nil)
                            }
                        )
                    ))
                }
                if isStakingAvailable {
                    primaryItems.append(.action(
                        ContextMenuAction(
                            title: lang("Stake"),
                            icon: .system("cylinder.split.1x2"),
                            handler: { [weak self] in
                                guard let self else { return }
                                AppActions.showEarn(accountContext: self.$account, tokenSlug: token.slug)
                            }
                        )
                    ))
                }
            }
        }

        let assetsAndActivityData = AssetsAndActivityDataStore.data(accountId: accountID) ?? .empty
        let isStaking = walletToken.isStaking
        switch assetsAndActivityData.isTokenPinned(slug: walletToken.tokenSlug, isStaked: walletToken.isStaking) {
        case .pinned:
            secondaryItems.append(.action(
                ContextMenuAction(
                    title: lang("Unpin"),
                    icon: .system("pin.slash"),
                    handler: {
                        AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                            settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: false)
                        })
                    }
                )
            ))
        case .notPinned:
            secondaryItems.append(.action(
                ContextMenuAction(
                    title: lang("Pin"),
                    icon: .system("pin"),
                    handler: {
                        AssetsAndActivityDataStore.update(accountId: accountID, update: { settings in
                            settings.saveTokenPinning(slug: tokenSlug, isStaking: isStaking, isPinned: true)
                        })
                    }
                )
            ))
        }

        secondaryItems.append(.action(
            ContextMenuAction(
                title: lang("Manage Assets"),
                icon: .airBundle("MenuManageAssets26"),
                handler: {
                    AppActions.showAssetsAndActivity()
                }
            )
        ))

        var items = primaryItems
        if !items.isEmpty, !secondaryItems.isEmpty {
            items.append(.separator)
        }
        items.append(contentsOf: secondaryItems)

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: walletTokenMenuStyle
        )
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return false
        }

        switch item {
        case .placeholder:
            return false
        case .empty:
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
        case .empty:
            break
        case .placeholder:
            break
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
    }

    // MARK: - WSegmentedControllerContent

    public var onScroll: ((CGFloat) -> Void)?
    public var scrollingView: UIScrollView? { collectionView }

}

// MARK: - Actions

extension WalletTokensVC {
    private func applyEmptyStateAnimation(to cell: WalletAssetsEmptyCell) {
        cell.updateAnimationPlayback(
            isPlaying: isWalletAssetsEmptyStateAnimationActive && isShowingEmptyState,
            playbackSessionID: walletAssetsEmptyStateAnimationSessionID
        )
    }

    private func updateVisibleEmptyStateAnimations() {
        guard isViewLoaded, collectionView != nil else {
            return
        }
        collectionView.layoutIfNeeded()
        for case let cell as WalletAssetsEmptyCell in collectionView.visibleCells {
            applyEmptyStateAnimation(to: cell)
        }
    }

    func setWalletAssetsEmptyStateAnimationActive(_ isActive: Bool) {
        isWalletAssetsEmptyStateAnimationActive = isActive
        if isActive {
            walletAssetsEmptyStateAnimationSessionID += 1
        }
        updateVisibleEmptyStateAnimations()
    }

    private func didSelectSeeAll() {
        AppActions.showAssets(accountSource: $account.source, selectedTab: .tokens, collectionsFilter: .none)
    }

    private func didTapAddTokens() {
        AppActions.showAssetsAndActivity()
    }
}

extension WalletTokensVC: WalletAssetsEmptyStateAnimationControlling { }

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
        case empty
        case seeAll(tokensCount: Int)
        
        var defaultHeight: CGFloat {
            switch self {
            case .token: WalletTokenCell.defaultHeight
            case .placeholder: ActivitySkeletonCollectionCell.defaultHeight
            case .empty: WalletAssetsEmptyCell.tokensHeight
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
        case empty
        case placeholders(count: Int)
    }
    
    public enum LayoutMode {
        case expanded
        case compact
        case compactLarge

        fileprivate var isCompact: Bool {
            self != .expanded
        }

        fileprivate var containerBackgroundColor: UIColor {
            isCompact ? .air.groupedItem : .air.pickerBackground
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
