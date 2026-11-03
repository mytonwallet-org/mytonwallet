import UIKit
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
    private var observations: [ObserveToken] = []
    private var orderFundingObservation: ObserveToken?
    private var polling: Task<Void, Never>?
    private weak var home: PerpsHomeVC?
    private var didLoadCapabilities = false
    private var homeSnapshotLoading = PerpsInitialLoadingState()
    private var homeMarketLoading = PerpsInitialLoadingState()
    private var homeHistoryLoading = PerpsInitialLoadingState()

    deinit { polling?.cancel() }

    init(accountId: String, store: PerpsStore = .shared) {
        context = AccountContext(accountId: accountId)
        self.store = store
        context.onAccountDeleted = { [weak self, weak store] in
            store?.removeAccount(accountId)
            self?.polling?.cancel()
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
            case .position(let id): showPosition(id, from: home)
            case .marketToken(_, let id): showMarket(id, from: home)
            case .marketSection(let id):
                guard let section = PerpsHomeAdapter.home(store: store, accountId: accountId, previewMarkets: false).marketSections.first(where: { $0.id == id }) else { return }
                var loading = PerpsInitialLoadingState()
                let render: () -> [MarketItemDisplayData] = { [store] in
                    let tokens = PerpsHomeAdapter.home(store: store, accountId: accountId, previewMarkets: false)
                        .marketSections.first { $0.id == id }?.tokens ?? []
                    let isStale = loading.update(isStale: store.isMarketStale(accountId: accountId),
                                                 hasData: store.snapshots[accountId] != nil)
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
                observations.append(observe { [weak list] in list?.update(tokens: render()) })
                home.navigationController?.pushViewController(list, animated: true)
            case .activity(let id): showFill(id, from: home)
            }
        }
        home = controller
        observations.append(observe { [weak controller, weak self] in
            guard let self else { return }
            controller?.update(data: homeDisplayData())
            controller?.updateOperationStatus(store.visibleOperationStatus(accountId: accountId).map { [self] operation in
                let symbol = self.asset(operation.assetId)?.symbol ?? operation.assetId.components(separatedBy: ":").last ?? ""
                return .init(title: PerpsFormatting.operationTitle(operation, symbol: symbol),
                             message: PerpsFormatting.operationMessage(operation), onSelect: { [weak controller, self] in
                    if let controller { self.showOperation(operation, from: controller) }
                }, onDismiss: { [store = self.store] in store.dismissOperationStatus(id: operation.id, accountId: accountId) })
            })
        })
        controller.onLoadMoreActivity = { [store, context] in Task { await store.loadMoreHistory(accountId: context.accountId) } }
        controller.onVisibilityChanged = { [self] in setVisible($0) }
        controller.onOpenOnboarding = { [weak controller] source in
            guard let controller, controller.presentedViewController == nil else { return }
            let stories = PerpsOnboarding.makeViewController()
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
            for index in data.positions.indices { data.positions[index].isStale = data.isStale }
            return data
        }
        let list = PerpsPositionsVC(data: render()) { [self, weak home] action in
            switch action {
            case .position(let id): if let home { showPosition(id, from: home) }
            case .refresh: Task { await store.reconcile(accountId: context.accountId) }
            default: break
            }
        }
        observations.append(observe { [weak list] in list?.update(data: render()) })
        list.onVisibilityChanged = { [self] in setVisible($0) }
        home.navigationController?.pushViewController(list, animated: true)
    }

    func showMarket(_ id: String, from origin: UIViewController) {
        if let position = store.snapshots[context.accountId]?.positions.first(where: { $0.assetId == id }) {
            showPosition(position.id, from: origin)
            return
        }
        guard let asset = asset(id) else { return }
        var period: ApiPriceHistoryPeriod = .day
        var finishedPeriods = Set<ApiPriceHistoryPeriod>()
        var freshPeriods = Set<ApiPriceHistoryPeriod>()
        var snapshotLoading = PerpsInitialLoadingState()
        var generation = UUID()
        weak var screen: PerpsMarketVC?
        let render: () -> PerpsMarketDisplayData = { [store, context] in
            let history = store.chart(accountId: context.accountId, assetId: id, period: period.rawValue)
                ?? (finishedPeriods.contains(period) ? [] : nil)
            var data = PerpsSDKAdapter.market(store.snapshots[context.accountId]?.assets.first { $0.id == id } ?? asset,
                canTrade: PerpsAvailability.canTrade(context.account, store: store), period: period, history: history,
                tradingUnavailableReason: PerpsAvailability.tradingUnavailableReason(context.account, store: store))
            let isChartStale = store.isChartRestored(accountId: context.accountId, assetId: id, period: period.rawValue)
            if !isChartStale { freshPeriods.insert(period) }
            data.isHistoryRestored = isChartStale && !freshPeriods.contains(period)
            data.isStale = snapshotLoading.update(isStale: store.isMarketStale(accountId: context.accountId),
                                                  hasData: store.snapshots[context.accountId] != nil)
            return data
        }
        let load: (ApiPriceHistoryPeriod) -> Void = { [store, context] selected in
            period = selected
            freshPeriods.remove(selected)
            let request = UUID(); generation = request
            screen?.update(data: render())
            Task {
                await store.refreshChart(accountId: context.accountId, assetId: id, period: selected.rawValue)
                finishedPeriods.insert(selected)
                guard generation == request else { return }
                screen?.update(data: render())
            }
        }
        let controller = PerpsMarketVC(data: render(), onSelectPeriod: load) { [self] side in
            guard let screen else { return }
            showOrder(asset: asset, side: side, from: screen)
        }
        screen = controller
        controller.onVisibilityChanged = { [self] in setVisible($0) }
        observations.append(observe { [weak controller] in controller?.update(data: render()) })
        origin.navigationController?.pushViewController(controller, animated: true)
        load(.day)
        Task { await store.refreshAsset(accountId: context.accountId, assetId: id) }
    }

    func showPosition(_ id: String, from origin: UIViewController) {
        guard let position = position(id), let asset = asset(position.assetId) else { return }
        weak var screen: PerpsPositionVC?
        var finishedPeriods = Set<ApiPriceHistoryPeriod>()
        var freshPeriods = Set<ApiPriceHistoryPeriod>()
        var snapshotLoading = PerpsInitialLoadingState()
        var historyLoading = PerpsInitialLoadingState()
        var period: ApiPriceHistoryPeriod = .day
        var generation = UUID()
        let render: () -> PerpsPositionDisplayData = { [store, context] in
            let current = store.snapshots[context.accountId]?.positions.first { $0.id == id }
            let chart = store.chart(accountId: context.accountId, assetId: asset.id, period: period.rawValue)
                ?? (finishedPeriods.contains(period) ? [] : nil)
            var data = PerpsSDKAdapter.position(current ?? position, asset: store.snapshots[context.accountId]?.assets.first { $0.id == asset.id } ?? asset,
                fills: store.fills[context.accountId] ?? [], canTrade: PerpsAvailability.canTrade(context.account, store: store) && current != nil,
                history: chart, tradingUnavailableReason: PerpsAvailability.tradingUnavailableReason(context.account, store: store))
            data.market.period = period
            let isChartStale = store.isChartRestored(accountId: context.accountId, assetId: asset.id, period: period.rawValue)
            if !isChartStale { freshPeriods.insert(period) }
            data.market.isHistoryRestored = isChartStale && !freshPeriods.contains(period)
            data.market.isStale = snapshotLoading.update(isStale: store.isSnapshotStale(accountId: context.accountId),
                                                         hasData: store.snapshots[context.accountId] != nil)
            data.isActivityStale = historyLoading.update(isStale: store.isHistoryStale(accountId: context.accountId),
                                                         hasData: store.fills[context.accountId] != nil)
            if current == nil { data.equity.optionalAmount = nil }
            return data
        }
        let load: (ApiPriceHistoryPeriod) -> Void = { [store, context] selected in
            period = selected
            freshPeriods.remove(selected)
            let request = UUID(); generation = request
            screen?.update(data: render())
            Task {
                await store.refreshChart(accountId: context.accountId, assetId: asset.id, period: selected.rawValue)
                finishedPeriods.insert(selected)
                guard generation == request else { return }
                screen?.update(data: render())
            }
        }
        let controller = PerpsPositionVC(data: render(), onSelectPeriod: load) { [self] action in
            guard let screen else { return }
            switch action {
            case .edit:
                guard let current = self.position(id) else { return }
                showOrder(asset: asset, side: current.side == "long" ? .long : .short, position: current, from: screen)
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
        observations.append(observe { [weak controller] in controller?.update(data: render()) })
        origin.navigationController?.pushViewController(controller, animated: true)
        load(.day)
        Task { await store.refreshAsset(accountId: context.accountId, assetId: asset.id) }
    }

    private func showOrder(asset: ApiPerpsAsset, side: PerpsTradeDirection, position: ApiPerpsAccountPosition? = nil,
                           from origin: UIViewController) {
        if position == nil, let current = store.snapshots[context.accountId]?.positions.first(where: { $0.assetId == asset.id }) {
            showPosition(current.id, from: origin)
            return
        }
        let entryKind = position == nil ? "open" : "reduce"
        guard !presentPendingOperation(from: origin, assetId: asset.id, kind: entryKind) else { return }
        guard canTrade(assetId: asset.id, kind: entryKind), let asset = self.asset(asset.id) else { return }
        let input = PerpsOrderInput(amount: position?.collateral ?? "", leverage: position?.raw.leverage.value ?? min(2, asset.maxLeverage))
        var data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side, input: input, position: position)
        data.status = .loading
        weak var screen: PerpsOrderVC?
        var generation = UUID()
        let controller = PerpsOrderVC(data: data, loadLeverageEstimates: { [self] input in
            let draft = ApiPerpsDraft(assetId: asset.id, side: side == .long ? "long" : "short", amount: input.amount.text,
                                      unit: "currency", leverage: input.leverage, editing: position != nil,
                                      leverageOnly: position != nil)
            if position != nil {
                return [PerpsSDKAdapter.leverageOption(try await store.client.preview(context.accountId, draft))]
            }
            return PerpsSDKAdapter.leverageOptions(try await store.client.leverageEstimates(context.accountId, draft))
        }, loadEstimate: { [self] input in
            let draft = ApiPerpsDraft(assetId: asset.id, side: side == .long ? "long" : "short", amount: input.amount.text,
                                     leverage: input.leverage, editing: position != nil, leverageOnly: input.leverageOnly)
            let quote = try await store.client.preview(context.accountId, draft)
            return PerpsSDKAdapter.order(asset: self.asset(asset.id) ?? asset, account: context.account, side: side,
                                         input: input, position: position, quote: quote)
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
                var draft = ApiPerpsDraft(assetId: asset.id, side: side == .long ? "long" : "short", amount: input.amount.text,
                    unit: "currency", leverage: input.leverage, editing: position != nil,
                    leverageOnly: input.leverageOnly)
                if request.action == .resetAmount { draft.reset = true }
                var requirements: ApiPerpsFundingRequirements?
                do {
                    let isEmptyOpening = position == nil && !input.hasAmount
                    if request.action == .refreshFunding || isEmptyOpening || data.fundingRequirement != nil {
                        requirements = try await store.client.fundingRequirements(context.accountId, draft)
                        guard generation == requestID, let screen else { return }
                        guard canTrade(assetId: asset.id, kind: entryKind) else {
                            throw PerpsExecutionError(message: self.asset(asset.id)?.tradingAvailability?.reason ?? "PerpsUnavailable")
                        }
                        if isEmptyOpening || requirements?.needsUsdc == true || requirements?.needsEth == true
                            || (request.action == .refreshFunding && input.amount.text == position?.collateral && draft.leverageOnly != true) {
                            data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side,
                                input: input, position: position, fundingRequirements: requirements)
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
                    let availableCollateral = data.availableCollateral
                    data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side, input: input,
                                                 position: position, quote: quote, fundingRequirements: requirements)
                    data.availableCollateral = data.availableCollateral ?? availableCollateral
                    data.canUseFractions = position != nil || data.availableCollateral != nil
                    _ = screen.update(data: data, for: request)
                    if request.action == .review && quote.kind != "unchanged" { showReview(quote, draft: draft, asset: asset, from: screen) }
                } catch {
                    if requirements == nil, String(describing: error).contains("PerpsInsufficient") {
                        requirements = try? await store.client.fundingRequirements(context.accountId, draft)
                    }
                    guard generation == requestID else { return }
                    let availableCollateral = data.availableCollateral
                    data = PerpsSDKAdapter.order(asset: asset, account: context.account, side: side,
                        input: input, position: position, fundingRequirements: requirements)
                    data.availableCollateral = data.availableCollateral ?? availableCollateral
                    data.canUseFractions = position != nil || data.availableCollateral != nil
                    if data.fundingRequirement == nil { data.status = .unavailable(PerpsFormatting.error(error)) }
                    _ = screen?.update(data: data, for: request)
                }
            }
        }
        screen = controller
        var lastFundingBalances = [context.balances[PerpsSDKAdapter.usdc.slug], context.balances[ARBITRUM_SLUG]]
        orderFundingObservation = observe { [weak controller, context] in
            guard let controller else { return }
            let balances = [context.balances[PerpsSDKAdapter.usdc.slug], context.balances[ARBITRUM_SLUG]]
            guard balances != lastFundingBalances else { return }
            lastFundingBalances = balances
            guard controller.presentedViewController == nil,
                  controller.navigationController?.topViewController === controller else { return }
            controller.refreshBlockedFunding()
        }
        let nav = WNavigationController(rootViewController: controller)
        origin.present(nav, animated: true)
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
                var needsReview = false
                let action = ProtectedAction<PerpsTradeConfirmationHeader, PerpsExecutionResult>(account: context.account,
                    software: .custom { [self] token in
                        do {
                            let result = try await store.execute(quote: reviewedQuote, enclaveToken: token)
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
                    confirmation: .init(title: lang("Confirm"), header: PerpsTradeConfirmationHeader(data: data), requiresFreshAuthentication: true),
                    completion: .replace { [self] receipt in
                        guard let operation = receipt.payload?.operation,
                              let controller = makeOperationReceipt(operation, asset: asset) else { return nil }
                        return Replacement(viewController: controller, animateAlongside: { [weak controller] in
                            controller?.animateToCollapsed()
                        })
                    })
                let outcome = await ProtectedActionExecutor.execute(action, in: .init(screen))
                switch outcome {
                case .completed:
                    break // ProtectedAction has already replaced confirmation with the receipt.
                case .partiallyCommitted(let receipt, _):
                    if let operation = receipt.payload?.operation { showOperation(operation, from: screen, replacingOrder: true) }
                case .indeterminate(_, let receipt):
                    if let operation = receipt?.payload?.operation { showOperation(operation, from: screen, replacingOrder: true) }
                case .failed(let error):
                    if needsReview {
                        await refreshReview(for: request)
                    } else {
                        var restored = data
                        restored.status = .unavailable(error.localizedDescription)
                        _ = screen.update(data: restored, for: request)
                    }
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

    private func showFill(_ id: String, from origin: UIViewController) {
        if let flow = store.cashFlows[context.accountId]?.first(where: { $0.id == id && $0.kind != .funding }) {
            let asset = store.snapshots[context.accountId]?.assets.first { $0.id == flow.assetId || $0.name == flow.coin }
            let controller = PerpsCashFlowDetailsVC(data: PerpsHomeAdapter.cashFlowDetails(flow, asset: asset))
            origin.present(WNavigationController(rootViewController: controller), animated: true)
            return
        }
        guard let fill = store.fills[context.accountId]?.first(where: { $0.id == id }), fill.eventKind != nil,
              let asset = store.snapshots[context.accountId]?.assets.first(where: { $0.name == fill.coin }) else { return }
        let operation = store.operations.values.first {
            $0.accountId == context.accountId && $0.assetId == asset.id && $0.orderId != nil && $0.orderId == fill.oid
        }
        let controller: PerpsPositionReceiptVC
        if let operation, let receipt = makeOperationReceipt(operation, asset: asset) {
            controller = receipt
        } else {
            controller = makeReceipt(data: PerpsSDKAdapter.receipt(fill: fill, asset: asset))
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
            var lines = [data.title + " · " + data.token.name,
                         PerpsFormatting.date(data.timestamp),
                         data.positionSizeTitle + ": " + data.positionSize,
                         lang("Price") + ": " + data.price]
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
        let operation = store.operations[initial.id] ?? initial
        guard let data = PerpsSDKAdapter.receipt(operation: operation, asset: asset, fill: completedFill(operation)) else { return nil }
        weak var screen: PerpsPositionReceiptVC?
        let controller = makeReceipt(data: data, onStatus: { [self] in
            guard let screen, let operation = store.operations[initial.id] else { return }
            showOperation(operation, from: screen)
        })
        screen = controller
        controller.observe { [weak controller, self] in
            guard let operation = store.operations[initial.id], operation.accountId == context.accountId,
                  let data = PerpsSDKAdapter.receipt(operation: operation, asset: asset, fill: completedFill(operation)) else { return }
            controller?.update(data: data)
        }
        var polling: Task<Void, Never>?
        controller.onVisibilityChanged = { [weak controller, self] visible in
            polling?.cancel()
            polling = nil
            guard visible else { return }
            polling = Task { [weak controller, store, context] in
                while !Task.isCancelled, controller != nil {
                    if UIApplication.shared.applicationState == .active { await store.reconcile(accountId: context.accountId) }
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
        }
        return controller
    }

    private func completedFill(_ operation: ApiPerpsOperation) -> ApiPerpsFill? {
        guard let orderId = operation.orderId, let asset = asset(operation.assetId) else { return nil }
        return store.fills[context.accountId]?.first { $0.oid == orderId && $0.coin == asset.name && $0.eventKind != nil }
    }

    private func presentPendingOperation(from origin: UIViewController, assetId: String? = nil, kind: String? = nil) -> Bool {
        guard let operation = store.pendingOperation(accountId: context.accountId, assetId: assetId, kind: kind) else { return false }
        showOperation(operation, from: origin)
        return true
    }

    private func showOperation(_ operation: ApiPerpsOperation, from origin: UIViewController, replacingOrder: Bool = false) {
        weak var screen: UIViewController?
        let controller = PerpsOperationVC(store: store, accountId: context.accountId, operationId: operation.id, onWithdraw: { [self] in
            guard let screen else { return }
            retryWithdrawal(operation.id, from: screen)
        }, onReceipt: { [self] in
            guard let screen, let fill = completedFill(store.operations[operation.id] ?? operation) else { return }
            showFill(fill.id, from: screen)
        })
        screen = controller
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
                let action = ProtectedAction<PerpsWithdrawalHeader, PerpsExecutionResult>(account: context.account,
                    software: .custom { [self] token in
                        do {
                            let result = try await store.retryWithdrawal(operation: operation, enclaveToken: token)
                            let receipt = ActionSubmissionReceipt(payload: PerpsExecutionResult(operation: result))
                            if result.state == "running" || result.state == "completed" { return .resolved(.committed(receipt)) }
                            return .resolved(.indeterminate(error: PerpsExecutionError(message: lang("PerpsExecutionUnknown")), receipt: receipt))
                        } catch { return .resolved(.notCommitted(error)) }
                    }, hardware: nil,
                    confirmation: .init(title: lang("PerpsWithdrawReleased"),
                        header: PerpsWithdrawalHeader(amount: amount), requiresFreshAuthentication: true))
                _ = await ProtectedActionExecutor.execute(action, in: .init(screen))
            } catch { AppActions.showError(error: PerpsExecutionError(message: PerpsFormatting.error(error))) }
        }
    }

    private func setVisible(_ visible: Bool) {
        polling?.cancel()
        polling = nil
        guard visible else { return }
        polling = Task { [weak self, store, context] in
            while !Task.isCancelled {
                if UIApplication.shared.applicationState == .active {
                    if !store.hasResolvedCapabilities {
                        await store.loadCapabilities()
                        self?.didLoadCapabilities = true
                    }
                    guard !Task.isCancelled else { return }
                    if PerpsAvailability.canRead(context.account, store: store) {
                        await store.reconcile(accountId: context.accountId)
                        await self?.refreshHomeCharts()
                    } else {
                        guard let self else { return }
                        var data = homeDisplayData()
                        data.positions.status = .unavailable(lang(store.hasResolvedCapabilities ? "PerpsUnsupportedAccount" : "PerpsUnavailable"))
                        home?.update(data: data)
                        if store.hasResolvedCapabilities { return }
                    }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func refreshHomeCharts() async {
        guard home?.viewIfLoaded?.window != nil else { return }
        let assets = PerpsHomeAdapter.featuredAssets(store.snapshots[context.accountId]).filter { $0.sparkline == nil }
        guard !assets.isEmpty else { return }
        for asset in assets {
            guard !Task.isCancelled else { return }
            guard !store.isChartFresh(accountId: context.accountId, assetId: asset.id,
                                      period: ApiPriceHistoryPeriod.day.rawValue, maxAge: 300) else { continue }
            await store.refreshChart(accountId: context.accountId, assetId: asset.id, period: ApiPriceHistoryPeriod.day.rawValue)
        }
        guard !Task.isCancelled else { return }
        home?.update(data: homeDisplayData())
    }

    private func homeDisplayData() -> PerpsHomeDisplayData {
        var charts: [String: [[Double]]] = [:]
        for asset in PerpsHomeAdapter.featuredAssets(store.snapshots[context.accountId]) {
            charts[asset.id] = store.chart(accountId: context.accountId, assetId: asset.id, period: ApiPriceHistoryPeriod.day.rawValue)
        }
        var data = PerpsHomeAdapter.home(store: store, accountId: context.accountId, charts: charts)
        data.showsOnboarding = data.showsOnboarding && !context.settings.dismissedHomeBannerIds.contains(PerpsOnboarding.bannerID)
        let isSnapshotStale = homeSnapshotLoading.update(isStale: store.isSnapshotStale(accountId: context.accountId),
                                                         hasData: store.snapshots[context.accountId] != nil)
        data.positions.isStale = isSnapshotStale
        for index in data.positions.positions.indices { data.positions.positions[index].isStale = isSnapshotStale }
        let isMarketStale = homeMarketLoading.update(isStale: store.isMarketStale(accountId: context.accountId),
                                                     hasData: store.snapshots[context.accountId] != nil)
        for section in data.marketSections.indices {
            for item in data.marketSections[section].tokens.indices {
                data.marketSections[section].tokens[item].isStale = isMarketStale
            }
        }
        let isHistoryStale = homeHistoryLoading.update(isStale: store.isHistoryStale(accountId: context.accountId),
                                                       hasData: store.fills[context.accountId] != nil)
        for index in data.activities.indices { data.activities[index].isStale = isHistoryStale }
        if didLoadCapabilities && !PerpsAvailability.canRead(context.account, store: store) {
            data.positions.status = .unavailable(lang(store.hasResolvedCapabilities ? "PerpsUnsupportedAccount" : "PerpsUnavailable"))
            data.showsOnboarding = false
        }
        return data
    }

    private func canTrade(assetId: String, kind: String? = nil) -> Bool {
        PerpsAvailability.canTrade(context.account, store: store)
            && asset(assetId)?.tradingAvailability?.isAvailable == true
            && store.pendingOperation(accountId: context.accountId, assetId: assetId, kind: kind) == nil
    }
    private func asset(_ id: String) -> ApiPerpsAsset? { store.snapshots[context.accountId]?.assets.first { $0.id == id } }
    private func position(_ id: String) -> ApiPerpsAccountPosition? { store.snapshots[context.accountId]?.positions.first { $0.id == id } }
}

private struct PerpsExecutionResult: MfaProtectedActionResult {
    let operation: ApiPerpsOperation
    var mfaRequestHash: String? { nil }
}
private struct PerpsExecutionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct PerpsWithdrawalHeader: ConfirmationContent {
    let amount: String
    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: amount + " USDC").textStyle(.screenTitle, content: .technical)
            Text(lang("PerpsWithdrawDescription"))
        }.padding(24)
    }
    var compactRepresentation: some View { body }
}
