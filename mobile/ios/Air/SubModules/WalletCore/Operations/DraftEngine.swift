import Foundation
import Perception

/// Keeps a blockchain-operation draft in sync with a request derived from
/// model state.
///
/// The engine is pull-based: the owner provides a single pure derivation of
/// the current request via ``start(request:)`` and the engine observes it
/// through Perception, reloading whenever the request changes. The request
/// must contain every user-input value that identifies the draft (rule:
/// request = intent). Wallet-state changes that should revalidate the same
/// request are events — report them with ``refresh()``, which keeps the
/// current draft visible while the replacement loads (stale-while-revalidate).
///
/// Published state is always evaluated against the live request, so it is
/// consistent synchronously after any mutation: ``current`` and ``failure``
/// only ever describe the request the model derives right now.
///
/// Perception visibility is deliberately one-way. Published properties
/// participate in the caller's observation, but mutating entry points —
/// ``refresh()``, ``retry()``, ``pause()``, ``resume()`` — read no
/// perceptible state, so an owner observer such as
/// `observe { _ = balances; engine.refresh() }` is never re-triggered by
/// the engine's own state transitions.
///
/// At most one load runs at a time; a request change or refresh during a
/// flight queues exactly one follow-up load (coalescing). Loads are never
/// interrupted mid-flight — results for a request that is no longer live are
/// discarded on arrival.
@Perceptible
@MainActor
public final class DraftEngine<
    Request: Equatable & Sendable,
    Draft: Sendable
>: Sendable {
    public typealias Loader = @MainActor @Sendable (
        _ request: Request,
        _ previous: Draft?
    ) async throws -> Draft
    /// Decides how long to wait before loading after the request changed
    /// from `from` to `to`. Return `.zero` for discrete picks (token,
    /// account) and a small delay for typed transitions. `from` is `nil`
    /// for the first observed request.
    public typealias DebouncePolicy = @MainActor @Sendable (
        _ from: Request?,
        _ to: Request
    ) -> Duration
    public typealias ScopePredicate = @MainActor @Sendable (
        Request,
        Request
    ) -> Bool
    public typealias LoadHandler = @MainActor (
        OperationDraftSnapshot<Request, Draft>
    ) -> Void
    public typealias FailureHandler = @MainActor (
        Request,
        any Error
    ) -> Void

    /// The live request, straight from the owner's derivation.
    public var request: Request? {
        requestProvider?()
    }

    /// The draft for exactly the live request. The only state submission
    /// may read. Retained while ``refresh()`` revalidates the same request.
    public var current: OperationDraftSnapshot<Request, Draft>? {
        _ = stateVersion
        guard let last, last.request == request else { return nil }
        return last
    }

    /// The latest load failure, if it was for the live request. When
    /// ``current`` is non-nil alongside it, the failure came from a refresh
    /// and the previous draft is still valid for display.
    public var failure: (any Error)? {
        _ = stateVersion
        guard let failed, failed.request == request else { return nil }
        return failed.error
    }

    /// No answer exists yet for the live request.
    public var isLoading: Bool {
        _ = stateVersion
        return request != nil && current == nil && failure == nil
            && !isPaused
    }

    /// The live request already has a draft and a replacement is loading.
    public var isRefreshing: Bool {
        _ = stateVersion
        return current != nil && inFlight == request
    }

    /// The live request failed and there is no draft to fall back on.
    public var canRetry: Bool {
        failure != nil && current == nil
    }

    /// The draft to display: ``current``, or the latest successful draft
    /// whose request shares the live request's scope. Display continuity
    /// only — never submit it.
    public var displayed: Draft? {
        _ = stateVersion
        if let current {
            return current.draft
        }
        guard let last, let request,
              sameScope(last.request, request) else {
            return nil
        }
        return last.draft
    }

    /// Runs after each successful load for the live request. May mutate
    /// owner input; if that moves the request, the engine reloads
    /// immediately, bypassing the debounce policy. Must converge: applying
    /// the same draft twice must not move the request again.
    @PerceptionIgnored
    public var onLoad: LoadHandler?
    /// Runs after each failed load for the live request.
    @PerceptionIgnored
    public var onFailure: FailureHandler?

    /// Bumped on every internal state transition. Published getters read it
    /// so observers are notified, while the stored state stays untracked and
    /// mutating entry points remain invisible to the caller's observation.
    private var stateVersion: UInt64 = 0
    /// Untracked shadow of ``stateVersion``. Bumps write the perceptible
    /// property without reading it — a compound `&+= 1` would register an
    /// access with the caller's observation.
    @PerceptionIgnored
    private var versionCounter: UInt64 = 0

    @PerceptionIgnored
    private var last: OperationDraftSnapshot<Request, Draft>?
    @PerceptionIgnored
    private var failed: (request: Request, error: any Error)?
    @PerceptionIgnored
    private var inFlight: Request?
    @PerceptionIgnored
    private var isPaused = false
    @PerceptionIgnored
    private var requestProvider: (@MainActor () -> Request?)?
    @PerceptionIgnored
    private var observedRequest: Request?
    @PerceptionIgnored
    private var observationGeneration: UInt64 = 0
    @PerceptionIgnored
    private var pendingRefresh = false
    @PerceptionIgnored
    private var debounceTask: Task<Void, Never>?
    @PerceptionIgnored
    private var loadTask: Task<Void, Never>?
    @PerceptionIgnored
    private var timerTask: Task<Void, Never>?
    @PerceptionIgnored
    private let debounce: DebouncePolicy
    @PerceptionIgnored
    /// Delay used for the next periodic refresh. Owners may adjust it after
    /// a load to back off failures without adding a second timer.
    public var refreshInterval: Duration?
    @PerceptionIgnored
    private let sameScope: ScopePredicate
    @PerceptionIgnored
    private let load: Loader

    public init(
        debounce: @escaping DebouncePolicy = { _, _ in .zero },
        refreshInterval: Duration? = nil,
        sameScope: @escaping ScopePredicate = { $0 == $1 },
        load: @escaping Loader
    ) {
        self.debounce = debounce
        self.refreshInterval = refreshInterval
        self.sameScope = sameScope
        self.load = load
    }

    /// Constant-debounce convenience for flows where every request change
    /// comes from typing.
    public convenience init(
        debounce interval: Duration,
        refreshInterval: Duration? = nil,
        sameScope: @escaping ScopePredicate = { $0 == $1 },
        load: @escaping Loader
    ) {
        self.init(
            debounce: { from, _ in from == nil ? .zero : interval },
            refreshInterval: refreshInterval,
            sameScope: sameScope,
            load: load
        )
    }

    deinit {
        debounceTask?.cancel()
        loadTask?.cancel()
        timerTask?.cancel()
    }

    /// Begins observing the request derivation. Call once, after the owner
    /// is fully initialised. The derivation must read owner input and
    /// environment only — never engine state.
    public func start(
        request: @escaping @MainActor () -> Request?
    ) {
        requestProvider = request
        observeRequest()
    }

    /// Revalidates the observed request, keeping ``current`` visible until
    /// the replacement arrives. Use for wallet-state events: balance
    /// changes, app foreground. No-op while a debounced load is already
    /// pending — that load fetches fresh data anyway.
    public func refresh() {
        guard !isPaused, observedRequest != nil, debounceTask == nil else { return }
        if inFlight != nil {
            pendingRefresh = true
            return
        }
        startLoad()
    }

    public func retry() {
        refresh()
    }

    /// Re-evaluates the live request immediately, bypassing the debounce
    /// policy, and reloads if it moved. Use after programmatic input
    /// mutations — feedback from another engine, an applied scan result —
    /// where waiting out a typing debounce would be wrong. No-op while the
    /// request is unchanged. Never call from inside an owner observation:
    /// it reads the request derivation.
    public func synchronize() {
        syncRequest()
    }

    /// Stops starting loads. An in-flight load may still complete and
    /// publish. Observation continues, so the engine stays in sync with
    /// the request and ``resume()`` picks up where the owner left off.
    public func pause() {
        isPaused = true
        debounceTask?.cancel()
        debounceTask = nil
        timerTask?.cancel()
        pendingRefresh = false
        bumpVersion()
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        bumpVersion()
        refresh()
    }

    private func bumpVersion() {
        versionCounter &+= 1
        stateVersion = versionCounter
    }

    // MARK: - Observation

    /// Self-re-arming Perception observation. Tracking covers only the
    /// request derivation, so engine-internal writes can never re-trigger
    /// it. `onChange` fires at willSet on an arbitrary thread; the
    /// main-actor hop coalesces synchronous mutation bursts and reads the
    /// settled value. The generation counter makes superseded armings inert.
    private func observeRequest() {
        observationGeneration &+= 1
        let generation = observationGeneration
        let request = withPerceptionTracking { [requestProvider] in
            requestProvider?()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.observationGeneration == generation else {
                    return
                }
                self.observeRequest()
            }
        }
        handleRequestChange(request, immediateReload: false)
    }

    /// Untracked catch-up with the live request, used after a publish so
    /// feedback that moved the request reloads without waiting for the
    /// observation hop or the debounce policy.
    private func syncRequest() {
        handleRequestChange(requestProvider?(), immediateReload: true)
    }

    private func handleRequestChange(
        _ request: Request?,
        immediateReload: Bool
    ) {
        guard request != observedRequest else { return }
        let previous = observedRequest
        observedRequest = request
        failed = nil
        pendingRefresh = false
        debounceTask?.cancel()
        debounceTask = nil
        timerTask?.cancel()
        bumpVersion()
        guard let request, !isPaused else { return }

        let delay = immediateReload
            ? .zero
            : debounce(previous, request)
        guard delay > .zero else {
            startLoad()
            return
        }
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            debounceTask = nil
            startLoad()
        }
    }

    // MARK: - Loading

    private func startLoad() {
        guard !isPaused, let request = observedRequest else { return }
        guard inFlight == nil else { return }
        if failed?.request == request {
            failed = nil
        }
        inFlight = request
        // This load supersedes any scheduled periodic tick; the next one
        // is scheduled when it finishes.
        timerTask?.cancel()
        bumpVersion()
        let previous = last.flatMap {
            sameScope($0.request, request) ? $0.draft : nil
        }
        loadTask = Task { [weak self, load] in
            let result: Result<Draft, any Error>
            do {
                result = .success(try await load(request, previous))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.finish(request, result)
        }
    }

    private func finish(
        _ request: Request,
        _ result: Result<Draft, any Error>
    ) {
        inFlight = nil
        loadTask = nil
        let shouldRefresh = pendingRefresh
        pendingRefresh = false
        bumpVersion()
        if request == self.request {
            switch result {
            case .success(let draft):
                let snapshot = OperationDraftSnapshot(
                    request: request,
                    draft: draft
                )
                last = snapshot
                failed = nil
                bumpVersion()
                onLoad?(snapshot)
                syncRequest()
            case .failure(let error):
                // A queued follow-up load supersedes this failure: the
                // engine stays in the loading state instead of surfacing
                // an error the immediate revalidation may clear.
                if !shouldRefresh {
                    failed = (request, error)
                    bumpVersion()
                    onFailure?(request, error)
                }
            }
        }
        // Input changes are covered by the latest observed request. Only
        // explicit refreshes require another load of the same request.
        if inFlight == nil {
            if debounceTask == nil, shouldRefresh || observedRequest != request {
                startLoad()
            } else {
                scheduleTick()
            }
        }
    }

    private func scheduleTick() {
        guard let refreshInterval, !isPaused,
              observedRequest != nil else {
            return
        }
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: refreshInterval)
            } catch {
                return
            }
            self?.refresh()
        }
    }
}
