
import Dependencies
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let log = Log("WalletTokens")

public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, UICollectionViewDelegate, Sendable, WSegmentedControllerContent {
    @AccountContext private var account: MAccount

    private let layoutMode: LayoutMode
    
    private var collectionView: UICollectionView!
    private lazy var dataSource: CollectionViewDataSource = makeDataSource()
    private var currentHeight: CGFloat = WalletTokenCell.defaultHeight * 4
    private var pendingInteractiveSwitchAccountId: String?

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

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        let collectionViewClass = layoutMode.isCompact ? _NoInsetsCollectionView.self : UICollectionView.self
        collectionView = collectionViewClass.init(frame: .zero, collectionViewLayout: layout)
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
                       isLast: item.isLast,
                       animated: item.animatedAmounts,
                       badgeContent: badgeContent,
                       isMultichain: account.isMultichain,
                       isPinned: item.isPinned,
                       highlightBackgroundWhenPinned: highlightBackgroundWhenPinned)
    }

    private func applySnapshot(animatedAmounts: Bool, walletTokensVM: WalletTokensVM) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let accountId = account.id
        let assetsAndActivityData = AssetsAndActivityDataStore.data(accountId: accountId) ?? .empty

        snapshot.appendSections([.main])
        let items: [Item] = switch walletTokensVM {
        case let .realTokens(tokensToShow, _):
            tokensToShow.enumerated().map { index, token in
                let isLast: Bool = index == tokensToShow.count - 1
                let isPinned = switch assetsAndActivityData.isTokenPinned(slug: token.tokenSlug, isStaked: token.isStaking) {
                case .pinned: true
                case .notPinned: false
                }
                return .token(item: TokenBalanceItem(tokenBalance: token,
                                                     accountId: accountId,
                                                     isPinned: isPinned,
                                                     animatedAmounts: animatedAmounts,
                                                     isLast: isLast))
            }

        case .tokensPlaceholders(let count):
            (0 ..< count).map(Item.placeholder)
        }
        snapshot.appendItems(items)
        snapshot.reconfigureItems(items)

        switch walletTokensVM {
        case let .realTokens(tokensToShow, allTokensCount):
            if allTokensCount > tokensToShow.count {
                snapshot.appendSections([.seeAll])
                snapshot.appendItems([.seeAll(tokensCount: allTokensCount)])
            }
        case .tokensPlaceholders: break
        }

        currentHeight = snapshot.itemIdentifiers.reduce(into: CGFloat(0)) { totalHeight, item in
            totalHeight += item.defaultHeight
        }
        dataSource.apply(snapshot, animatingDifferences: animatedAmounts)
    }

    // MARK: - Data Updates

    private func updateWalletTokens(animated: Bool) {
        let walletTokensVM: WalletTokensVM
        if let walletTokensData = $account.walletTokensData {
            let assetsData = AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty
            let tokenBalances = walletTokensData.walletStaked + walletTokensData.walletTokens
            let sorted = MTokenBalance.sortedForUI(tokenBalances: tokenBalances,
                                                   assetsAndActivityData: assetsData,
                                                   balances: $account.balances,
                                                   defaultTokenSlugs: ApiToken.defaultSlugs(forNetwork: account.network))
            let tokensToShow: [MTokenBalance] = if layoutMode.isCompact {
                sorted.lazy
                    .filter { ($0.tokenPrice ?? 0) > 0 }
                    .prefix(layoutMode.visibleRowsLimit)
                    .apply(Array.init)
            } else {
                sorted
            }

            walletTokensVM = .realTokens(tokensToShow: tokensToShow, allTokensCount: tokenBalances.count)
        } else {
            walletTokensVM = .tokensPlaceholders(count: 4)
        }

        applySnapshot(animatedAmounts: animated, walletTokensVM: walletTokensVM)
        onHeightChanged?(animated)
    }

    private func reloadStakeCells(animated _: Bool) { // Improvement: this should simply be an apply snapshot
        for cell in collectionView.visibleCells {
            if let cell = cell as? WalletTokenCell, let walletToken = cell.walletToken {
                let badgeContent = getBadgeContent(accountContext: _account, slug: walletToken.tokenSlug, isStaking: walletToken.isStaking)
                cell.configureBadge(badgeContent: badgeContent)
            }
        }
    }

    private func reconfigureAllRows(animated: Bool) { // Improvement: this should simply be an apply snapshot
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .main))

        DispatchQueue.main.async { [dataSource] in
            dataSource.apply(snapshot, animatingDifferences: animated)
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
                reconfigureAllRows(animated: true)

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
        
        // Token identity:
        private let tokenID: TokenID
        private let accountId: String // for reloading tokens with same slug / staking when account changed
        
        // For UI:
        let animatedAmounts: Bool
        let isLast: Bool
        let isPinned: Bool
        
        init(tokenBalance: MTokenBalance, accountId: String, isPinned: Bool, animatedAmounts: Bool, isLast: Bool) {
            self.tokenBalance = tokenBalance
            self.accountId = accountId
            tokenID = TokenID(slug: tokenBalance.tokenSlug, isStaking: tokenBalance.isStaking)
            self.animatedAmounts = animatedAmounts
            self.isLast = isLast
            self.isPinned = isPinned
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.tokenID == rhs.tokenID && lhs.accountId == rhs.accountId && lhs.isPinned == rhs.isPinned
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(tokenID)
            hasher.combine(accountId)
            hasher.combine(isPinned)
        }
    }
    
    private enum WalletTokensVM {
        case realTokens(tokensToShow: [MTokenBalance], allTokensCount: Int)
        case tokensPlaceholders(count: Int)
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
