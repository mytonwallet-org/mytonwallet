
import ContextMenuKit
import Dependencies
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let contextMenuSourceCornerRadius: CGFloat = 26

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
    private var pendingScrollTokenID: TokenID?

    public var showAllMenuProvider: (() -> UIMenu?)?

    public var onHeightChanged: ((_ animated: Bool) -> Void)?
    private lazy var tokenActions = WalletTokenActions(
        accountContext: $account,
        isInModal: !layoutMode.isCompact
    )

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

    public init(
        accountSource: AccountSource,
        mode: LayoutMode,
        initialTokenID: TokenID? = nil
    ) {
        self._account = AccountContext(source: accountSource)
        self.layoutMode = mode
        self.pendingScrollTokenID = initialTokenID
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
            cell.configure(tokensCount: tokensCount, menu: account.isTemporaryView ? nil : showAllMenuProvider?())
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
        let stakingPresentation = $account.getStakingTokenPresentation(
            tokenSlug: token.tokenSlug,
            isStaking: token.isStaking
        )
        let badgeContent = getBadgeContent(
            accountContext: _account,
            slug: token.tokenSlug,
            stakingBadge: stakingPresentation?.badge
        )
        cell.baseBackgroundColor = layoutMode.containerBackgroundColor

        cell.configure(with: item.tokenBalance,
                       animated: item.animatedAmounts,
                       badgeContent: badgeContent,
                       stakingAccessoryContent: stakingPresentation?.accessory,
                       isMultichain: account.isMultichain,
                       isPinned: item.isPinned)

        let interaction = ContextMenuInteraction(
            triggers: [.longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: contextMenuSourceCornerRadius)
            ),
            pressAnimation: .default(transformMode: .sublayerTransform)
        ) { [weak self, walletToken = item.tokenBalance] _ in
            self?.tokenActions.makeContextMenuConfiguration(walletToken: walletToken)
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

        if layoutMode.isCompact {
            let allTokensCount: Int = switch walletTokensViewState {
            case .loaded(_, let count): count
            case .empty, .placeholders: 0
            }
            snapshot.appendSections([.seeAll])
            snapshot.appendItems([.seeAll(tokensCount: allTokensCount)])
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
        dataSource.apply(snapshot, animatingDifferences: animatedAmounts) { [weak self] in
            self?.applyPendingScrollPosition(animated: false)
        }
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
        let orderedTokens = walletTokensData.orderedTokenBalances
        if orderedTokens.isEmpty {
            return .empty
        }
        let visibleTokens = makeVisibleTokens(from: orderedTokens)
        let pinnedTokenIDs = Set(orderedTokens.compactMap { tokenBalance in
            if case .pinned = assetsData.isTokenPinned(
                slug: tokenBalance.tokenSlug,
                isStaked: tokenBalance.isStaking
            ) {
                tokenBalance.tokenID
            } else {
                nil
            }
        })
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

    private func refreshVisibleStakingPresentations() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? WalletTokenCell, let walletToken = cell.walletToken {
                let stakingPresentation = $account.getStakingTokenPresentation(
                    tokenSlug: walletToken.tokenSlug,
                    isStaking: walletToken.isStaking
                )
                let badgeContent = getBadgeContent(
                    accountContext: _account,
                    slug: walletToken.tokenSlug,
                    stakingBadge: stakingPresentation?.badge
                )
                cell.configureStakingPresentation(
                    badgeContent: badgeContent,
                    accessoryContent: stakingPresentation?.accessory
                )
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
                    refreshVisibleStakingPresentations()
                }

            case .stakingAccountData(let data):
                if data.accountId == self.account.id {
                    refreshVisibleStakingPresentations()
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
            tokenActions.open(item.tokenBalance)
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

    public func scrollToToken(_ tokenID: TokenID, animated: Bool) {
        loadViewIfNeeded()
        pendingScrollTokenID = tokenID
        applyPendingScrollPosition(animated: animated)
    }

    private func applyPendingScrollPosition(animated: Bool) {
        guard let pendingScrollTokenID else { return }
        let item = dataSource.snapshot().itemIdentifiers.first { item in
            guard case .token(let tokenItem) = item else { return false }
            return tokenItem.tokenBalance.tokenID == pendingScrollTokenID
        }
        guard let item, let indexPath = dataSource.indexPath(for: item) else { return }
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        self.pendingScrollTokenID = nil
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
        let lastDisplayedTokenID = dataSource.snapshot().itemIdentifiers.reversed().compactMap { item -> TokenID? in
            guard case .token(let tokenItem) = item else { return nil }
            return tokenItem.tokenBalance.tokenID
        }.first
        AppActions.showAssets(
            accountSource: $account.source,
            selectedTab: .tokens,
            collectionsFilter: .none,
            initialPosition: lastDisplayedTokenID.map(AssetListInitialPosition.token)
        )
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
