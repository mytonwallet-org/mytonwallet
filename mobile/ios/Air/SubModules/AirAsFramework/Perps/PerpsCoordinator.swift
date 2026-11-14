import UIKit
import Dependencies
import SwiftUI
import SwiftNavigation
import ProtectedAction
import WalletContext
import WalletCore
import UIComponents
import UIAssets
import UIToken

/// Pins a flow to its wallet; presentation controllers remain SDK-independent.
@MainActor final class PerpsCoordinator {
    let context: AccountContext
    let store: PerpsStore
    @Dependency(\.accountStore) private var accountStore
    private weak var assetScreenBeingSwitched: UIViewController?
    private var visibility: Task<Void, Never>?
    private weak var home: PerpsHomeVC?
    private var homeSnapshotLoading = PerpsInitialLoadingState()
    private var homeMarketLoading = PerpsInitialLoadingState()
    private var homeHistoryLoading = PerpsInitialLoadingState()
    private let prefetchStories: @MainActor ([ApiPerpsOnboardingStory]) async -> Bool
    private var onboardingPrefetch: (id: UUID, onboarding: ApiPerpsOnboarding)?
    private(set) var isPreparingBalanceWithdrawal = false

    deinit { visibility?.cancel() }

    init(accountId: String, store: PerpsStore = .shared,
         prefetchStories: @escaping @MainActor ([ApiPerpsOnboardingStory]) async -> Bool = { await PerpsStoryMediaCache.shared.prefetch($0) }) {
        context = AccountContext(accountId: accountId)
        self.store = store
        self.prefetchStories = prefetchStories
        context.onAccountDeleted = { [weak self] in
            self?.setVisible(false)
            self?.home?.navigationController?.dismiss(animated: true)
        }
    }

    func makeHome() -> UIViewController {
        let accountId = context.accountId
        homeSnapshotLoading = .init()
        homeMarketLoading = .init()
        homeHistoryLoading = .init()
        let controller = PerpsHomeVC(data: homeDisplayData()) { [self] action in
            guard let home else { return }
            switch action {
            case .refresh: Task { await store.reconcile(accountId: accountId) }
            case .allPositions: showAllPositions()
            case .withdrawBalance: showBalanceWithdrawal(from: home)
            case .position(let id): showPosition(id, from: home)
            case .marketToken(_, let id): showMarket(id, from: home)
            case .marketSection(let id):
                guard let section = PerpsHomeAdapter.home(store: store, accountId: accountId, previewMarkets: false).marketSections.first(where: { $0.id == id }) else { return }
                var loading = PerpsInitialLoadingState()
                let render: () -> [MarketItemDisplayData] = { [store] in
                    let tokens = PerpsHomeAdapter.home(store: store, accountId: accountId, previewMarkets: false)
                        .marketSections.first { $0.id == id }?.tokens ?? []
                    let isStale = loading.update(isStale: store.isMarketStale(), hasData: store.market != nil)
                    return tokens.map { token in
                        var token = token
                        token.isStale = isStale
                        return token
                    }
                }
                let list = MarketTokenListVC(title: section.title, tokens: render()) { [self, weak home] token in
                    if let home { showMarket(token.id, from: home) }
                }
                list.onVisibilityChanged = { [weak self] in self?.setVisible($0) }
                list.observe { [weak list] in list?.update(tokens: render()) }
                home.navigationController?.pushViewController(list, animated: true)
            case .activity(let id): showFill(id, from: home)
            }
        }
        home = controller
        controller.observe { [weak controller, weak self] in
            guard let self else { return }
            controller?.update(data: homeDisplayData())
        }
        controller.onLoadMoreActivity = { [store, context] in Task { await store.loadMoreHistory(accountId: context.accountId) } }
        controller.onVisibilityChanged = { [self] in setVisible($0) }
        controller.onOpenOnboarding = { [weak controller, store] source in
            guard let controller, controller.presentedViewController == nil else { return }
            let stories = PerpsOnboarding.makeViewController(onboarding: store.market?.onboarding)
            stories.presentationSource = source
            controller.present(stories, animated: true)
        }
        controller.onDismissOnboarding = { [context] in
            context.settings.dismissHomeBanner(id: PerpsOnboarding.bannerID)
        }
        return controller
    }

    func showAllPositions() {
        guard let home else { return }
        var loading = PerpsInitialLoadingState()
        let render: () -> PerpsPositionsDisplayData = { [store, context] in
            var data = PerpsHomeAdapter.positions(store: store, accountId: context.accountId)
            data.isStale = loading.update(isStale: data.isStale, hasData: store.snapshots[context.accountId] != nil)
            return data
        }
        let list = PerpsPositionsVC(data: render()) { [self, weak home] action in
            switch action {
            case .position(let id): if let home { showPosition(id, from: home) }
            case .refresh: Task { await store.reconcile(accountId: context.accountId) }
            default: break
            }
        }
        list.observe { [weak list] in list?.update(data: render()) }
        list.onVisibilityChanged = { [self] in setVisible($0) }
        home.navigationController?.pushViewController(list, animated: true)
    }

    func showMarket(_ id: String, from origin: UIViewController) {
        if let position = store.snapshots[context.accountId]?.positions.first(where: { $0.assetId == id }) {
            showPosition(position.id, from: origin)
            return
        }
        guard let controller = makeMarket(id) else { return }
        origin.navigationController?.pushViewController(controller, animated: true)
    }

    private func makeMarket(_ id: String, chart existing: PerpsChartSelection? = nil) -> PerpsMarketVC? {
        guard let asset = asset(id) else { return nil }
        let chart = existing ?? PerpsChartSelection(store: store, assetId: id)
        var snapshotLoading = PerpsInitialLoadingState()
        weak var screen: PerpsMarketVC?
        let render: () -> PerpsMarketDisplayData = { [store, context] in
            var data = PerpsSDKAdapter.market(store.asset(id: id) ?? asset,
                canTrade: PerpsAvailability.canTrade(context.account, store: store), period: chart.period, history: chart.history,
                tradingUnavailableReason: PerpsAvailability.tradingUnavailableReason(context.account, store: store))
            data.applyAccountAvailability(context.account, store: store)
            data.isHistoryRestored = chart.isRestored()
            data.isStale = snapshotLoading.update(isStale: store.isMarketStale(), hasData: store.market != nil)
            return data
        }
        let load: (ApiPriceHistoryPeriod) -> Void = { selected in
            chart.select(selected) { screen?.update(data: render()) }
        }
        let controller = PerpsMarketVC(data: render(), onSelectPeriod: load) { [self] side in
            guard let screen else { return }
            showOrder(asset: asset, side: side, from: screen)
        }
        screen = controller
        controller.onVisibilityChanged = { [self] in setVisible($0) }
        controller.observe { [weak controller, self] in
            guard let controller else { return }
            if let position = store.snapshots[context.accountId]?.positions.first(where: { $0.assetId == id }) {
                switchAssetScreen(from: controller) { [self] in makePosition(position.id, chart: chart) }
            } else {
                controller.update(data: render())
            }
        }
        load(chart.period)
        Task { await store.refreshAsset(accountId: context.accountId, assetId: id) }
        return controller
    }

    func showPosition(_ id: String, from origin: UIViewController) {
        guard let controller = makePosition(id) else { return }
        origin.navigationController?.pushViewController(controller, animated: true)
    }

    private func makePosition(_ id: String, chart existing: PerpsChartSelection? = nil) -> PerpsPositionVC? {
        guard let position = position(id), let asset = asset(position.assetId) else { return nil }
        weak var screen: PerpsPositionVC?
        let chart = existing ?? PerpsChartSelection(store: store, assetId: asset.id)
        var snapshotLoading = PerpsInitialLoadingState()
        var historyLoading = PerpsInitialLoadingState()
        let render: () -> PerpsPositionDisplayData = { [store, context] in
            let current = store.snapshots[context.accountId]?.positions.first { $0.id == id }
            let fills = store.fills(accountId: context.accountId, assetId: asset.id)
            var data = PerpsSDKAdapter.position(current ?? position, asset: store.asset(id: asset.id) ?? asset,
                fills: fills ?? [], canTrade: PerpsAvailability.canTrade(context.account, store: store) && current != nil,
                history: chart.history, tradingUnavailableReason: PerpsAvailability.tradingUnavailableReason(context.account, store: store))
            data.market.applyAccountAvailability(context.account, store: store)
            data.market.period = chart.period
            data.market.isHistoryRestored = chart.isRestored()
            data.market.isStale = snapshotLoading.update(isStale: store.isSnapshotStale(accountId: context.accountId),
                                                         hasData: store.snapshots[context.accountId] != nil)
            data.isActivityStale = historyLoading.update(isStale: store.isHistoryStale(accountId: context.accountId),
                                                         hasData: fills != nil)
            if current == nil { data.equity.optionalAmount = nil }
            return data
        }
        let load: (ApiPriceHistoryPeriod) -> Void = { selected in
            chart.select(selected) { screen?.update(data: render()) }
        }
        let controller = PerpsPositionVC(data: render(), onSelectPeriod: load) { [self] action in
            guard let screen else { return }
            switch action {
            case .edit:
                guard let current = self.position(id) else { return }
                showOrder(asset: asset, side: current.side, position: current, from: screen)
            case .close:
                guard !presentPendingOperation(from: screen, assetId: asset.id, kind: "close") else { return }
                guard canTrade(assetId: asset.id, kind: "close"), !screen.isPreparingClose, let current = self.position(id) else { return }
                screen.isPreparingClose = true
                Task {
                    defer { screen.isPreparingClose = false }
                    do {
                        let draft = ApiPerpsDraft(assetId: asset.id, side: current.side,
                            amount: "0", leverage: current.raw.leverage.value, editing: true, close: true)
                        let quote = try await store.client.prepare(context.accountId, draft)
                        guard screen.viewIfLoaded?.window != nil,
                              screen.navigationController?.topViewController === screen,
                              screen.presentedViewController == nil, canTrade(assetId: asset.id, kind: "close") else { return }
                        showReview(quote, draft: draft, asset: asset, from: screen, presented: true)
                    } catch { AppActions.showError(error: PerpsExecutionError(message: PerpsFormatting.error(error))) }
                }
            case .activity(let id): showFill(id, from: screen)
            }
        }
        controller.onLoadMoreActivity = { [store, context] in
            Task { await store.refreshAsset(accountId: context.accountId, assetId: asset.id, loadMore: true) }
        }
        screen = controller
        controller.onVisibilityChanged = { [self] in setVisible($0) }
        controller.observe { [weak controller, self] in
            guard let controller else { return }
            // The store keeps the last complete read, so a position missing from it has closed
            if let snapshot = store.snapshots[context.accountId], !snapshot.positions.contains(where: { $0.id == id }) {
                switchAssetScreen(from: controller) { [self] in makeMarket(asset.id, chart: chart) }
            } else {
                controller.update(data: render())
            }
        }
        load(chart.period)
        Task { await store.refreshAsset(accountId: context.accountId, assetId: asset.id) }
        return controller
    }

    /// Runs after the observation that noticed the change, and after any push or pop already under way.
    private func switchAssetScreen(from current: UIViewController, to makeNext: @escaping () -> UIViewController?) {
        guard assetScreenBeingSwitched !== current else { return }
        assetScreenBeingSwitched = current
        DispatchQueue.main.async { [self, weak current] in
            guard let current, let navigation = current.navigationController else { return }
            // Checked first: a swipe back that gets cancelled returns the screen to the stack
            if let transition = navigation.transitionCoordinator, navigation.presentedViewController == nil,
               transition.animate(alongsideTransition: nil, completion: { [self, weak current] _ in
                   assetScreenBeingSwitched = nil
                   if let current { switchAssetScreen(from: current, to: makeNext) }
               }) {
                return
            }
            guard navigation.viewControllers.contains(current), let next = makeNext() else {
                assetScreenBeingSwitched = nil
                return
            }
            Task { [self] in
                await navigation.switchAssetScreen(current, to: next)
                assetScreenBeingSwitched = nil
            }
        }
    }

    private func showOrder(asset: ApiPerpsAsset, side: PerpsTradeDirection, position: ApiPerpsAccountPosition? = nil,
                           from origin: UIViewController) {
        // The screen is about to become this position's, which has no Long or Short.
        guard position != nil || store.snapshots[context.accountId]?.positions.contains(where: { $0.assetId == asset.id }) != true else { return }
        let entryKind = position == nil ? "open" : "reduce"
        guard !presentPendingOperation(from: origin, assetId: asset.id, kind: entryKind) else { return }
        guard canTrade(assetId: asset.id, kind: entryKind), let asset = self.asset(asset.id) else { return }
        let controller = makeOrder(asset: asset, side: side, position: position)
        origin.present(WNavigationController(rootViewController: controller), animated: true)
    }

    func makeOrder(asset: ApiPerpsAsset, side: PerpsTradeDirection, position: ApiPerpsAccountPosition? = nil) -> PerpsOrderVC {
        let entryKind = position == nil ? "open" : "reduce"
        let input = PerpsOrderInput(amount: position.map { PerpsSDKAdapter.currentInput($0.collateral).text } ?? "",
                                    leverage: position?.raw.leverage.value ?? min(2, asset.maxLeverage),
                                    intent: position == nil ? .amount : .current)
        let balances = { [context, store] in
            PerpsSDKAdapter.FundingBalances(
                wallet: context.balances[PerpsSDKAdapter.usdc.slug].map { bigIntToDoubleString($0, decimals: PerpsSDKAdapter.usdc.decimals) },
                hyperliquid: store.snapshots[context.accountId]?.spendableUsdcByDex?[asset.dex])
        }
        var data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side, input: input, position: position,
                                         balances: balances())
        data.status = .loading
        weak var screen: PerpsOrderVC?
        var generation = UUID()
        let controller = PerpsOrderVC(data: data, loadLeverageEstimate: { [self] input in
            let draft = PerpsSDKAdapter.draft(assetId: asset.id, side: side, input: input, isEditing: false)
            return PerpsSDKAdapter.leverageEstimate(try await store.client.leverageEstimate(context.accountId, draft))
        }, loadEstimate: { [self] input in
            let draft = PerpsSDKAdapter.draft(assetId: asset.id, side: side, input: input, isEditing: position != nil)
            let quote = try await store.client.preview(context.accountId, draft)
            return PerpsSDKAdapter.order(asset: self.asset(asset.id) ?? asset, account: context.account, side: side,
                                         input: input, position: position, quote: quote, balances: balances())
        }, onSelectAccount: { [store, accountStore] accountId in
            guard position == nil, let screen, let navigation = screen.navigationController,
                  navigation.topViewController === screen else { return }
            generation = UUID()
            try await accountStore.activateAccount(accountId: accountId)
            guard navigation.topViewController === screen else { return }
            let coordinator = PerpsCoordinator(accountId: accountId, store: store)
            let next = coordinator.makeOrder(asset: asset, side: side)
            navigation.setViewControllers([next], animated: false)
        }) { [self] request in
            if request.action == .buyUsdc || request.action == .buyEth {
                screen?.setEstimateRefreshSuspended(true)
                let token = request.action == .buyUsdc ? PerpsSDKAdapter.usdc
                    : TokenStore.tokens[ARBITRUM_SLUG] ?? .ARBITRUM
                Task { [context, weak screen] in
                    await AppActions.showTokenTrade(accountContext: context, token: token, isBuying: true, onDismiss: { [weak screen] in
                        screen?.setEstimateRefreshSuspended(false)
                        screen?.refreshFunding()
                    })
                }
                return
            }
            let requestID = UUID(); generation = requestID
            Task { [self] in
                if request.action == .amountChanged || request.action == .leverageChanged {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard generation == requestID else { return }
                }
                let input = request.input
                let draft = PerpsSDKAdapter.draft(assetId: asset.id, side: side, input: input, isEditing: position != nil)
                var requirements: ApiPerpsFundingRequirements?
                do {
                    if store.snapshots[context.accountId] == nil {
                        await store.refresh(accountId: context.accountId, includesHistory: false)
                        guard generation == requestID else { return }
                    }
                    let isEmptyOpening = position == nil && !input.hasAmount && input.fraction == nil
                    if request.action == .refreshFunding || isEmptyOpening || data.fundingRequirement != nil {
                        requirements = try await store.client.fundingRequirements(context.accountId, draft)
                        guard generation == requestID, let screen else { return }
                        guard canTrade(assetId: asset.id, kind: entryKind) else {
                            throw PerpsExecutionError(message: self.asset(asset.id)?.tradingAvailability?.reason ?? "PerpsUnavailable")
                        }
                        if isEmptyOpening || requirements?.needsUsdc == true || requirements?.needsEth == true
                            || (request.action == .refreshFunding && position != nil && input.intent == .current) {
                            data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side,
                                input: input, position: position, fundingRequirements: requirements, balances: balances())
                            _ = screen.update(data: data, for: request)
                            return
                        }
                    }
                    let quote = try await (request.action == .review ? store.client.prepare : store.client.preview)(context.accountId, draft)
                    guard generation == requestID, let screen else { return }
                    guard canTrade(assetId: asset.id, kind: quote.kind == "unchanged" ? entryKind : quote.kind) else {
                        throw PerpsExecutionError(message: store.pendingOperation(accountId: context.accountId, assetId: asset.id, kind: quote.kind) != nil
                            ? "PerpsOperationPending" : self.asset(asset.id)?.tradingAvailability?.reason ?? "PerpsUnavailable")
                    }
                    data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side, input: input,
                                                 position: position, quote: quote, fundingRequirements: requirements,
                                                 balances: balances())
                    _ = screen.update(data: data, for: request)
                    if request.action == .review && quote.kind != "unchanged" { showReview(quote, draft: draft, asset: asset, from: screen) }
                } catch {
                    if requirements == nil, String(describing: error).contains("PerpsInsufficient") {
                        requirements = try? await store.client.fundingRequirements(context.accountId, draft)
                    }
                    guard generation == requestID else { return }
                    data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side,
                        input: input, position: position, fundingRequirements: requirements, balances: balances())
                    if data.fundingRequirement == nil { data.status = .unavailable(PerpsFormatting.error(error)) }
                    _ = screen?.update(data: data, for: request)
                }
            }
        }
        screen = controller
        var lastFundingBalances = [context.balances[PerpsSDKAdapter.usdc.slug], context.balances[ARBITRUM_SLUG]]
        controller.observe { [weak controller, context] in
            guard let controller else { return }
            let balances = [context.balances[PerpsSDKAdapter.usdc.slug], context.balances[ARBITRUM_SLUG]]
            guard balances != lastFundingBalances else { return }
            lastFundingBalances = balances
            guard controller.presentedViewController == nil,
                  controller.navigationController?.topViewController === controller else { return }
            controller.refreshBlockedFunding()
        }
        return controller
    }

    private func showReview(_ initialQuote: ApiPerpsQuote, draft: ApiPerpsDraft, asset: ApiPerpsAsset, from origin: UIViewController, presented: Bool = false) {
        var quote = initialQuote
        var data = PerpsSDKAdapter.review(quote, asset: asset)
        weak var screen: PerpsOrderReviewVC?
        func refreshReview(for request: PerpsOrderReviewRequest) async {
            do {
                let refreshed = try await store.client.prepare(context.accountId, draft)
                var updated = PerpsSDKAdapter.review(refreshed, asset: self.asset(asset.id) ?? asset)
                updated.notice = lang("PerpsReviewUpdated")
                guard updated.mode.operation == data.mode.operation, updated.positionID == data.positionID,
                      screen?.update(data: updated, for: request) == true else {
                    var unavailable = data
                    unavailable.status = .unavailable(lang("PerpsPositionChanged"))
                    _ = screen?.update(data: unavailable, for: request)
                    return
                }
                quote = refreshed
                data = updated
            } catch {
                var unavailable = data
                unavailable.status = .unavailable(PerpsFormatting.error(error))
                _ = screen?.update(data: unavailable, for: request)
            }
        }
        let controller = PerpsOrderReviewVC(data: data) { [self] request in
            guard let screen else { return }
            Task { [self] in
                guard canTrade(assetId: asset.id, kind: quote.kind) else {
                    var unavailable = data
                    unavailable.status = .unavailable(store.pendingOperation(accountId: context.accountId, assetId: asset.id, kind: quote.kind) != nil
                        ? lang("PerpsOperationPending")
                        : PerpsAvailability.tradingUnavailableReason(context.account, store: store)
                            ?? lang(self.asset(asset.id)?.tradingAvailability?.reason ?? "PerpsUnavailable"))
                    _ = screen.update(data: unavailable, for: request)
                    return
                }
                if quote.expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) {
                    await refreshReview(for: request)
                    return
                }
                // Authentication must authorize this exact displayed quote, even if it expires while entering the code.
                let reviewedQuote = quote
                let outcome = await confirmReviewed(header: PerpsTradeConfirmationHeader(data: data), from: screen) { [self] token in
                    try await store.execute(quote: reviewedQuote, enclaveToken: token)
                } replacement: { [self] operation in
                    guard let controller = makeOperationReceipt(operation, asset: asset) else { return nil }
                    return Replacement(viewController: controller, animateAlongside: { [weak controller] in
                        controller?.animateToCollapsed()
                    })
                }
                switch outcome {
                case .finished:
                    break
                case .needsReview:
                    await refreshReview(for: request)
                case .failed(let message):
                    var restored = data
                    restored.status = .unavailable(message)
                    _ = screen.update(data: restored, for: request)
                case .cancelled:
                    if quote.expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) {
                        await refreshReview(for: request)
                    } else {
                        _ = screen.update(data: data, for: request)
                    }
                }
            }
        }
        screen = controller
        if presented {
            origin.present(WNavigationController(rootViewController: controller), animated: true)
        } else {
            origin.navigationController?.pushViewController(controller, animated: true)
        }
    }

    /// Authenticates and submits a reviewed operation. A committed result replaces the confirmation with `replacement`.
    private func confirmReviewed<Header: ConfirmationContent>(
        header: Header, from screen: UIViewController,
        submit: @escaping (EnclaveToken) async throws -> ApiPerpsOperation,
        replacement: @escaping (ApiPerpsOperation) -> Replacement?
    ) async -> PerpsReviewedOutcome {
        var needsReview = false
        let action = ProtectedAction<Header, PerpsExecutionResult>(account: context.account,
            software: .custom { token in
                do {
                    let result = try await submit(token)
                    let receipt = ActionSubmissionReceipt(payload: PerpsExecutionResult(operation: result))
                    switch result.state {
                    // The receipt displays settlement progress; committed does not imply a filled trade.
                    case "running", "completed", "partial", "unknown": return .resolved(.committed(receipt))
                    case "failed":
                        needsReview = ["PerpsQuoteExpired", "PerpsReviewChanged"].contains(result.error ?? "")
                        return .resolved(.notCommitted(PerpsExecutionError(message: PerpsFormatting.errorMessage(result.error))))
                    default: return .resolved(.indeterminate(error: PerpsExecutionError(message: lang("PerpsExecutionUnknown")), receipt: receipt))
                    }
                } catch PerpsError.expired {
                    needsReview = true
                    return .resolved(.notCommitted(PerpsError.expired))
                } catch { return .resolved(.notCommitted(error)) }
            }, hardware: nil,
            confirmation: .init(title: lang("Confirm"), header: header, requiresFreshAuthentication: true),
            completion: .replace { receipt in receipt.payload.flatMap { replacement($0.operation) } })
        switch await ProtectedActionExecutor.execute(action, in: .init(screen)) {
        case .completed:
            return .finished // ProtectedAction has already replaced confirmation with the receipt.
        case .partiallyCommitted(let receipt, _):
            if let operation = receipt.payload?.operation { showOperation(operation, from: screen, replacingOrder: true) }
            return .finished
        case .indeterminate(_, let receipt):
            if let operation = receipt?.payload?.operation { showOperation(operation, from: screen, replacingOrder: true) }
            return .finished
        case .failed(let error):
            return needsReview ? .needsReview : .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        }
    }

    /// Prepares a fresh quote for everything one withdrawal can send, then opens its review.
    func showBalanceWithdrawal(from origin: UIViewController) {
        guard !isPreparingBalanceWithdrawal, !presentPendingOperation(from: origin),
              PerpsAvailability.canTrade(context.account, store: store) else { return }
        setPreparingBalanceWithdrawal(true)
        Task { [self] in
            defer { setPreparingBalanceWithdrawal(false) }
            do {
                let quote = try await store.client.prepareBalanceWithdrawal(context.accountId)
                guard origin.viewIfLoaded?.window != nil, origin.presentedViewController == nil,
                      store.pendingOperation(accountId: context.accountId) == nil else { return }
                showBalanceWithdrawalReview(quote, from: origin)
            } catch { AppActions.showError(error: PerpsExecutionError(message: PerpsFormatting.error(error))) }
        }
    }

    private func setPreparingBalanceWithdrawal(_ isPreparing: Bool) {
        isPreparingBalanceWithdrawal = isPreparing
        home?.update(data: homeDisplayData())
    }

    private func showBalanceWithdrawalReview(_ initialQuote: ApiPerpsBalanceWithdrawalQuote, from origin: UIViewController) {
        var quote = initialQuote
        var data = PerpsSDKAdapter.balanceWithdrawalReview(quote)
        weak var screen: PerpsBalanceWithdrawalReviewVC?
        func refreshReview(for request: PerpsOrderReviewRequest) async {
            do {
                let refreshed = try await store.client.prepareBalanceWithdrawal(context.accountId)
                var updated = PerpsSDKAdapter.balanceWithdrawalReview(refreshed)
                updated.notice = lang("PerpsBalanceWithdrawalUpdated")
                guard screen?.update(data: updated, for: request) == true else { return }
                quote = refreshed
                data = updated
            } catch {
                var unavailable = data
                unavailable.status = .unavailable(PerpsFormatting.error(error))
                _ = screen?.update(data: unavailable, for: request)
            }
        }
        let controller = PerpsBalanceWithdrawalReviewVC(data: data) { [self] request in
            guard let screen else { return }
            Task { [self] in
                guard PerpsAvailability.canTrade(context.account, store: store),
                      store.pendingOperation(accountId: context.accountId) == nil else {
                    var unavailable = data
                    unavailable.status = .unavailable(PerpsAvailability.tradingUnavailableReason(context.account, store: store)
                        ?? lang("PerpsOperationPending"))
                    _ = screen.update(data: unavailable, for: request)
                    return
                }
                if quote.expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) {
                    await refreshReview(for: request)
                    return
                }
                // Authentication must authorize this exact displayed quote, even if it expires while entering the code.
                let reviewedQuote = quote
                let header = PerpsWithdrawalConfirmationHeader(amount: data.receiveAmount, title: lang("You Receive"),
                                                              accessibilityPrefix: "perps.withdrawal.authentication")
                let outcome = await confirmReviewed(header: header, from: screen) { [self] token in
                    try await store.executeBalanceWithdrawal(quote: reviewedQuote, enclaveToken: token)
                } replacement: { [self] operation in
                    balanceWithdrawalReplacement(operation)
                }
                switch outcome {
                case .finished:
                    break
                case .needsReview:
                    await refreshReview(for: request)
                case .failed(let message):
                    var restored = data
                    restored.status = .unavailable(message)
                    _ = screen.update(data: restored, for: request)
                case .cancelled:
                    if quote.expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) {
                        await refreshReview(for: request)
                    } else {
                        _ = screen.update(data: data, for: request)
                    }
                }
            }
        }
        screen = controller
        origin.present(WNavigationController(rootViewController: controller), animated: true)
    }

    func balanceWithdrawalReplacement(_ operation: ApiPerpsOperation) -> Replacement {
        guard let controller = makeOperationReceipt(operation, data: PerpsSDKAdapter.balanceWithdrawalReceipt) else {
            return Replacement(viewController: makeOperationStatus(operation))
        }
        return Replacement(viewController: controller, animateAlongside: { [weak controller] in
            controller?.animateToCollapsed()
        })
    }

    private func showFill(_ id: String, from origin: UIViewController) {
        let controller: PerpsPositionReceiptVC
        if let operationId = PerpsTradeActivity.failedOrderOperationID(activityID: id) {
            guard let operation = store.operations[operationId], operation.accountId == context.accountId,
                  let asset = asset(operation.assetId), let receipt = makeOperationReceipt(operation, asset: asset) else { return }
            controller = receipt
        } else {
            guard let fill = store.fill(accountId: context.accountId, id: id),
                  let asset = store.asset(named: fill.coin) else { return }
            let operation = store.operations.values.first {
                $0.accountId == context.accountId && $0.assetId == asset.id && $0.orderId != nil && $0.orderId == fill.oid
            }
            if let operation, let receipt = makeOperationReceipt(operation, asset: asset) {
                controller = receipt
            } else {
                controller = makeReceipt(data: PerpsSDKAdapter.receipt(fill: fill, asset: asset))
            }
        }
        let navigation = WNavigationController(rootViewController: controller)
        controller.prepareForPresentation(from: origin)
        origin.present(navigation, animated: true)
    }

    private func makeReceipt(data: PerpsPositionReceiptDisplayData, onStatus: (() -> Void)? = nil) -> PerpsPositionReceiptVC {
        weak var receipt: PerpsPositionReceiptVC?
        let controller = PerpsPositionReceiptVC(data: data, onShare: {
            guard let receipt else { return }
            let data = receipt.data
            var lines = [data.title + " · " + data.token.name, data.timestamp.dateTimeString]
            if case .balanceWithdrawal(let withdrawal) = data.event {
                lines += [lang("You Receive") + ": " + withdrawal.formattedReceiveAmount,
                          lang("PerpsWithdrawalToWallet") + ": " + withdrawal.destination]
            } else {
                lines += [data.positionSizeTitle + ": " + data.positionSize, lang("Price") + ": " + data.price]
            }
            switch data.event {
            case .closed(let outcome), .liquidated(let outcome):
                lines.append(lang("Profit and Loss") + ": " + outcome.profitLoss.text)
            case .reduced(_, let profitLoss, _):
                lines.append(lang("Profit and Loss") + ": " + profitLoss.text)
            default: break
            }
            if let hash = data.transferID { lines.append(lang("Transfer ID") + ": " + hash) }
            receipt.presentActivityViewController(UIActivityViewController(activityItems: [lines.joined(separator: "\n")], applicationActivities: nil))
        }, onStatus: onStatus)
        receipt = controller
        return controller
    }

    private func makeOperationReceipt(_ initial: ApiPerpsOperation, asset: ApiPerpsAsset) -> PerpsPositionReceiptVC? {
        makeOperationReceipt(initial) { [self] operation in
            PerpsSDKAdapter.receipt(operation: operation, asset: asset, fill: completedFill(operation))
        }
    }

    private func makeOperationReceipt(_ initial: ApiPerpsOperation,
                                      data makeData: @escaping (ApiPerpsOperation) -> PerpsPositionReceiptDisplayData?) -> PerpsPositionReceiptVC? {
        guard let data = makeData(store.operations[initial.id] ?? initial) else { return nil }
        weak var screen: PerpsPositionReceiptVC?
        let controller = makeReceipt(data: data, onStatus: { [self] in
            guard let screen, let operation = store.operations[initial.id] else { return }
            showOperation(operation, from: screen)
        })
        screen = controller
        controller.observe { [weak controller, self] in
            guard let operation = store.operations[initial.id], operation.accountId == context.accountId,
                  let data = makeData(operation) else { return }
            controller?.update(data: data)
        }
        controller.onVisibilityChanged = { [weak controller, store, context] visible in
            guard let controller else { return }
            if visible { store.watch(accountId: context.accountId, every: .seconds(5), by: controller) }
            else { store.unwatch(by: controller) }
        }
        return controller
    }

    private func completedFill(_ operation: ApiPerpsOperation) -> ApiPerpsFill? {
        guard let orderId = operation.orderId, let asset = asset(operation.assetId) else { return nil }
        return store.fills(accountId: context.accountId, assetId: asset.id)?
            .first { $0.oid == orderId && $0.coin == asset.name }
    }

    private func presentPendingOperation(from origin: UIViewController, assetId: String? = nil, kind: String? = nil) -> Bool {
        guard let operation = store.pendingOperation(accountId: context.accountId, assetId: assetId, kind: kind) else { return false }
        showOperation(operation, from: origin)
        return true
    }

    private func makeOperationStatus(_ operation: ApiPerpsOperation) -> PerpsOperationVC {
        weak var screen: UIViewController?
        let controller = PerpsOperationVC(store: store, accountId: context.accountId, operationId: operation.id, onWithdraw: { [self] in
            guard let screen else { return }
            retryWithdrawal(operation.id, from: screen)
        }, onReceipt: { [self] in
            guard let screen, let fill = completedFill(store.operations[operation.id] ?? operation) else { return }
            showFill(fill.id, from: screen)
        })
        screen = controller
        return controller
    }

    private func showOperation(_ operation: ApiPerpsOperation, from origin: UIViewController, replacingOrder: Bool = false) {
        let controller = makeOperationStatus(operation)
        if replacingOrder, let navigation = origin.navigationController, navigation.presentingViewController != nil {
            navigation.setViewControllers([controller], animated: true)
        } else {
            origin.present(WNavigationController(rootViewController: controller), animated: true)
        }
    }

    private func retryWithdrawal(_ id: String, from screen: UIViewController) {
        guard PerpsAvailability.canTrade(context.account, store: store), let operation = store.operations[id], operation.state == "partial" else { return }
        Task { [self] in
            do {
                let amount = try await store.client.prepareWithdrawal(context.accountId, id)
                let token = PerpsFormatting.hyperliquidUsdc
                let header = PerpsWithdrawalConfirmationHeader(
                    amount: TokenAmount(normalizedAmountValue(amount, digits: token.decimals), token),
                    title: lang("PerpsWithdrawReleased"), description: lang("PerpsWithdrawDescription"),
                    accessibilityPrefix: "perps.releasedWithdrawal.authentication")
                let action = ProtectedAction<PerpsWithdrawalConfirmationHeader, PerpsExecutionResult>(account: context.account,
                    software: .custom { [self] token in
                        do {
                            let result = try await store.retryWithdrawal(operation: operation, enclaveToken: token)
                            let receipt = ActionSubmissionReceipt(payload: PerpsExecutionResult(operation: result))
                            if result.state == "running" || result.state == "completed" { return .resolved(.committed(receipt)) }
                            return .resolved(.indeterminate(error: PerpsExecutionError(message: lang("PerpsExecutionUnknown")), receipt: receipt))
                        } catch { return .resolved(.notCommitted(error)) }
                    }, hardware: nil,
                    confirmation: .init(title: lang("PerpsWithdrawReleased"),
                        header: header, requiresFreshAuthentication: true))
                _ = await ProtectedActionExecutor.execute(action, in: .init(screen))
            } catch { AppActions.showError(error: PerpsExecutionError(message: PerpsFormatting.error(error))) }
        }
    }

    private func setVisible(_ visible: Bool) {
        visibility?.cancel()
        visibility = nil
        store.unwatch(by: self)
        guard visible else { return }
        visibility = Task { [weak self] in
            guard let self else { return }
            await store.loadCapabilities()
            guard !Task.isCancelled, PerpsAvailability.canRead(context.account, store: store) else { return }
            store.watch(accountId: context.accountId, every: .seconds(20), by: self)
        }
    }

    func homeDisplayData() -> PerpsHomeDisplayData {
        let accountId = context.accountId
        var data = PerpsHomeAdapter.home(store: store, accountId: accountId)
        data.operationStatus = operationStatus()
        data.showsOnboarding = data.showsOnboarding && !context.settings.dismissedHomeBannerIds.contains(PerpsOnboarding.bannerID)
        let hasSnapshot = store.snapshots[accountId] != nil
        data.positions.isStale = homeSnapshotLoading.update(isStale: store.isSnapshotStale(accountId: accountId), hasData: hasSnapshot)
        data.balanceWithdrawal?.isStale = data.positions.isStale
        data.balanceWithdrawal?.isPreparing = isPreparingBalanceWithdrawal
        data.isMarketStale = homeMarketLoading.update(isStale: store.isMarketStale(), hasData: store.market != nil)
        data.isActivityStale = homeHistoryLoading.update(isStale: store.isHistoryStale(accountId: accountId),
                                                         hasData: store.fills[accountId] != nil)
        if PerpsAvailability.requiresMultichainAccount(context.account, store: store) {
            data.accountNotice = lang("PerpsRequiresMultichainWallet")
            data.showsOnboarding = false
        } else if !PerpsAvailability.canRead(context.account, store: store) {
            data.positions.status = .unavailable(lang(store.isSupported ? "PerpsUnsupportedAccount" : "PerpsUnavailable"))
            data.balanceWithdrawal = nil
            data.showsOnboarding = false
        }
        if data.showsOnboarding, let onboarding = store.market?.onboarding {
            prefetchOnboarding(onboarding)
        }
        return data
    }

    @discardableResult
    func prefetchOnboarding(_ onboarding: ApiPerpsOnboarding) -> Task<Void, Never>? {
        guard onboardingPrefetch?.onboarding != onboarding else { return nil }
        let id = UUID()
        onboardingPrefetch = (id, onboarding)
        return Task { [weak self, prefetchStories] in
            let isComplete = await prefetchStories(onboarding.stories)
            if !isComplete, self?.onboardingPrefetch?.id == id {
                self?.onboardingPrefetch = nil
            }
        }
    }

    private func operationStatus() -> PerpsOperationStatusDisplayData? {
        store.visibleOperationStatus(accountId: context.accountId).map { operation in
            let symbol = asset(operation.assetId)?.symbol ?? operation.assetId.components(separatedBy: ":").last ?? ""
            return .init(title: PerpsFormatting.operationTitle(operation, symbol: symbol),
                         message: PerpsFormatting.operationMessage(operation), onSelect: { [weak self] in
                guard let self, let home else { return }
                showOperation(operation, from: home)
            }, onDismiss: { [store, accountId = context.accountId] in
                store.dismissOperationStatus(id: operation.id, accountId: accountId)
            })
        }
    }

    private func canTrade(assetId: String, kind: String? = nil) -> Bool {
        PerpsAvailability.canTrade(context.account, store: store)
            && asset(assetId)?.tradingAvailability?.isAvailable == true
            && store.pendingOperation(accountId: context.accountId, assetId: assetId, kind: kind) == nil
    }
    private func asset(_ id: String) -> ApiPerpsAsset? { store.asset(id: id) }
    private func position(_ id: String) -> ApiPerpsAccountPosition? { store.snapshots[context.accountId]?.positions.first { $0.id == id } }
}

/// The chart period a market or position screen shows, and what has been read for each of its periods.
@MainActor private final class PerpsChartSelection {
    private(set) var period = ApiPriceHistoryPeriod(rawValue: AppStorageHelper.selectedCurrentTokenPeriod()) ?? .day
    private let store: PerpsStore
    private let assetId: String
    private var finishedPeriods = Set<ApiPriceHistoryPeriod>()
    private var freshPeriods = Set<ApiPriceHistoryPeriod>()
    private var generation = UUID()

    init(store: PerpsStore, assetId: String) {
        self.store = store
        self.assetId = assetId
    }

    /// The selected period's points: nil until its first read finishes, then empty if that read found none.
    var history: [[Double]]? {
        store.chart(assetId: assetId, period: period.rawValue) ?? (finishedPeriods.contains(period) ? [] : nil)
    }

    /// Whether the selected period still shows a chart that has not been read since the screen selected it.
    func isRestored() -> Bool {
        let isChartStale = store.isChartRestored(assetId: assetId, period: period.rawValue)
        if !isChartStale { freshPeriods.insert(period) }
        return isChartStale && !freshPeriods.contains(period)
    }

    /// Selects a period and reads its chart. `onUpdate` runs at once, and after the read unless another period took over.
    func select(_ selected: ApiPriceHistoryPeriod, onUpdate: @escaping () -> Void) {
        period = selected
        AppStorageHelper.save(currentTokenPeriod: selected.rawValue)
        freshPeriods.remove(selected)
        let request = UUID(); generation = request
        onUpdate()
        Task {
            await store.refreshChart(assetId: assetId, period: selected.rawValue)
            finishedPeriods.insert(selected)
            guard generation == request else { return }
            onUpdate()
        }
    }
}

private struct PerpsExecutionResult: MfaProtectedActionResult {
    let operation: ApiPerpsOperation
    var mfaRequestHash: String? { nil }
}
private enum PerpsReviewedOutcome {
    case finished
    case needsReview
    case failed(String)
    case cancelled
}
private struct PerpsExecutionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
