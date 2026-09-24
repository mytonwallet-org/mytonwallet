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

        static func tokenAccountId(_ identifier: String) -> String? {
            guard isToken(identifier) else { return nil }
            return identifier.dropFirst(tokenPrefix.count).split(separator: ":", maxSplits: 1).first.map(String.init)
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
        let presentation: WalletTokenPresentation
        let animatedAmounts: Bool

        var tokenBalance: MTokenBalance { presentation.tokenBalance }
        var isPinned: Bool { presentation.isPinned }
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
    private var state: State = .placeholders(count: 5)
    private var tokenItemsByIdentifier: [String: TokenItem] = [:]
    private var emptyStateAnimationSessionID = 0
    private struct CachedContent {
        let accountId: String
        let presentation: WalletTokenPresentation
        let view: WalletTokenContentView
    }
    private var cachedContent: [String: CachedContent] = [:]
    private var preloadTask: Task<Void, Never>?
    private var cachedAccountOrder: [String] = []

    public func preloadAccounts(_ accountIds: [String], rowWidth: CGFloat, visibleRowCount: Int) {
        preloadTask?.cancel()
        for id in [accountId] + accountIds.prefix(2) {
            cachedAccountOrder.removeAll { $0 == id }
            cachedAccountOrder.append(id)
        }
        cachedAccountOrder = Array(cachedAccountOrder.suffix(3))
        let retainedAccounts = Set(cachedAccountOrder)
        guard rowWidth > 0, visibleRowCount > 0 else { return }
        preloadTask = Task { @MainActor [weak self] in
            // Let the account animation finish before preparing neighboring rows.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.cachedContent = self?.cachedContent.filter { retainedAccounts.contains($0.value.accountId) } ?? [:]
            for accountId in accountIds.prefix(2) {
                guard !Task.isCancelled, let self else { return }
                let context = AccountContext(source: .accountId(accountId))
                let balances = context.walletTokensData?.orderedTokenBalances ?? []
                let items = Self.makeTokenItems(balances, accountContext: context, animated: false)
                for item in items.prefix(visibleRowCount) {
                    guard !Task.isCancelled else { return }
                    let identifier = ItemIdentifier.token(accountId: accountId, tokenID: item.tokenBalance.tokenID)
                    if cachedContent[identifier]?.presentation == item.presentation { continue }
                    let content = self.content(for: item, identifier: identifier, accountId: accountId, host: nil)
                    if content.superview == nil {
                        content.frame = CGRect(x: 0, y: 0, width: rowWidth, height: WalletTokenCell.defaultHeight)
                        content.layoutIfNeeded()
                    }
                    // Bound preparation to one row per run-loop interval.
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        }
    }

    public func cancelPreloading() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    public func discardPreparedContent() {
        cancelPreloading()
        cachedContent.removeAll()
        cachedAccountOrder.removeAll()
    }

    isolated deinit { preloadTask?.cancel() }

    // A bounded set of pools preserves warm hosts. An item's registration must stay
    // stable when UIKit reconfigures it, including after moves or an account switch.
    private lazy var tokenRegistrations = (0..<(3 * HomeWalletVisibleTokensLimit.top30.rawValue)).map { _ in
        UICollectionView.CellRegistration<WalletTokenCell, String> { [weak self] cell, _, identifier in
            guard let self, let accountId = ItemIdentifier.tokenAccountId(identifier),
                  let item = tokenItem(for: identifier, accountId: accountId) else {
                cell.setContextMenuInteraction(nil)
                return
            }
            configureTokenCell(cell, item: item, identifier: identifier, accountId: accountId)
        }
    }

    private func tokenItem(for identifier: String, accountId: String) -> TokenItem? {
        if let item = tokenItemsByIdentifier[identifier] { return item }
        if let cached = cachedContent[identifier] {
            return TokenItem(presentation: cached.presentation, animatedAmounts: false)
        }
        // The displayed snapshot can still request outgoing/prefetched rows while
        // Home has already prepared the next account or a shorter token list.
        let context = AccountContext(source: .accountId(accountId))
        guard let balance = context.walletTokensData?.orderedTokenBalances.first(where: {
            ItemIdentifier.token(accountId: accountId, tokenID: $0.tokenID) == identifier
        }) else { return nil }
        return Self.makeTokenItems([balance], accountContext: context, animated: false).first
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

    public func switchAccountTo(_ accountId: String) {
        guard displayedAccountId != accountId else { return }
        displayedAccountId = accountId
        accountContext.accountId = accountId
        // Home owns the replacement animation; individual amounts stay still underneath it.
        refresh(animated: false, notify: false)
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
        _ = tokenRegistrations
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
                using: tokenRegistrations[Int(UInt(bitPattern: itemIdentifier.hashValue) % UInt(tokenRegistrations.count))],
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
            let reason = HomeTrace.isEnabled ? event.homeTraceDescription ?? "other" : ""
            switch event {
            case .stakingAccountData(let data):
                if data.accountId == accountId {
                    refresh(animated: true, reason: reason)
                }
            case .tokensChanged, .baseCurrencyChanged, .assetsAndActivityDataUpdated, .homeWalletVisibleTokensLimitChanged:
                refresh(animated: true, reason: reason)
            case .accountChanged(let accountId, _):
                if accountId == self.accountId {
                    refresh(animated: true, reason: reason)
                }
            case .balanceChanged(let accountId):
                if accountId == self.accountId {
                    refresh(animated: true, reason: reason)
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

    private func refresh(animated: Bool, notify: Bool = true, reason: String = #function) {
        let previousItemIdentifiers = itemIdentifiers
        let traceStartedAt = HomeTrace.isEnabled ? HomeTrace.now : 0
        let previousTokenItems = tokenItemsByIdentifier
        let previousCount = allTokensCount
        HomeTrace.record("tokens.refresh.begin", "account=\(accountId) reason=\(reason) notify=\(notify) animated=\(animated)")
        defer {
            itemIdentifiers = makeItemIdentifiers()
            let retainedIdentifiers = Set(itemIdentifiers)
            cachedContent = cachedContent.filter { $0.value.accountId != accountId || retainedIdentifiers.contains($0.key) }
            let structureChanged = previousItemIdentifiers != itemIdentifiers
            let presentationChanges = tokenItemsByIdentifier.filter {
                previousTokenItems[$0.key]?.presentation != $0.value.presentation
            }.count
            let shouldNotify = notify && (structureChanged || presentationChanges > 0 || previousCount != allTokensCount)
            if HomeTrace.isEnabled {
                let balanceOrPriceChanges = tokenItemsByIdentifier.filter {
                    previousTokenItems[$0.key]?.tokenBalance != $0.value.tokenBalance
                }.count
                let pinChanges = tokenItemsByIdentifier.filter {
                    previousTokenItems[$0.key]?.isPinned != $0.value.isPinned
                }.count
                HomeTrace.record("tokens.refresh.end", "account=\(accountId) reason=\(reason) duration_ms=\(HomeTrace.milliseconds(since: traceStartedAt)) rows=\(itemIdentifiers.count) structureChanged=\(structureChanged) balanceOrPriceChanged=\(balanceOrPriceChanges) pinChanged=\(pinChanges) presentationChanged=\(presentationChanges) total=\(previousCount)->\(allTokensCount) notify=\(shouldNotify)")
            }
            if shouldNotify {
                onStateChange?(structureChanged, animated)
            }
        }
        tokenItemsByIdentifier.removeAll(keepingCapacity: true)

        guard let walletTokensData = accountContext.walletTokensData else {
            state = .placeholders(count: 5)
            return
        }

        let orderedTokens = walletTokensData.orderedTokenBalances
        guard !orderedTokens.isEmpty else {
            state = .empty
            return
        }

        let items = Self.makeTokenItems(orderedTokens, accountContext: accountContext, animated: animated)
        tokenItemsByIdentifier = Dictionary(uniqueKeysWithValues: items.map { item in
            (ItemIdentifier.token(accountId: accountId, tokenID: item.tokenBalance.tokenID), item)
        })
        state = .loaded(items: items, allTokensCount: orderedTokens.count)
    }

    private static func makeTokenItems(_ orderedTokens: [MTokenBalance], accountContext: AccountContext, animated: Bool) -> [TokenItem] {
        let visibleTokens = orderedTokens.prefix(AppStorageHelper.homeWalletVisibleTokensLimit.rawValue)
        let assetsData = AssetsAndActivityDataStore.data(accountId: accountContext.accountId) ?? .empty
        return visibleTokens.map { tokenBalance in
            let isPinned: Bool
            if case .pinned = assetsData.isTokenPinned(
                slug: tokenBalance.tokenSlug,
                isStaked: tokenBalance.isStaking
            ) {
                isPinned = true
            } else {
                isPinned = false
            }
            let stakingPresentation = accountContext.getStakingTokenPresentation(
                tokenSlug: tokenBalance.tokenSlug,
                isStaking: tokenBalance.isStaking
            )
            let presentation = WalletTokenPresentation(
                tokenBalance: tokenBalance,
                token: tokenBalance.token,
                badgeContent: getBadgeContent(
                    accountContext: accountContext,
                    slug: tokenBalance.tokenSlug,
                    stakingBadge: stakingPresentation?.badge
                ),
                stakingAccessory: stakingPresentation?.accessory,
                isMultichain: accountContext.account.isMultichain,
                isPinned: isPinned,
                baseCurrency: TokenStore.baseCurrency,
                baseCurrencyRate: TokenStore.baseCurrencyRate,
                accentColor: accountContext.accentColor
            )
            return TokenItem(presentation: presentation, animatedAmounts: animated)
        }
    }

    private func content(for item: TokenItem, identifier: String, accountId: String, host: UIView?,
                         existing: WalletTokenContentView? = nil) -> WalletTokenContentView {
        let cached = cachedContent[identifier]
        // Preloading must not replace an unchanged view that UIKit retains in its reuse pool.
        if host == nil, let cached, cached.presentation == item.presentation { return cached.view }
        // Offscreen and prefetched cells still own their content until reuse.
        let owned = existing.flatMap { $0.preparedItemIdentifier == identifier && $0.superview === host ? $0 : nil }
        let available = cached.flatMap { $0.view.superview == nil || $0.view.superview === host ? $0.view : nil }
        let reusable = owned ?? available
        let content = reusable ?? WalletTokenContentView(frame: .zero)
        #if DEBUG || HOME_FRAME_PROBE
        HomeFrameProbe.shared.event(reusable != nil ? "token.content.reuse" : "token.content.create")
        #endif
        if content.preparedPresentation != item.presentation {
            content.tintColor = item.presentation.accentColor
            content.configure(
                with: item.tokenBalance,
                animated: item.animatedAmounts && content.superview === host && host != nil,
                badgeContent: item.presentation.badgeContent,
                stakingAccessoryContent: item.presentation.stakingAccessory,
                isMultichain: item.presentation.isMultichain,
                isPinned: item.isPinned
            )
            content.preparedPresentation = item.presentation
        }
        content.preparedItemIdentifier = identifier
        cachedContent[identifier] = CachedContent(accountId: accountId, presentation: item.presentation, view: content)
        return content
    }

    private func configureTokenCell(_ cell: WalletTokenCell, item: TokenItem, identifier: String, accountId: String) {
        let token = item.tokenBalance
        cell.baseBackgroundColor = .air.groupedItem
        cell.host(content(for: item, identifier: identifier, accountId: accountId, host: cell.contentView,
                          existing: cell.tokenContent))

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
