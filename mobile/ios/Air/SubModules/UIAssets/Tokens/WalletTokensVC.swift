
import Dependencies
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let log = Log("WalletTokens")

public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, UITableViewDelegate, Sendable, WSegmentedControllerContent {
    @AccountContext private var account: MAccount

    private let layoutMode: LayoutMode
    
    private let tableView: UITableView = UITableView(frame: .zero, style: .plain)
    private lazy var dataSource: TableViewDataSource = makeDataSource()
    private var currentHeight: CGFloat = WalletTokenCell.defaultHeight * 4
    private var pendingInteractiveSwitchAccountId: String?

    public var onHeightChanged: ((_ animated: Bool) -> Void)?

    public var visibleCells: [UITableViewCell] {
        tableView.visibleCells
    }

    public var calculatedHeight: CGFloat {
        currentHeight
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
        updateWalletTokens(animated: false)
        WalletCoreData.add(eventObserver: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onHeightChanged?(false)
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear

        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes

        if layoutMode.isCompact {
            tableView.bounces = false
            tableView.isScrollEnabled = false
        }

        tableView.register(layoutMode.isCompact ? WalletTokenCell.self : AssetsWalletTokenCell.self, forCellReuseIdentifier: "WalletToken")
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "Placeholder")
        tableView.register(WalletSeeAllCell.self, forCellReuseIdentifier: "SeeAll")

        view.addStretchedToBounds(subview: tableView)
    }

    private func makeDataSource() -> TableViewDataSource {
        let dataSource = TableViewDataSource(tableView: tableView) { [unowned self] tableView, indexPath, item in
            switch item {
            case let .token(item):
                let cell = tableView.dequeueReusableCell(withIdentifier: "WalletToken", for: indexPath) as! WalletTokenCell
                let account = self.account
                let token = item.tokenBalance
                let badgeContent = getBadgeContent(accountContext: _account, slug: token.tokenSlug, isStaking: token.isStaking)

                // when opened on full screen, background is highlighted for pinned cells
                let highlightBackgroundWhenPinned = !layoutMode.isCompact
                // add color under navBar area for being coherent with color of pinned cells
                let showUnderNavbarPinningColor = indexPath.row == 0 && item.isPinned && highlightBackgroundWhenPinned
                cell.underNavigationBarColorView.isVisible = showUnderNavbarPinningColor

                cell.configure(with: item.tokenBalance,
                               isLast: item.isLast,
                               animated: item.animatedAmounts,
                               badgeContent: badgeContent,
                               isMultichain: account.isMultichain,
                               isPinned: item.isPinned,
                               highlightBackgroundWhenPinned: highlightBackgroundWhenPinned,
                               onSelect: { [weak self] in
                                   self?.didSelectToken(token)
                               })
                return cell

            case .placeholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Placeholder", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell

            case .seeAll:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SeeAll", for: indexPath) as! WalletSeeAllCell
                cell.configure(onTap: { [weak self] in self?.didSelectSeeAll() })
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
        
        return dataSource
    }

    private func applySnapshot(animatedAmounts: Bool, walletTokensVM: WalletTokensVM) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let accountId = account.id
        let assetsAndActivityData = AccountStore.assetsAndActivityData(forAccountID: accountId) ?? .empty

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
                snapshot.appendItems([.seeAll])
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
        if let data = $account.balanceData {
            let assetsData = AccountStore.assetsAndActivityData(forAccountID: account.id) ?? .empty
            let tokenBalances = data.walletStaked + data.walletTokens
            let sorted = MTokenBalance.sortedForUI(tokenBalances: tokenBalances, assetsAndActivityData: assetsData)

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
        for cell in tableView.visibleCells {
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

    public func switchAcccountTo(accountId: String, animated: Bool) {
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

            case .balanceChanged(let accountId, _):
                if accountId == self.account.id {
                    updateWalletTokens(animated: true)
                }

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
        AppActions.showEarn(tokenSlug: stakingBaseSlug(for: slug))
    }

    private func showEarnForToken(slug: String, isStaking: Bool) {
        if isStaking {
            goToStakedPage(slug: slug)
        } else {
            AppActions.showEarn(tokenSlug: slug)
        }
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
                        AppActions.showReceive(chain: token.chain, title: nil)
                    })
                }
                primaryActions.append(UIAction(title: lang("Send"), image: UIImage(systemName: "arrow.up")) { _ in
                    AppActions.showSend(prefilledValues: .init(token: token.slug))
                })
                if isSwapAvailable {
                    primaryActions.append(UIAction(title: lang("Swap"), image: UIImage(systemName: "arrow.left.arrow.right")) { _ in
                        let defaultBuying = token.slug == TONCOIN_SLUG ? nil : TONCOIN_SLUG
                        AppActions.showSwap(defaultSellingToken: token.slug,
                                            defaultBuyingToken: defaultBuying,
                                            defaultSellingAmount: nil,
                                            push: nil)
                    })
                }
                if isStakingAvailable {
                    primaryActions.append(UIAction(title: lang("Stake"), image: UIImage(systemName: "cylinder.split.1x2")) { _ in
                        AppActions.showEarn(tokenSlug: token.slug)
                    })
                }
            }
        }

        let assetsAndActivityData = AccountStore.assetsAndActivityData(forAccountID: accountID) ?? .empty
        switch assetsAndActivityData.isTokenPinned(slug: walletToken.tokenSlug, isStaked: walletToken.isStaking) {
        case .pinned:
            secondaryActions.append(UIAction(title: lang("Unpin"), image: UIImage(systemName: "pin.slash")) { _ in
                AccountStore.updateAssetsAndActivityData(forAccountID: accountID, update: { settings in
                    settings.saveTokenPinning(slug: walletToken.tokenSlug, isStaking: walletToken.isStaking, isPinned: false)
                })
            })
        case .notPinned:
            secondaryActions.append(UIAction(title: lang("Pin"), image: UIImage(systemName: "pin")) { _ in
                AccountStore.updateAssetsAndActivityData(forAccountID: accountID, update: { settings in
                    settings.saveTokenPinning(slug: walletToken.tokenSlug, isStaking: walletToken.isStaking, isPinned: true)
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

    // MARK: - UITableViewDelegate

    public func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            Log.shared.error("Not found item for indexPath: \(indexPath)")
            return 0
        }
        return item.defaultHeight
    }

    public func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
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

    public var scrollingView: UIScrollView? { tableView }
}

// MARK: - WalletSeeAllCell.Delegate

extension WalletTokensVC {
    private func didSelectSeeAll() {
        AppActions.showAssets(accountSource: $account.source, selectedTab: 0, collectionsFilter: .none)
    }
}

// MARK: - Diffable Data Source Types

extension WalletTokensVC {
    private typealias TableViewDataSource = UITableViewDiffableDataSource<Section, Item>
    
    private enum Section: Hashable {
        case main
        case seeAll
    }
    
    private enum Item: Hashable {
        case token(item: TokenBalanceItem)
        case placeholder(Int)
        case seeAll
        
        var defaultHeight: CGFloat {
            switch self {
            case .token: WalletTokenCell.defaultHeight
            case .placeholder: WalletTokenCell.defaultHeight
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
            case .compact: 5
            case .compactLarge: 6
            }
        }
    }
}
    
// MARK: - iPad fixup

//final class _NoInsetsTableView: UITableView {
//    override var safeAreaInsets: UIEdgeInsets { .zero }
//}
