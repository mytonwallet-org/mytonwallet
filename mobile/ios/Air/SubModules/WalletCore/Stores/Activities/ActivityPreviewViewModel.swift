import WalletContext

private let previewLog = Log("ActivityPreviewViewModel")

@MainActor
public protocol ActivityPreviewViewModelDelegate: AnyObject, Sendable {
    func activityPreviewViewModelChanged()
}

/// A bounded, count-driven activity source for previews such as Home.
///
/// Unlike `ActivityListViewModel`, this model does not wait for a row to become visible before
/// loading more. It keeps advancing history until `requestedCount` *visible* activities are
/// available, or the store confirms that history is exhausted.
@MainActor
public final class ActivityPreviewViewModel: WalletCoreData.EventsObserver, Sendable {
    public enum LoadState: Equatable, Sendable {
        case loading
        case satisfied
        case exhausted
        case failed
    }

    nonisolated public let accountContext: AccountContext
    nonisolated public let accountId: String

    public private(set) var activityIDs: [String]?
    public private(set) var requestedCount: Int
    public private(set) var loadState: LoadState = .loading
    public private(set) var isEndReached: Bool?
    public weak var delegate: ActivityPreviewViewModelDelegate?

    private var activitiesById: [String: ApiActivity]?
    private var presentation: Presentation?
    private let activitiesStore: _ActivityStore
    private var loadTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private static let pageSize = 60
    private static let retryDelay: Duration = .seconds(10)

    struct Presentation: Equatable {
        struct Row: Equatable {
            let activity: ApiActivity
            let tokens: [ApiToken?]
            let nft: NftPresentation?
        }

        struct NftPresentation: Equatable {
            let nft: ApiNft

            static func == (lhs: Self, rhs: Self) -> Bool {
                let a = lhs.nft
                let b = rhs.nft
                // ApiNft equality compares identity only, including when nested in ApiActivity.
                return a == b
                    && a.index == b.index
                    && a.ownerAddress == b.ownerAddress
                    && a.name == b.name
                    && a.thumbnail == b.thumbnail
                    && a.image == b.image
                    && a.description == b.description
                    && a.collectionName == b.collectionName
                    && a.collectionAddress == b.collectionAddress
                    && a.isOnSale == b.isOnSale
                    && a.isHidden == b.isHidden
                    && a.isOnFragment == b.isOnFragment
                    && a.isTelegramGift == b.isTelegramGift
                    && a.isScam == b.isScam
                    && a.isUnverified == b.isUnverified
                    && a.isNsfw == b.isNsfw
                    && a.metadata == b.metadata
                    && a.interface == b.interface
                    && a.compression == b.compression
            }
        }

        let rows: [Row]?
        let requestedCount: Int
        let baseCurrency: MBaseCurrency?
        let baseCurrencyRate: Double?

        init(
            activityIDs: [String]?,
            activitiesById: [String: ApiActivity]?,
            requestedCount: Int,
            baseCurrency: MBaseCurrency,
            baseCurrencyRate: Double,
            token: (String) -> ApiToken?,
            resolveNft: (ApiNft) -> ApiNft
        ) {
            rows = activityIDs.map { ids in
                ids.prefix(requestedCount).compactMap { id in
                    guard let activity = activitiesById?[id] else { return nil }
                    let tokens: [ApiToken?] = switch activity {
                    case .transaction(let tx): [token(tx.slug)]
                    case .swap(let swap): [token(swap.from), token(swap.to)]
                    }
                    return Row(
                        activity: activity,
                        tokens: tokens,
                        nft: activity.transaction?.nft.map(resolveNft).map { NftPresentation(nft: $0) }
                    )
                }
            }
            self.requestedCount = requestedCount
            self.baseCurrency = rows?.isEmpty == false ? baseCurrency : nil
            self.baseCurrencyRate = rows?.isEmpty == false ? baseCurrencyRate : nil
        }
    }

    public init(
        accountId: String,
        requestedCount: Int,
        delegate: any ActivityPreviewViewModelDelegate
    ) async {
        self.accountContext = AccountContext(accountId: accountId)
        self.accountId = accountId
        self.requestedCount = max(1, requestedCount)
        self.activitiesStore = .shared

        await refreshState(failed: false, notifyDelegate: false)
        self.delegate = delegate
        WalletCoreData.addImmediately(eventObserver: self)
        ensureRequestedCount()
    }

    deinit {
        loadTask?.cancel()
        retryTask?.cancel()
    }

    public func activity(for id: String) -> ApiActivity? {
        activitiesById?[id]
    }

    public func setRequestedCount(_ requestedCount: Int) async {
        let requestedCount = max(1, requestedCount)
        guard self.requestedCount != requestedCount else {
            ensureRequestedCount()
            return
        }
        self.requestedCount = requestedCount
        await refreshState(failed: false)
        ensureRequestedCount()
    }

    public func retryLoading() {
        retryTask?.cancel()
        retryTask = nil
        ensureRequestedCount()
    }

    nonisolated static func resolveLoadState(
        visibleCount: Int?,
        requestedCount: Int,
        isEndReached: Bool?,
        failed: Bool
    ) -> LoadState {
        if failed {
            return .failed
        }
        if visibleCount ?? 0 >= requestedCount {
            return .satisfied
        }
        if isEndReached == true {
            return .exhausted
        }
        return .loading
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .activitiesChanged(let accountId, _, _) where accountId == self.accountId:
            HomeTrace.record("activities.event", "preview=\(ObjectIdentifier(self)) \(event.homeTraceDescription ?? "")")
            refreshAndEnsureRequestedCount()

        case .hideTinyTransfersChanged, .hideUnverifiedNftsChanged, .tokensChanged, .baseCurrencyChanged:
            HomeTrace.record("activities.event", "preview=\(ObjectIdentifier(self)) account=\(accountId) \(event.homeTraceDescription ?? "")")
            refreshAndEnsureRequestedCount()

        case .nftsChanged(let accountId) where accountId == self.accountId:
            HomeTrace.record("activities.event", "preview=\(ObjectIdentifier(self)) \(event.homeTraceDescription ?? "")")
            refreshAndEnsureRequestedCount()

        case .homeActivityVisibleItemsLimitChanged:
            Task { [weak self] in
                await self?.setRequestedCount(AppStorageHelper.homeActivityVisibleItemsLimit.rawValue)
            }

        default:
            break
        }
    }

    private func refreshAndEnsureRequestedCount() {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshState(failed: false)
            self.ensureRequestedCount()
        }
    }

    private func ensureRequestedCount() {
        guard needsMoreActivities, loadTask == nil else { return }
        retryTask?.cancel()
        retryTask = nil
        if loadState != .loading {
            HomeTrace.record("activities.loading", "account=\(accountId) oldState=\(loadState) notify=true")
            loadState = .loading
            delegate?.activityPreviewViewModelChanged()
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadUntilRequestedCountIsSatisfied()
            self.loadTask = nil
        }
    }

    private var needsMoreActivities: Bool {
        activityIDs?.count ?? 0 < requestedCount && isEndReached != true
    }

    private func loadUntilRequestedCountIsSatisfied() async {
        while needsMoreActivities, !Task.isCancelled {
            let stateBeforeFetch = await activitiesStore.getAccountState(accountId)
            let progressBeforeFetch = HistoryProgress(
                count: stateBeforeFetch.idsMain?.count,
                lastID: stateBeforeFetch.idsMain?.last,
                isEndReached: stateBeforeFetch.isMainHistoryEndReached
            )

            do {
                HomeTrace.record("activities.fetch.begin", "account=\(accountId) visible=\(activityIDs?.count ?? -1) requested=\(requestedCount) pageSize=\(Self.pageSize)")
                try await activitiesStore.fetchAllActivities(
                    accountId: accountId,
                    limit: Self.pageSize,
                    shouldLoadWithBudget: false
                )
                HomeTrace.record("activities.fetch.end", "account=\(accountId) success=true")
            } catch {
                guard !Task.isCancelled else { return }
                previewLog.error("load failed accountId=\(accountId, .public) error=\(error, .public)")
                HomeTrace.record("activities.fetch.end", "account=\(accountId) success=false")
                await refreshState(failed: true)
                scheduleRetryIfNeeded()
                return
            }

            guard !Task.isCancelled else { return }
            await refreshState(failed: false)
            guard needsMoreActivities else { return }

            let stateAfterFetch = await activitiesStore.getAccountState(accountId)
            let progressAfterFetch = HistoryProgress(
                count: stateAfterFetch.idsMain?.count,
                lastID: stateAfterFetch.idsMain?.last,
                isEndReached: stateAfterFetch.isMainHistoryEndReached
            )
            guard progressAfterFetch != progressBeforeFetch else {
                HomeTrace.record("activities.noProgress", "account=\(accountId) notify=true")
                previewLog.error("load made no progress accountId=\(accountId, .public)")
                loadState = .failed
                delegate?.activityPreviewViewModelChanged()
                scheduleRetryIfNeeded()
                return
            }
        }
    }

    private func refreshState(failed: Bool, notifyDelegate: Bool = true) async {
        let traceStartedAt = HomeTrace.isEnabled ? HomeTrace.now : 0
        HomeTrace.record("activities.refresh.begin", "preview=\(ObjectIdentifier(self)) account=\(accountId) failed=\(failed) notify=\(notifyDelegate)")
        let accountState = await activitiesStore.getAccountState(accountId)
        let poisoningCache = await activitiesStore.getPoisoningCache(accountId)
        // Compare after the actor hops: another refresh can finish while we await the store.
        let previousIDs = activityIDs
        let previousActivities = HomeTrace.isEnabled ? activitiesById : nil
        let previousState = loadState
        let visibleIDs = ActivityVisibilityFilter.visibleIDs(
            accountState.idsMain,
            activitiesById: accountState.byId,
            accountId: accountId,
            token: nil,
            poisoningCache: poisoningCache,
            hideTinyTransfers: AppStorageHelper.hideTinyTransfers
        )

        activitiesById = accountState.byId
        activityIDs = visibleIDs.map { Array($0.prefix(requestedCount)) }
        isEndReached = accountState.isMainHistoryEndReached
        loadState = Self.resolveLoadState(
            visibleCount: visibleIDs?.count,
            requestedCount: requestedCount,
            isEndReached: accountState.isMainHistoryEndReached,
            failed: failed
        )
        let nextPresentation = Presentation(
            activityIDs: activityIDs,
            activitiesById: activitiesById,
            requestedCount: requestedCount,
            baseCurrency: TokenStore.baseCurrency,
            baseCurrencyRate: TokenStore.baseCurrencyRate,
            token: { TokenStore.getToken(slugOrAddress: $0) },
            resolveNft: { NftStore.nftWithStoredTelegramGiftLottie(accountId: accountId, nft: $0) }
        )
        let presentationChanged = presentation != nextPresentation
        presentation = nextPresentation
        let shouldNotify = notifyDelegate && (presentationChanged || previousState != loadState)

        if HomeTrace.isEnabled {
            let contentChanges = (activityIDs ?? []).filter { previousActivities?[$0] != activitiesById?[$0] }.count
            HomeTrace.record("activities.refresh.end", "preview=\(ObjectIdentifier(self)) account=\(accountId) duration_ms=\(HomeTrace.milliseconds(since: traceStartedAt)) rows=\(previousIDs?.count ?? -1)->\(activityIDs?.count ?? -1) idsChanged=\(previousIDs != activityIDs) contentChanged=\(contentChanges) presentationChanged=\(presentationChanged) state=\(previousState)->\(loadState) notify=\(shouldNotify)")
        }

        if shouldNotify {
            delegate?.activityPreviewViewModelChanged()
        }
    }

    private func scheduleRetryIfNeeded() {
        guard needsMoreActivities, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            self.retryTask = nil
            self.ensureRequestedCount()
        }
    }
}

private struct HistoryProgress: Equatable {
    let count: Int?
    let lastID: String?
    let isEndReached: Bool?
}
