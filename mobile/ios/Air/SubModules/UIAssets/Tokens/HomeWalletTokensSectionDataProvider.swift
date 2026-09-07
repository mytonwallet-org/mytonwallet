import ContextMenuKit
import Perception
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let homeWalletTokenContextMenuCornerRadius: CGFloat = 26

@MainActor
public final class HomeWalletTokensSectionDataProvider: ActivityListViewController.CustomSectionDataProvider, WalletCoreData.EventsObserver {
    private enum ItemIdentifier {
        static let tokenPrefix = "token:"
        static let placeholderPrefix = "placeholder:"
        static let emptyPrefix = "empty:"
        static let showAllPrefix = "show-all:"

        static func token(accountId: String, tokenID: TokenID) -> String {
            tokenPrefix + accountId + ":" + (tokenID.isStaking ? "staking:" : "wallet:") + tokenID.slug
        }

        static func placeholder(accountId: String, index: Int) -> String {
            placeholderPrefix + accountId + ":" + String(index)
        }

        static func empty(accountId: String) -> String {
            emptyPrefix + accountId
        }

        static func showAll(accountId: String) -> String {
            showAllPrefix + accountId
        }

        static func isToken(_ identifier: String) -> Bool {
            identifier.hasPrefix(tokenPrefix)
        }

        static func isPlaceholder(_ identifier: String) -> Bool {
            identifier.hasPrefix(placeholderPrefix)
        }

        static func isEmpty(_ identifier: String) -> Bool {
            identifier.hasPrefix(emptyPrefix)
        }

        static func isShowAll(_ identifier: String) -> Bool {
            identifier.hasPrefix(showAllPrefix)
        }
    }

    private struct TokenItem {
        let tokenBalance: MTokenBalance
        let isPinned: Bool
        let animatedAmounts: Bool
    }

    private enum State {
        case placeholders(count: Int)
        case empty
        case loaded(items: [TokenItem], allTokensCount: Int)
    }

    public var menuProvider: (() -> UIMenu?)?

    public let id: String
    public var onStateChange: ((_ hasStructuralChanges: Bool, _ animated: Bool) -> Void)?
    public private(set) var itemIdentifiers: [String] = []

    public var accountId: String { accountContext.accountId }

    private let accountContext: AccountContext
    private lazy var tokenActions = WalletTokenActions(accountContext: accountContext, isInModal: false)
    private var state: State = .placeholders(count: 4)
    private var tokenItemsByIdentifier: [String: TokenItem] = [:]
    private var emptyStateAnimationSessionID = 0

    private lazy var tokenRegistration = UICollectionView.CellRegistration<WalletTokenCell, String> { [weak self] cell, _, itemIdentifier in
        guard let self, let item = tokenItemsByIdentifier[itemIdentifier] else {
            cell.setContextMenuInteraction(nil)
            return
        }
        configureTokenCell(cell, item: item)
    }

    private lazy var placeholderRegistration = UICollectionView.CellRegistration<ActivitySkeletonCollectionCell, String> { cell, _, _ in
        cell.configure()
    }

    private lazy var emptyRegistration = UICollectionView.CellRegistration<WalletAssetsEmptyCell, String> { cell, _, _ in
        cell.configure(
            animationName: "duck_no-data",
            title: lang("No tokens yet"),
            description: lang("$no_tokens_description"),
            actionTitle: lang("Add Tokens"),
            height: WalletAssetsEmptyCell.tokensHeight,
            descriptionNumberOfLines: 4,
            onAction: {
                AppActions.showAssetsAndActivity()
            }
        )
    }

    private lazy var showAllRegistration = UICollectionView.CellRegistration<WalletSeeAllCell, String> { [weak self] cell, _, _ in
        guard let self else { return }
        cell.baseBackgroundColor = .air.groupedItem
        cell.configure(tokensCount: allTokensCount, menu: menuProvider?())
        cell.configurationUpdateHandler = { showAllCell, state in
            showAllCell.isHighlighted = state.isHighlighted
        }
    }

    public init(id: String = "tokens", accountSource: AccountSource) {
        self.id = id
        self.accountContext = AccountContext(source: accountSource)
        self.displayedAccountId = accountContext.accountId
        refresh(animated: false, notify: false)
        WalletCoreData.add(eventObserver: self)
        observeAccountId()
    }

    private var displayedAccountId: String

    private func observeAccountId() {
        withPerceptionTracking {
            _ = accountContext.accountId
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.accountIdChanged()
                self?.observeAccountId()
            }
        }
    }

    private func accountIdChanged() {
        guard accountContext.accountId != displayedAccountId else { return }
        displayedAccountId = accountContext.accountId
        refresh(animated: true)
    }

    private func makeItemIdentifiers() -> [String] {
        let identifiers: [String] = switch state {
        case .placeholders(let count):
            (0..<count).map { ItemIdentifier.placeholder(accountId: accountId, index: $0) }
        case .empty:
            [ItemIdentifier.empty(accountId: accountId)]
        case .loaded(let items, _):
            items.map {
                ItemIdentifier.token(accountId: accountId, tokenID: $0.tokenBalance.tokenID)
            }
        }
        return identifiers + [ItemIdentifier.showAll(accountId: accountId)]
    }

    public func prepareForUse() {
        _ = tokenRegistration
        _ = placeholderRegistration
        _ = emptyRegistration
        _ = showAllRegistration
    }

    public func makeLayoutSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .none
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
        if !IOS_26_MODE_ENABLED {
            configuration.separatorConfiguration.color = .air.separator
        }
        configuration.itemSeparatorHandler = { [weak self] indexPath, separatorConfiguration in
            guard let self else { return separatorConfiguration }
            var separatorConfiguration = separatorConfiguration
            let identifiers = itemIdentifiers
            let item = identifiers.indices.contains(indexPath.item) ? identifiers[indexPath.item] : nil
            let nextItem = identifiers.indices.contains(indexPath.item + 1) ? identifiers[indexPath.item + 1] : nil
            if item.map(ItemIdentifier.isShowAll) == true {
                separatorConfiguration.topSeparatorVisibility = .hidden
                separatorConfiguration.bottomSeparatorVisibility = .hidden
            } else if nextItem.map(ItemIdentifier.isShowAll) == true {
                separatorConfiguration.bottomSeparatorVisibility = .hidden
            }
            return separatorConfiguration
        }
        return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
    }

    public func dequeueCell(
        _ collectionView: UICollectionView,
        _ indexPath: IndexPath,
        itemIdentifier: String
    ) -> UICollectionViewCell {
        if ItemIdentifier.isToken(itemIdentifier) {
            return collectionView.dequeueConfiguredReusableCell(
                using: tokenRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        if ItemIdentifier.isPlaceholder(itemIdentifier) {
            return collectionView.dequeueConfiguredReusableCell(
                using: placeholderRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        if ItemIdentifier.isEmpty(itemIdentifier) {
            return collectionView.dequeueConfiguredReusableCell(
                using: emptyRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        if ItemIdentifier.isShowAll(itemIdentifier) {
            return collectionView.dequeueConfiguredReusableCell(
                using: showAllRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
        assertionFailure("Unknown Home token item identifier: \(itemIdentifier)")
        return collectionView.dequeueConfiguredReusableCell(
            using: placeholderRegistration,
            for: indexPath,
            item: itemIdentifier
        )
    }

    public func shouldSelect(itemIdentifier: String) -> Bool {
        ItemIdentifier.isToken(itemIdentifier) || ItemIdentifier.isShowAll(itemIdentifier)
    }

    public func didSelect(itemIdentifier: String) {
        if let item = tokenItemsByIdentifier[itemIdentifier] {
            tokenActions.open(item.tokenBalance)
        } else if ItemIdentifier.isShowAll(itemIdentifier) {
            AppActions.showAssets(
                accountSource: accountContext.source,
                selectedTab: .tokens,
                collectionsFilter: .none,
                initialPosition: lastDisplayedTokenID.map(AssetListInitialPosition.token)
            )
        }
    }

    public func willDisplay(_ cell: UICollectionViewCell, itemIdentifier: String) {
        guard ItemIdentifier.isEmpty(itemIdentifier), let cell = cell as? WalletAssetsEmptyCell else { return }
        emptyStateAnimationSessionID += 1
        cell.updateAnimationPlayback(isPlaying: true, playbackSessionID: emptyStateAnimationSessionID)
    }

    public func didEndDisplaying(_ cell: UICollectionViewCell, itemIdentifier: String) {
        guard ItemIdentifier.isEmpty(itemIdentifier), let cell = cell as? WalletAssetsEmptyCell else { return }
        cell.pauseAnimation()
    }

    public nonisolated func walletCore(event: WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .stakingAccountData(let data):
                if data.accountId == accountId {
                    refresh(animated: true)
                }
            case .tokensChanged, .assetsAndActivityDataUpdated, .homeWalletVisibleTokensLimitChanged:
                refresh(animated: true)
            case .accountChanged(let accountId, _):
                if accountId == self.accountId {
                    refresh(animated: true)
                }
            case .balanceChanged(let accountId):
                if accountId == self.accountId {
                    refresh(animated: true)
                }
            default:
                break
            }
        }
    }

    private var allTokensCount: Int {
        if case .loaded(_, let allTokensCount) = state {
            allTokensCount
        } else {
            0
        }
    }

    private var lastDisplayedTokenID: TokenID? {
        guard case .loaded(let items, _) = state else { return nil }
        return items.last?.tokenBalance.tokenID
    }

    private func refresh(animated: Bool, notify: Bool = true) {
        let previousItemIdentifiers = itemIdentifiers
        tokenItemsByIdentifier.removeAll(keepingCapacity: true)

        guard let walletTokensData = accountContext.walletTokensData else {
            state = .placeholders(count: 4)
            finishRefresh(previousItemIdentifiers: previousItemIdentifiers, animated: animated, notify: notify)
            return
        }

        let orderedTokens = walletTokensData.orderedTokenBalances
        guard !orderedTokens.isEmpty else {
            state = .empty
            finishRefresh(previousItemIdentifiers: previousItemIdentifiers, animated: animated, notify: notify)
            return
        }

        let visibleTokens = Array(orderedTokens.prefix(AppStorageHelper.homeWalletVisibleTokensLimit.rawValue))
        let assetsData = AssetsAndActivityDataStore.data(accountId: accountId) ?? .empty
        let items = visibleTokens.map { tokenBalance in
            let isPinned: Bool
            if case .pinned = assetsData.isTokenPinned(
                slug: tokenBalance.tokenSlug,
                isStaked: tokenBalance.isStaking
            ) {
                isPinned = true
            } else {
                isPinned = false
            }
            return TokenItem(
                tokenBalance: tokenBalance,
                isPinned: isPinned,
                animatedAmounts: animated
            )
        }
        tokenItemsByIdentifier = Dictionary(uniqueKeysWithValues: items.map { item in
            (
                ItemIdentifier.token(accountId: accountId, tokenID: item.tokenBalance.tokenID),
                item
            )
        })
        state = .loaded(items: items, allTokensCount: orderedTokens.count)
        finishRefresh(previousItemIdentifiers: previousItemIdentifiers, animated: animated, notify: notify)
    }

    private func finishRefresh(
        previousItemIdentifiers: [String],
        animated: Bool,
        notify: Bool
    ) {
        itemIdentifiers = makeItemIdentifiers()
        if notify {
            onStateChange?(previousItemIdentifiers != itemIdentifiers, animated)
        }
    }

    private func configureTokenCell(_ cell: WalletTokenCell, item: TokenItem) {
        let token = item.tokenBalance
        let stakingPresentation = accountContext.getStakingTokenPresentation(
            tokenSlug: token.tokenSlug,
            isStaking: token.isStaking
        )
        let badgeContent = getBadgeContent(
            accountContext: accountContext,
            slug: token.tokenSlug,
            stakingBadge: stakingPresentation?.badge
        )
        cell.baseBackgroundColor = .air.groupedItem
        cell.configure(
            with: token,
            animated: item.animatedAmounts,
            badgeContent: badgeContent,
            stakingAccessoryContent: stakingPresentation?.accessory,
            isMultichain: accountContext.account.isMultichain,
            isPinned: item.isPinned
        )

        let interaction = ContextMenuInteraction(
            triggers: [.longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: homeWalletTokenContextMenuCornerRadius)
            ),
            pressAnimation: .default(transformMode: .sublayerTransform)
        ) { [weak self, walletToken = token] _ in
            self?.tokenActions.makeContextMenuConfiguration(walletToken: walletToken)
        }
        cell.setContextMenuInteraction(interaction)
        cell.configurationUpdateHandler = { tokenCell, state in
            tokenCell.isHighlighted = state.isHighlighted
        }
    }

}
