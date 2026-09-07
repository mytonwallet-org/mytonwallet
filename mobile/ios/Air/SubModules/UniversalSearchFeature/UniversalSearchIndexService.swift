@preconcurrency import Combine
import Foundation
import UIAgent
import UIInAppBrowser
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletContext
import WalletCore

private let indexServiceLog = Log("UniversalSearchIndexService")

struct UniversalSearchIndexUpdate: Sendable {
    enum Kind: Sendable {
        case contextChanged
        case source(UniversalSearchRefreshProgress)
        case completed(UniversalSearchRefreshResult)
    }

    let context: UniversalSearchContext
    let kind: Kind
}

@MainActor
protocol UniversalSearchIndexServiceObserver: AnyObject {
    func universalSearchIndexService(
        _ service: UniversalSearchIndexService,
        didUpdate update: UniversalSearchIndexUpdate
    )
}

/// Keeps the local search corpus current for the lifetime of the app process.
///
/// The service owns WalletCore observation and refresh coalescing. Search UI is
/// only an observer and may be created or destroyed without affecting indexing.
@MainActor
public final class UniversalSearchIndexService: WalletCoreData.EventsObserver, @unchecked Sendable {
    public typealias ContextProvider = @MainActor @Sendable () -> UniversalSearchContext

    public struct RefreshTiming: Sendable {
        /// Trailing-edge debounce: every new invalidation restarts the wait, so a burst — account
        /// switching, polling updates — collapses into one refresh after events pause
        public var debounce: Duration
        /// Upper bound on how long consecutive invalidations can keep postponing a refresh
        public var maxPostpone: Duration
        /// Pause between consecutive refreshes while invalidations keep arriving mid-refresh
        public var loopPacing: Duration

        public init(
            debounce: Duration = .milliseconds(300),
            maxPostpone: Duration = .seconds(2),
            loopPacing: Duration = .milliseconds(500)
        ) {
            self.debounce = debounce
            self.maxPostpone = maxPostpone
            self.loopPacing = loopPacing
        }
    }

    public let coordinator: UniversalSearchCoordinator

    private let contextProvider: ContextProvider
    private let timing: RefreshTiming
    private var observers: [WeakObserver] = []
    private var hydrationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshLoopGeneration: UInt64 = 0
    private var isRefreshLoopRunning = false
    private var pendingRefreshSourceIDs = Set<SearchSourceID>()
    private var pendingFullRefresh = false
    private var pendingRefreshSince: ContinuousClock.Instant?
    private var isStarted = false
    private var isWalletReady = false
    private var browserHistoryLoadedCancellable: AnyCancellable?
    private var agentConversationChangedCancellable: AnyCancellable?

    init(
        coordinator: UniversalSearchCoordinator,
        contextProvider: @escaping ContextProvider = {
            WalletCoreUniversalSearchFactory.currentContext()
        },
        timing: RefreshTiming = RefreshTiming()
    ) {
        self.coordinator = coordinator
        self.contextProvider = contextProvider
        self.timing = timing
    }

    deinit {
        hydrationTask?.cancel()
        refreshTask?.cancel()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        WalletCoreData.addImmediately(eventObserver: self)
        browserHistoryLoadedCancellable = BrowserHistoryStore.shared.onChanged.sink { [weak self] in
            self?.scheduleRefresh(sourceIDs: [UniversalSearchBrowserHistorySource.id])
        }
        agentConversationChangedCancellable = AgentStore.shared.conversationChanged.sink {
            [weak self] in
            self?.scheduleRefresh(sourceIDs: [UniversalSearchAgentConversationSource.id])
        }
    }

    public func setWalletReady(_ isReady: Bool) {
        guard isWalletReady != isReady else { return }
        isWalletReady = isReady
        if isReady {
            // Serve the persisted corpus right away; the full source refresh rides the debounce so
            // it coalesces with the startup event storm instead of competing with startup work
            hydrationTask = Task { [weak self] in
                await self?.refresh(sourceIDs: [])
            }
            scheduleRefresh(sourceIDs: nil)
        } else {
            hydrationTask?.cancel()
            hydrationTask = nil
            refreshLoopGeneration &+= 1
            refreshTask?.cancel()
            refreshTask = nil
            mergePendingRefresh(sourceIDs: nil)
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        isWalletReady = false
        WalletCoreData.remove(observer: self)
        refreshLoopGeneration &+= 1
        hydrationTask?.cancel()
        hydrationTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        browserHistoryLoadedCancellable?.cancel()
        browserHistoryLoadedCancellable = nil
        agentConversationChangedCancellable?.cancel()
        agentConversationChangedCancellable = nil
        pendingRefreshSourceIDs.removeAll()
        pendingFullRefresh = false
        pendingRefreshSince = nil
    }

    func add(observer: any UniversalSearchIndexServiceObserver) {
        observers.removeAll { $0.value == nil }
        guard !observers.contains(where: { $0.value === observer }) else { return }
        observers.append(WeakObserver(value: observer))
    }

    func remove(observer: any UniversalSearchIndexServiceObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            // Only account-scoped snapshots can be invalidated by a switch; shared snapshots and
            // cached snapshots of other accounts stay
            scheduleRefresh(sourceIDs: coordinator.accountScopedSourceIDs)

        case .accountDeleted(let accountID):
            WalletCoreSearchInteractionStore.shared.clear(scopeID: accountID)
            Task { [coordinator] in
                await coordinator.removeAccountScopedSlots(scopeID: accountID)
            }
            scheduleRefresh(sourceIDs: coordinator.accountScopedSourceIDs)

        case .accountsReset:
            WalletCoreSearchInteractionStore.shared.clearAll()
            Task { [coordinator] in
                await coordinator.removeAllAccountScopedSlots()
            }
            scheduleRefresh(sourceIDs: coordinator.accountScopedSourceIDs)

        case .accountNameChanged, .updateAccount, .updateAccountConfig,
             .updateAccountDomainData:
            scheduleRefresh(sourceIDs: [WalletCoreWalletSearchSource.id, UniversalSearchAppEntrySource.id])

        case .tokensChanged, .swapTokensChanged, .baseCurrencyChanged,
             .assetsAndActivityDataUpdated, .hideNoCostTokensChanged,
             .updateCurrencyRates, .updateSwapTokens, .updateTokens:
            scheduleRefresh(sourceIDs: [WalletCoreTokenSearchSource.id])

        // Balance and NFT updates carry an account; only the current account's snapshot can be
        // affected, and switching to another account re-snapshots its sources anyway
        case .balanceChanged(let accountID), .rawBalancesChanged(let accountID):
            if accountID == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreTokenSearchSource.id])
            }

        case .updateBalances(let update):
            if update.accountId == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreTokenSearchSource.id])
            }

        case .nftsChanged(let accountID):
            if accountID == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])
            }

        case .updateNfts(let update):
            if update.accountId == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])
            }

        case .nftReceived(let update):
            if update.accountId == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])
            }

        case .nftSent(let update):
            if update.accountId == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])
            }

        case .nftPutUpForSale(let update):
            if update.accountId == AccountStore.accountId {
                scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])
            }

        case .hideUnverifiedNftsChanged:
            scheduleRefresh(sourceIDs: [WalletCoreCollectibleSearchSource.id])

        case .updateDapps, .dappsCountUpdated, .dappDisconnected:
            scheduleRefresh(sourceIDs: [WalletCoreConnectedAppSearchSource.id, UniversalSearchAppEntrySource.id])

        case .walletVersionsDataReceived:
            scheduleRefresh(sourceIDs: [UniversalSearchAppEntrySource.id])

        case .configChanged:
            scheduleRefresh(sourceIDs: [
                WalletCoreExploreAppSearchSource.id,
                UniversalSearchAgentSuggestionSource.id,
                UniversalSearchAppEntrySource.id,
            ])

        default:
            break
        }
    }

    private func scheduleRefresh(
        sourceIDs: Set<SearchSourceID>?,
        immediate: Bool = false
    ) {
        mergePendingRefresh(sourceIDs: sourceIDs)
        guard isStarted, isWalletReady else { return }
        if pendingRefreshSince == nil {
            pendingRefreshSince = ContinuousClock.now
        }
        guard !isRefreshLoopRunning else { return }

        let delay: Duration
        if immediate {
            delay = .zero
        } else {
            let now = ContinuousClock.now
            let latestStart = (pendingRefreshSince ?? now) + timing.maxPostpone
            delay = min(timing.debounce, max(.zero, latestStart - now))
        }

        refreshTask?.cancel()
        refreshLoopGeneration &+= 1
        let generation = refreshLoopGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await runRefreshLoop(generation: generation)
        }
    }

    private func runRefreshLoop(generation: UInt64) async {
        isRefreshLoopRunning = true
        var hasCompletedRefresh = false
        while isStarted,
              isWalletReady,
              generation == refreshLoopGeneration,
              !Task.isCancelled,
              hasPendingRefresh {
            if hasCompletedRefresh {
                try? await Task.sleep(for: timing.loopPacing)
                guard !Task.isCancelled else { break }
            }
            let sourceIDs = takePendingRefreshSourceIDs()
            await refresh(sourceIDs: sourceIDs)
            hasCompletedRefresh = true
        }
        isRefreshLoopRunning = false
        if generation == refreshLoopGeneration {
            refreshTask = nil
        }

        if isStarted, isWalletReady, hasPendingRefresh {
            scheduleRefresh(sourceIDs: [], immediate: true)
        }
    }

    private func refresh(sourceIDs: Set<SearchSourceID>?) async {
        let context = contextProvider()
        if await coordinator.currentContext() != context {
            publish(.init(context: context, kind: .contextChanged))
        }
        do {
            let result = try await coordinator.refresh(
                context: context,
                sourceIDs: sourceIDs
            ) { [weak self] progress in
                await self?.publish(.init(context: context, kind: .source(progress)))
            }
            guard result.disposition == .applied else { return }
            publish(.init(context: context, kind: .completed(result)))
        } catch is CancellationError {
            return
        } catch {
            indexServiceLog.error(
                "refresh failed error=\(String(describing: error), .public)"
            )
        }
    }

    private func publish(_ update: UniversalSearchIndexUpdate) {
#if DEBUG
        switch update.kind {
        case .contextChanged:
            indexServiceLog.info(
                "context changed network=\(update.context.network ?? "none", .public)"
            )
        case .source(let progress):
            indexServiceLog.info(
                "source ready id=\(progress.sourceID, .public) source_docs=\(progress.sourceDocumentCount, .public) corpus_docs=\(progress.corpusDocumentCount, .public) source_ms=\(Self.formatted(progress.sourceElapsedMilliseconds), .public) index_ms=\(Self.formatted(progress.indexElapsedMilliseconds), .public) revision=\(progress.corpusRevision, .public)"
            )
        case .completed(let result):
            indexServiceLog.info(
                "refresh complete disposition=\(result.disposition.rawValue, .public) sources=\(result.refreshedSourceIDs.count, .public) failures=\(result.failures.count, .public) revision=\(result.corpusRevision, .public)"
            )
        }
#endif
        observers = observers.filter { $0.value != nil }
        for observer in observers {
            observer.value?.universalSearchIndexService(self, didUpdate: update)
        }
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func mergePendingRefresh(sourceIDs: Set<SearchSourceID>?) {
        guard let sourceIDs else {
            pendingFullRefresh = true
            pendingRefreshSourceIDs.removeAll()
            return
        }
        guard !pendingFullRefresh else { return }
        pendingRefreshSourceIDs.formUnion(sourceIDs)
    }

    private func takePendingRefreshSourceIDs() -> Set<SearchSourceID>? {
        defer {
            pendingFullRefresh = false
            pendingRefreshSourceIDs.removeAll()
            pendingRefreshSince = nil
        }
        return pendingFullRefresh ? nil : pendingRefreshSourceIDs
    }

    private var hasPendingRefresh: Bool {
        pendingFullRefresh || !pendingRefreshSourceIDs.isEmpty
    }
}

private final class WeakObserver {
    weak var value: (any UniversalSearchIndexServiceObserver)?

    init(value: any UniversalSearchIndexServiceObserver) {
        self.value = value
    }
}
