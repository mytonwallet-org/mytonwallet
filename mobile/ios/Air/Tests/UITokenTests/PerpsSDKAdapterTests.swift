import Foundation
import Testing
import WalletContext
import WalletCore
import WalletResources
@testable import UIToken

@Suite @MainActor
struct PerpsSDKAdapterTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func tradingUsesSDKAvailabilityAndOldCacheRemainsReadable() throws {
        var asset = try asset()
        asset.tradingAvailability = nil
        let cached = PerpsSDKAdapter.market(asset, canTrade: true)
        #expect(!cached.canTrade)
        #expect(cached.tradingUnavailableReason != nil)
        #expect(cached.price == 2000)
        #expect(!cached.description.isEmpty)

        asset.tradingAvailability = .init(isAvailable: false, reason: "PerpsTradingUnavailable")
        let unavailable = PerpsSDKAdapter.position(try position(), asset: asset, fills: [], canTrade: true)
        #expect(!unavailable.canEdit && !unavailable.canClose)
        #expect(unavailable.market.tradingUnavailableReason == lang("PerpsTradingUnavailable"))

        asset.tradingAvailability = .init(isAvailable: true)
        let readOnly = PerpsSDKAdapter.market(asset, canTrade: false,
            tradingUnavailableReason: lang("PerpsUnsupportedAccount"))
        #expect(!readOnly.canTrade)
        #expect(readOnly.tradingUnavailableReason == lang("PerpsUnsupportedAccount"))
        let eligible = PerpsSDKAdapter.market(asset, canTrade: true)
        #expect(eligible.canTrade)
        #expect(eligible.tradingUnavailableReason == nil)
    }

    @Test func closeReviewUsesProfitLossAndKeepsEquityInItsOwnRow() throws {
        let quote = try quote()
        let data = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(data.margin == .fromDouble(25, .USD))
        #expect(data.positionSize == PerpsFormatting.money("1000"))
        guard case .close(let closing) = data.mode else { Issue.record("Expected close review"); return }
        #expect(closing.currentValue == PerpsFormatting.money("125"))
        #expect(closing.invested == PerpsFormatting.money("100"))

        var unknownProfit = quote
        unknownProfit.profitLoss = nil
        #expect(PerpsSDKAdapter.review(unknownProfit, asset: try asset()).margin.optionalAmount == nil)
    }

    @Test(arguments: ["opened", "increased", "reduced"])
    func historicalReceiptDoesNotInventMissingMarginOrLeverage(kind: String) throws {
        var fill = try fill()
        fill.eventKind = kind
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin.optionalAmount == nil)
        #expect(data.leverage == 0)
        #expect(data.paymentAmount == "—")
        #expect(data.liquidationPrice == nil)
        #expect(data.event.previous?.margin.optionalAmount == nil)
    }

    @Test(arguments: ["opened", "increased", "reduced"])
    func normalizedHistoryShowsTradeSizeWithoutInventingCollateralChanges(kind: String) throws {
        var fill = try normalizedFill(kind: kind)
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin.optionalAmount == nil)
        #expect(data.summaryTradeSize == .fromDouble(1025, .USD))
        #expect(data.summaryAmount == .fromDouble(1025, .USD))
        #expect(data.summaryTitle == lang("Trade Size"))
        #expect(data.summaryPreviousMargin == nil)
        #expect(data.leverage == 0)
        #expect(data.positionSize == PerpsFormatting.money("1025"))
        #expect(data.positionSizeTitle == lang("Trade Size"))
        #expect(data.isTradeSize)

        fill.collateralBefore = "100"
        fill.previousNotional = "900"
        let withPrevious = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(withPrevious.summaryPreviousMargin == nil)
        #expect(withPrevious.isTradeSize)
    }

    @Test(arguments: ["opened", "increased", "reduced"])
    func knownHistoricalCollateralAndPositionSizeTakePriority(kind: String) throws {
        var fill = try normalizedFill(kind: kind)
        fill.collateralBefore = "100"
        fill.collateralAfter = "125"
        fill.positionNotional = "1500"
        fill.leverage = 10
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin == .fromDouble(125, .USD))
        #expect(data.summaryAmount == .fromDouble(125, .USD))
        #expect(data.summaryTradeSize == nil)
        #expect(data.summaryTitle == nil)
        #expect(data.summaryPreviousMargin == (kind == "opened" ? nil : .fromDouble(100, .USD)))
        #expect(data.positionSize == PerpsFormatting.money("1500"))
        #expect(data.positionSizeTitle == lang("Position Size"))
        #expect(!data.isTradeSize)
        #expect(data.leverage == 10)
    }

    @Test(arguments: ["increased", "reduced"])
    func enrichedHistoryShowsPositionSizeChangesWithoutTreatingTransfersAsCollateral(kind: String) throws {
        let isIncrease = kind == "increased"
        var fill: ApiPerpsFill = try decode("""
        {"activityId":"oid:20","assetId":"eth","coin":"ETH","oid":20,"time":1792866000000,
         "eventKind":"\(kind)","positionSide":"long","px":"2050","sz":"0.5","notional":"1025",
         "previousSize":"\(isIncrease ? "0.4" : "0.9")","positionSize":"\(isIncrease ? "0.9" : "0.4")",
         "previousNotional":"\(isIncrease ? "820" : "1845")","positionNotional":"\(isIncrease ? "1845" : "820")",
         "transferredAmount":"102.5","feeToken":"USDC"}
        """)
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.event.previous?.positionSize == PerpsFormatting.money(isIncrease ? "820" : "1845"))
        #expect(data.positionSize == PerpsFormatting.money(isIncrease ? "1845" : "820"))
        #expect(!data.isTradeSize)
        #expect(data.margin.optionalAmount == nil)
        #expect(data.event.previous?.margin.optionalAmount == nil)
        #expect(data.summaryTradeSize == .fromDouble(1025, .USD))
        #expect(data.leverage == 0)
        #expect(data.paymentAmount == "—")
        #expect(data.liquidationPrice == nil)
        if isIncrease {
            fill.deposit = try decode("""
            {"grossAmount":"102.7","bridgeFee":"0.2","creditedAmount":"102.5"}
            """)
        } else {
            fill.withdrawal = try decode("""
            {"amount":"102.5","bridgeFee":"0.2","receivedAmount":"102.3","status":"completed"}
            """)
        }
        let settled = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(settled.paymentAmount == PerpsFormatting.quantity(isIncrease ? "102.7" : "102.3", symbol: "USDC"))
    }

    @Test(arguments: ["closed", "liquidated"])
    func normalizedClosedHistoryKeepsProfitLossAndKnownOutcomeValues(kind: String) throws {
        var fill = try normalizedFill(kind: kind)
        fill.collateralBefore = "100"
        fill.withdrawal = try decode("""
        {"amount":"124.3","bridgeFee":"0.2","receivedAmount":"124.1","status":"completed"}
        """)
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin == .fromDouble(24.1, .USD))
        #expect(data.summaryAmount == .fromDouble(24.1, .USD))
        #expect(data.summaryTradeSize == nil)
        #expect(data.summaryTitle == nil)
        #expect(data.positionSize == PerpsFormatting.money("1025"))
        #expect(data.isTradeSize)
        let outcome = try #require(data.event.outcome)
        #expect(outcome.invested == PerpsFormatting.money("100"))
        #expect(outcome.closingValue == (kind == "closed" ? PerpsFormatting.money("124.1") : "—"))
        #expect(data.expandedSummaryAmount == BaseCurrencyAmount(kind == "closed" ? 124_100_000 : 24_100_000, .USD))

        fill.withdrawal?.status = "pending"
        let pending = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(pending.event.outcome?.closingValue == "—")
        if kind == "closed" { #expect(pending.expandedSummaryAmount.optionalAmount == nil) }
    }

    @Test(arguments: ["opened", "increased", "reduced", "closed", "liquidated", "unknown"])
    func unavailableHistoricalAmountsRemainUnknown(kind: String) throws {
        var fill = try normalizedFill(kind: kind)
        fill.notional = nil
        fill.netPnl = nil
        let data = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin.optionalAmount == nil)
        #expect(data.summaryAmount.optionalAmount == nil)
        #expect(data.summaryTradeSize == nil)
        #expect(data.summaryTitle == nil)
        #expect(data.positionSize == "—")
        #expect(!data.isTradeSize)
        #expect(data.leverage == 0)

        fill.notional = "-1025"
        let invalid = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(invalid.summaryTradeSize == nil)
        #expect(!invalid.isTradeSize)
        if kind == "unknown" {
            fill.notional = "1025"
            let unknown = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
            #expect(unknown.summaryTradeSize == nil)
            #expect(!unknown.isTradeSize)
        }
    }

    @Test func closedReceiptUsesNetProfitAfterFeesAndItsPreviousPositionSize() throws {
        let data = PerpsSDKAdapter.receipt(fill: try fill(), asset: try asset())
        #expect(data.margin == .fromDouble(24.1, .USD))
        #expect(data.positionSize == PerpsFormatting.money("1000"))
        guard case .closed(let outcome) = data.event else { Issue.record("Expected closed receipt"); return }
        #expect(outcome.profitLoss.text == PerpsFormatting.profitLoss("24.1"))
        #expect(outcome.profitLoss.tone == .positive)
        #expect(outcome.invested == "—")
        #expect(data.fee == PerpsFormatting.quantity("0.3", symbol: "USDC"))
    }

    @Test(arguments: ["close", "reduce"])
    func pendingReceiveDoesNotShowThePaymentPlaceholderAsZero(kind: String) throws {
        var quote = try quote()
        quote.kind = kind
        let data = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(data.paymentQuantity == nil)
        #expect(data.paymentAmount == "—")
        #expect(data.paymentToken?.symbol == "USDC")
        #expect(!data.canSelectPayment)

        quote.receiveAmount = "123.45"
        let resolved = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(resolved.paymentQuantity == "123.45")
        #expect(resolved.paymentAmount == PerpsFormatting.quantity("123.45", symbol: "USDC"))
    }

    @Test func initialEditPreservesCurrentFiatLiquidationSizeAndAssetConversion() throws {
        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        let position = try position()
        let input = PerpsOrderInput(amount: "100", leverage: 10)
        let data = PerpsSDKAdapter.order(asset: try asset(), account: account, side: .long, input: input, position: position)
        #expect(data.status == .idle)
        #expect(data.editingPosition?.currentInput.text == "100")
        #expect(data.editingPosition?.currentAmount == PerpsFormatting.money("100"))
        #expect(data.editingPosition?.liquidationPrice == PerpsFormatting.money("1800"))
        #expect(data.positionSize == PerpsFormatting.money("1000"))
        #expect(data.conversion == PerpsFormatting.quantity("0.5", symbol: "ETH"))
        #expect(!data.canSelectPayment)
    }

    @Test func marketUsesSDKFundingUnitsAndUsdInterestWithoutInventingDistribution() throws {
        var asset = try asset()
        let data = PerpsSDKAdapter.market(asset, canTrade: true)
        #expect(data.title == L10n.perpsMarketTitle(asset: "Ethereum"))
        #expect(data.description == "Ethereum perpetual futures.")
        #expect(data.fundingRate == "0.01% · 8h")
        #expect(data.openInterest == AssetInfoFormatting.compactCurrency(1_000_000, currency: .USD))
        #expect(data.distribution == nil)
        #expect(data.canTrade)

        asset.context.fundingPercent = nil
        asset.context.openInterestUsd = nil
        asset.description = nil
        asset.tradingAvailability = .init(isAvailable: false, reason: "PerpsTradingUnavailable")
        let partial = PerpsSDKAdapter.market(asset, canTrade: true)
        #expect(partial.fundingRate == nil)
        #expect(partial.openInterest == nil)
        #expect(partial.distribution == nil)
        #expect(partial.description.isEmpty)
        #expect(!partial.canTrade)
    }

    @Test func submittedReceiptRetainsReviewedAmountsThenUsesCorrelatedSettlement() throws {
        var quote = try quote()
        quote.kind = "increase"
        quote.collateral = "200"
        quote.paymentAmount = "100.2"
        quote.notional = "2000"
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "increase", createdAt: quote.createdAt)
        operation.reviewedQuote = quote
        operation.stage = "deposit"
        let pending = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(pending.status == .submitted)
        #expect(pending.title == lang("Position Increased"))
        #expect(pending.canShare)
        #expect(pending.margin == .fromDouble(200, .USD))
        #expect(pending.summaryTradeSize == nil)
        #expect(pending.summaryTitle == nil)
        #expect(!pending.isTradeSize)
        #expect(pending.event.previous?.margin == .fromDouble(100, .USD))
        #expect(pending.leverage == 10)
        #expect(pending.isEstimated)

        var position = try position()
        position.collateral = "199.8"
        operation.receiptPosition = position
        operation.state = "completed"
        operation.orderId = 20
        var fill = try fill()
        fill.eventKind = "increased"
        fill.positionNotional = "1998"
        let settled = PerpsSDKAdapter.receipt(fill: fill, asset: try asset(), operation: operation)
        #expect(settled.status == .completed)
        #expect(settled.canShare)
        #expect(settled.title == lang("Position Increased"))
        #expect(settled.margin == .fromDouble(199.8, .USD))
        #expect(settled.summaryTradeSize == nil)
        #expect(settled.summaryPreviousMargin == .fromDouble(100, .USD))
        #expect(!settled.isTradeSize)
        #expect(settled.leverage == 10)
        #expect(!settled.isEstimated)
        #expect(settled.liquidationPrice == PerpsFormatting.money("1800"))
        #expect(settled.price == PerpsFormatting.money("2050"))
        #expect(settled.paymentAmount == PerpsFormatting.quantity("100.2", symbol: "USDC"))
        #expect(settled.fee == PerpsFormatting.quantity("0.3", symbol: "USDC"))

        fill.oid = 21
        #expect(PerpsSDKAdapter.receipt(operation: operation, asset: try asset(), fill: fill) == nil)
        #expect(PerpsSDKAdapter.receipt(fill: fill, asset: try asset(), operation: operation).leverage == 0)
    }

    @Test(arguments: ["open", "increase", "reduce", "close", "leverage"])
    func submittedReceiptsAreOptimisticWithoutChangingExecutionState(kind: String) throws {
        var quote = try quote()
        quote.kind = kind
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: kind, createdAt: quote.createdAt)
        operation.reviewedQuote = quote
        let preparing = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(preparing.status == .pending)
        #expect(!preparing.canShare)
        for stage in ["deposit", "trade", "withdrawal"] {
            operation.stage = stage
            let submitted = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
            #expect(submitted.status == .submitted)
            #expect(submitted.title == submitted.event.title)
            #expect(submitted.status.message == nil)
            #expect(submitted.canShare)
            #expect(operation.state == "running")
            #expect(operation.blocksTrading)
        }
        operation.state = "unknown"
        let unknown = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(unknown.status == .attention(lang("PerpsExecutionUnknown")))
        #expect(!unknown.canShare)
        #expect(unknown.margin.optionalAmount == nil)
        operation.state = "partial"
        let partial = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(partial.status == .attention(lang("PerpsWithdrawalPending")))
        #expect(!partial.canShare)
    }

    @Test func submittedCloseRetainsReviewedReceivePriceAndProfitEstimates() throws {
        var quote = try quote()
        quote.receiveAmount = "124.2"
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "close", createdAt: quote.createdAt)
        operation.reviewedQuote = quote
        operation.stage = "trade"
        let data = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(data.isEstimated)
        #expect(data.margin == PerpsFormatting.usd("25"))
        #expect(data.paymentAmount == "≈ " + PerpsFormatting.quantity("124.2", symbol: "USDC"))
        #expect(data.price == "≈ " + PerpsFormatting.money("2050"))
        guard case .closed(let outcome) = data.event else { Issue.record("Expected close receipt"); return }
        #expect(outcome.profitLoss.text == "≈ " + PerpsFormatting.profitLoss("25"))
        #expect(outcome.exitPrice == data.price)
    }

    @Test func closeReceiptUsesRealizedProfitAndWithdrawalWithoutLosingInvestedAmount() throws {
        let quote = try quote()
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "close", createdAt: quote.createdAt)
        operation.reviewedQuote = quote
        operation.orderId = 20
        operation.state = "completed"
        operation.withdrawalAmount = "124.1"
        operation.receiptDetails = try JSONDecoder().decode(ApiPerpsReceiptDetails.self, from: Data("""
        {"receiveAmount":"123.9"}
        """.utf8))
        let data = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill()))
        #expect(data.margin == .fromDouble(24.1, .USD))
        #expect(!data.isEstimated)
        #expect(data.leverage == 10)
        #expect(data.paymentAmount == PerpsFormatting.quantity("123.9", symbol: "USDC"))
        #expect(data.summaryAmount == BaseCurrencyAmount(24_100_000, .USD))
        #expect(data.expandedSummaryAmount == BaseCurrencyAmount(123_900_000, .USD))
        guard case .closed(let outcome) = data.event else { Issue.record("Expected closed receipt"); return }
        #expect(outcome.invested == PerpsFormatting.money("100"))
        #expect(outcome.profitLoss.tone == .positive)
    }

    @Test func incompleteReceiptsDoNotClaimSuccessOrDisplayAnUnfilledTargetAsActual() throws {
        var quote = try quote()
        quote.kind = "reduce"
        quote.collateral = "50"
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "reduce", createdAt: quote.createdAt)
        operation.reviewedQuote = quote
        operation.state = "completed"
        operation.error = "PerpsPartialFill"
        let partial = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(partial.status == .attention(lang("PerpsPartialFill")))
        #expect(partial.margin.optionalAmount == nil)
        operation.state = "failed"
        operation.error = "PerpsOrderTooSmall"
        let failed = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(failed.title == lang("Failed"))
        #expect(failed.status == .failed(lang("PerpsOrderTooSmall")))
        #expect(!failed.canShare)
        #expect(failed.margin.optionalAmount == nil)
        operation.reviewedQuote?.accountId = "another-wallet"
        #expect(PerpsSDKAdapter.receipt(operation: operation, asset: try asset()) == nil)
    }

    @Test func settledActivityOverridesSavedReceiptAmountsAndFees() throws {
        var quote = try quote()
        quote.kind = "increase"
        quote.collateral = "200"
        quote.paymentAmount = "100.2"
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "increase", createdAt: 1)
        operation.reviewedQuote = quote
        operation.state = "completed"
        operation.orderId = 20
        operation.receiptPosition = try position()
        operation.receiptDetails = try decode("""
        {"fees":{"trading":"1","bridge":"0.2","total":"1.2"}}
        """)
        var fill = try fill()
        fill.eventKind = "increased"
        fill.collateralBefore = "98"
        fill.collateralAfter = "197.5"
        fill.previousNotional = "784"
        fill.positionNotional = "1580"
        fill.transferredAmount = "100"
        fill.leverage = 8
        fill.receiptFees = try decode("""
        {"exchange":"0.1","service":"0.2","trading":"0.3","bridge":"0.22","total":"0.52"}
        """)
        fill.deposit = try decode("""
        {"grossAmount":"100.22","bridgeFee":"0.22","creditedAmount":"100","txHash":"deposit"}
        """)
        let data = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        let historical = PerpsSDKAdapter.receipt(fill: fill, asset: try asset())
        #expect(data.margin == historical.margin)
        #expect(data.margin == PerpsFormatting.usd("197.5"))
        #expect(data.summaryPreviousMargin == PerpsFormatting.usd("98"))
        #expect(data.event.previous?.positionSize == PerpsFormatting.money("784"))
        #expect(data.positionSize == PerpsFormatting.money("1580"))
        #expect(data.positionSize == historical.positionSize)
        #expect(data.leverage == 8)
        #expect(data.paymentAmount == historical.paymentAmount)
        #expect(data.paymentAmount == PerpsFormatting.quantity("100.22", symbol: "USDC"))
        #expect(data.fee == historical.fee)
        #expect(data.fee == PerpsFormatting.quantity("0.52", symbol: "USDC"))
        #expect(data.feeRows.map(\.id) == historical.feeRows.map(\.id))
        #expect(data.feeRows.map(\.value) == historical.feeRows.map(\.value))
        #expect(!data.isEstimated)
    }

    @Test func incompleteActivityFeesUseMatchingSDKBridgeReconciliation() throws {
        var quote = try quote()
        quote.kind = "increase"
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "increase", createdAt: 1)
        operation.reviewedQuote = quote
        operation.state = "completed"
        operation.orderId = 20
        operation.receiptDetails = try decode("""
        {"fees":{"trading":"0.3","bridge":"0.2","total":"0.5"}}
        """)
        var fill = try normalizedFill(kind: "increased")
        let reconciled = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        #expect(reconciled.fee == PerpsFormatting.quantity("0.5", symbol: "USDC"))
        #expect(reconciled.feeRows.map(\.id) == ["exchange", "service", "bridge", "total"])

        fill.receiptFees?.trading = "0.4"
        fill.receiptFees?.total = "0.4"
        let updatedFill = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        #expect(updatedFill.fee == PerpsFormatting.quantity("0.4", symbol: "USDC"))

        fill.receiptFees?.trading = "0.3"
        fill.receiptFees?.total = "0.3"
        fill.receiptFees?.bridge = "0"
        let freeBridge = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        #expect(freeBridge.fee == PerpsFormatting.quantity("0.3", symbol: "USDC"))
    }

    @Test func backendWithdrawalStatusOverridesLocalReceiveFallback() throws {
        let quote = try quote()
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "close", createdAt: 1)
        operation.reviewedQuote = quote
        operation.state = "completed"
        operation.orderId = 20
        operation.receiptDetails = try decode("""
        {"receiveAmount":"123.9"}
        """)
        var fill = try fill()
        fill.collateralBefore = "98"
        fill.withdrawal = try decode("""
        {"amount":"124.3","bridgeFee":"0.22","receivedAmount":"124.08","status":"completed"}
        """)
        let completed = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        #expect(completed.paymentAmount == PerpsFormatting.quantity("124.08", symbol: "USDC"))
        #expect(completed.event.outcome?.closingValue == PerpsFormatting.money("124.08"))
        #expect(completed.event.outcome?.invested == PerpsFormatting.money("98"))
        #expect(completed.expandedSummaryAmount == BaseCurrencyAmount(124_080_000, .USD))
        fill.withdrawal?.status = "pending"
        let pending = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset(), fill: fill))
        #expect(pending.paymentAmount == "—")
        #expect(pending.event.outcome?.closingValue == "—")
        #expect(pending.expandedSummaryAmount.optionalAmount == nil)
    }

    @Test func receiptFeeEstimateStateIsIndependentOfPositionEstimate() throws {
        var quote = try quote()
        quote.kind = "increase"
        quote.estimatedFees = try decode("""
        {"trading":"0.3","bridge":"0.2","total":"0.5"}
        """)
        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "increase", createdAt: 1)
        operation.reviewedQuote = quote
        operation.receiptPosition = try position()
        let estimatedFees = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(!estimatedFees.isEstimated)
        #expect(estimatedFees.feesAreEstimated)

        operation.receiptPosition = nil
        operation.receiptDetails = try decode("""
        {"fees":{"trading":"0.3","bridge":"0.2","total":"0.5"}}
        """)
        let settledFees = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(settledFees.isEstimated)
        #expect(!settledFees.feesAreEstimated)
    }

    @Test func reviewUsesNetEstimateAndBreaksDownFeesWithoutChangingPayment() throws {
        var quote = try quote()
        quote.kind = "increase"
        quote.collateral = "30"
        quote.estimatedCollateral = "29.875652"
        quote.estimatedRemainingCollateral = "0.098066"
        quote.estimatedLiquidationPrice = "40555"
        quote.paymentAmount = "10.313566"
        quote.estimatedFees = try decode("""
        {"exchange":"0.008654","service":"0.017628","trading":"0.026282","bridge":"0.2","total":"0.226282"}
        """)
        let data = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(data.margin == PerpsFormatting.usd("29.875652"))
        #expect(data.isEstimated)
        #expect(data.paymentQuantity == "10.313566")
        #expect(data.liquidationPrice == "≈ " + PerpsFormatting.money("40555"))
        #expect(data.feeRows.map(\.id) == ["exchange", "service", "bridge", "total"])
        #expect(data.fee == "≈ " + PerpsFormatting.usd("0.226282").formatted(.baseCurrencyEquivalent))
        #expect(data.feeRows.last?.value == data.fee)
        #expect(data.feeExplanation == nil)
        #expect(data.feeRows.allSatisfy { !$0.value.contains("USDC") })
        #expect(data.remainingCollateral == "≈ " + PerpsFormatting.quantity("0.098066", symbol: "USDC"))

        var operation = ApiPerpsOperation(id: "operation", accountId: "wallet", assetId: "eth", kind: "increase", createdAt: 1)
        operation.reviewedQuote = quote
        let pending = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(pending.margin == data.margin)
        #expect(pending.liquidationPrice == data.liquidationPrice)
        #expect(pending.remainingCollateral == data.remainingCollateral)
        operation.state = "completed"
        let awaitingDetails = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(awaitingDetails.remainingCollateral == data.remainingCollateral)
        #expect(awaitingDetails.feeRows.map(\.value) == pending.feeRows.map(\.value))
        operation.error = "PerpsPartialFill"
        let partial = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(partial.remainingCollateral == nil)
        #expect(partial.feeRows.isEmpty)
        operation.error = nil
        operation.receiptDetails = try decode("""
        {"fees":{"exchange":"0.008657","service":"0.017636","trading":"0.026293","bridge":"0.2","total":"0.226293"},
         "remainingCollateral":"0.090566"}
        """)
        let settled = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(settled.feeRows.last?.value == PerpsFormatting.quantity("0.226293", symbol: "USDC"))
        #expect(settled.remainingCollateral == PerpsFormatting.quantity("0.090566", symbol: "USDC"))
        operation.receiptDetails?.remainingCollateral = "0"
        let noRemainder = try #require(PerpsSDKAdapter.receipt(operation: operation, asset: asset()))
        #expect(noRemainder.remainingCollateral == nil)
    }

    @Test(arguments: ["0.008654", "0.000001"])
    func reviewFeesKeepBuySellPrecisionForSmallDollarAmounts(amount: String) throws {
        var quote = try quote()
        quote.estimatedFees = try decode("""
        {"exchange":"\(amount)","service":"0","trading":"\(amount)","bridge":"0","total":"\(amount)"}
        """)
        let data = PerpsSDKAdapter.review(quote, asset: try asset())
        let expected = "≈ " + PerpsFormatting.usd(amount).formatted(.baseCurrencyEquivalent)
        #expect(data.fee == expected)
        #expect(data.feeRows.first?.value == expected)
        #expect(data.fee != "≈ " + BaseCurrencyAmount(0, .USD).formatted(.baseCurrencyEquivalent))
    }

    @Test func reviewDistinguishesZeroFeeFromPositiveSubPrecisionFee() throws {
        var quote = try quote()
        quote.kind = "leverage"
        quote.estimatedFees = try decode("""
        {"exchange":"0","service":"0","trading":"0","bridge":"0","total":"0"}
        """)
        let zero = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(zero.fee == "≈ " + BaseCurrencyAmount(0, .USD).formatted(.baseCurrencyEquivalent))
        #expect(zero.feeExplanation == nil)
        quote.estimatedFees?.total = "0.0000004"
        let small = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(small.fee == BaseCurrencyAmount(1, .USD).formatted(.baseCurrencyEquivalent, precision: .lessThan))
        #expect(small.fee != zero.fee)
    }

    @Test func reviewDoesNotTreatMissingFeeEstimateAsZero() throws {
        var quote = try quote()
        quote.estimatedFees = nil
        let data = PerpsSDKAdapter.review(quote, asset: try asset())
        #expect(data.fee == lang("PerpsFeesAtExecution"))
        #expect(data.feeExplanation == lang("PerpsFeesAtExecution"))
        #expect(data.feeRows.isEmpty)
    }

    @Test func leverageSheetUsesSDKPricesForEveryOption() throws {
        let estimates: [ApiPerpsLeverageEstimate] = try decode("""
        [{"leverage":2,"liquidationPrice":"40555"},{"leverage":5,"liquidationPrice":"64000"}]
        """)
        let options = PerpsSDKAdapter.leverageOptions(estimates)
        #expect(options.map(\.value) == [2, 5])
        #expect(options[0].liquidationPrice == "≈ " + PerpsFormatting.money("40555"))
        #expect(options[1].liquidationPrice == "≈ " + PerpsFormatting.money("64000"))
    }

    @Test func orderUsesPreparedLiquidationEstimateAndMarketFundingRate() throws {
        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        var quote = try quote()
        quote.kind = "open"
        quote.estimatedLiquidationPrice = "1850"
        let data = PerpsSDKAdapter.order(asset: try asset(), account: account, side: .long,
                                        input: .init(amount: "100", leverage: 10), quote: quote)
        #expect(data.leverageOptions.first { $0.value == 10 }?.liquidationPrice == "≈ " + PerpsFormatting.money("1850"))
        #expect(data.leverageOptions.first { $0.value == 5 }?.liquidationPrice == nil)
        #expect(data.fundingPayments == "0.01%")
        #expect(data.tradingFee == nil)
    }

    @Test(arguments: ["0", "-0.00125", nil])
    func orderFundingRatePreservesZeroNegativeAndUnknownValues(rate: String?) throws {
        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        var asset = try asset()
        asset.context.fundingPercent = rate
        let data = PerpsSDKAdapter.order(asset: asset, account: account, side: .long, input: .init())
        #expect(data.fundingPayments == rate.map { $0 + "%" })
    }

    @Test func fundingNoticesUseSdkRequirementsAndOfferTheMissingArbitrumAsset() throws {
        var requirements: ApiPerpsFundingRequirements = try decode("""
        {"requiredUsdc":"10.2","requiredEth":"0.0001","requiredEthUsd":"0.25",
         "usdcBalance":"0","ethBalance":"0","needsUsdc":true,"needsEth":true}
        """)
        let both = try #require(PerpsSDKAdapter.fundingRequirement(requirements))
        #expect(both.title == lang("PerpsFundingMissingTitle"))
        #expect(both.message == L10n.perpsFundingMissing(minUSDC: "10.2", feeETH: "0.0001"))
        #expect(both.buttonTitle == lang("Not Enough Funds"))
        #expect(both.action == .buyUsdc)
        requirements.needsEth = false
        let usdc = try #require(PerpsSDKAdapter.fundingRequirement(requirements))
        #expect(usdc.actionTitle == L10n.buyToken(token: "USDC"))
        #expect(usdc.buttonTitle == L10n.notEnoughSymbol(symbol: "USDC"))
        #expect(usdc.message == L10n.perpsFundingUsdc(minUSDC: "10.2"))
        #expect(PerpsSDKAdapter.fundingRequirement(requirements, isEditing: true)?.message
                == L10n.perpsFundingUsdcIncrease(minUSDC: "10.2"))
        requirements.needsUsdc = false
        requirements.needsEth = true
        let eth = try #require(PerpsSDKAdapter.fundingRequirement(requirements))
        #expect(eth.action == .buyEth)
        #expect(eth.actionTitle == L10n.buyToken(token: "ETH"))
        #expect(eth.buttonTitle == L10n.notEnoughSymbol(symbol: "ETH"))
        requirements.needsEth = false
        #expect(PerpsSDKAdapter.fundingRequirement(requirements) == nil)
    }

    @Test func initialOrderCanShowFundingRequirementsWithoutAnAmountOrQuote() throws {
        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        let requirements: ApiPerpsFundingRequirements = try decode("""
        {"requiredUsdc":"10.2","requiredEth":"0.0001","requiredEthUsd":"0.25",
         "usdcBalance":"9","ethBalance":"0.001","needsUsdc":true,"needsEth":false}
        """)
        let data = PerpsSDKAdapter.order(asset: try asset(), account: account, side: .long, input: .init(),
                                        fundingRequirements: requirements)
        #expect(data.input.amount.text.isEmpty)
        #expect(data.fundingRequirement?.action == .buyUsdc)
        #expect(data.networkFee == nil)
        #expect(data.tradingFee == nil)
    }

    @Test(arguments: ["30", "-1.72", "0"])
    func positionHeroUsesSignedPercentageBeforeUnsignedFiatWithoutChangingRows(amount: String) throws {
        var position = try position()
        let ratio = amount == "30" ? "0.3" : amount == "-1.72" ? "-0.0698" : "0"
        position.raw.unrealizedPnl = amount
        position.returnOnEquity = ratio
        var trade = try fill()
        trade.netPnl = amount
        let data = try PerpsSDKAdapter.position(position, asset: asset(), fills: [trade], canTrade: true)
        #expect(data.profitLoss.text == formatPercent(Double(ratio)!) + " · "
            + PerpsFormatting.usd(amount).formatted(.baseCurrencyEquivalent, showMinus: false))
        #expect(data.profitLoss.tone == (amount == "30" ? .positive : amount == "-1.72" ? .negative : .neutral))
        #expect(data.activities[0].amount.text == PerpsFormatting.profitLoss(amount))
        #expect(data.fundingPayments.text == PerpsFormatting.profitLoss("0.3"))
    }

    @Test(arguments: [nil, "unavailable", "nan"])
    func positionHeroPreservesSignedFiatWhenReturnIsUnavailable(ratio: String?) throws {
        var position = try position()
        position.raw.unrealizedPnl = "-1.72"
        position.returnOnEquity = ratio
        let data = try PerpsSDKAdapter.position(position, asset: asset(), fills: [], canTrade: true)
        #expect(data.profitLoss.text == PerpsFormatting.profitLoss("-1.72"))
        #expect(data.profitLoss.tone == .negative)
    }

    @Test func positionActivityContainsTradesAndKeepsFundingInTheSummary() throws {
        var opened = try fill()
        opened.eventKind = "opened"
        opened.positionSize = "0.5"
        opened.positionOpenedAt = opened.time
        let data = try PerpsSDKAdapter.position(position(), asset: asset(), fills: [opened], canTrade: true)
        #expect(data.activities.map(\.id) == [opened.id])
        #expect(data.activities[0].kind == .opened)
        #expect(data.activities[0].canSelect)
        #expect(data.fundingPayments.text == PerpsFormatting.profitLoss("0.3"))
        #expect(data.activityTitle == lang("Activity"))
    }

    @Test func positionActivityUsesOnlyHistoricalLeverageAndLabelsTradeSizeFallback() throws {
        var trade = try normalizedFill(kind: "reduced")
        let unknown = try PerpsSDKAdapter.position(position(), asset: asset(), fills: [trade], canTrade: true)
        #expect(unknown.activityTitle == lang("Recent Market Activity"))
        #expect(unknown.activities[0].title == L10n.perpsActivityReduced(asset: lang("Long")))
        #expect(unknown.activities[0].detail == lang("Trade Size") + ": " + PerpsFormatting.money("1025"))

        trade.leverage = 2
        trade.positionNotional = "1500"
        let known = try PerpsSDKAdapter.position(position(), asset: asset(), fills: [trade], canTrade: true)
        let direction = L10n.perpsLeverageDirection(leverage: 2.formatted(.number.locale(.forNumberFormatters)), direction: lang("Long"))
        #expect(known.activities[0].title == L10n.perpsActivityReduced(asset: direction))
        #expect(known.activities[0].detail == lang("Position Size") + ": " + PerpsFormatting.money("1500"))
    }

    private func asset() throws -> ApiPerpsAsset {
        try decode("""
        {"id":"eth","name":"ETH","symbol":"ETH","displayName":"Ethereum","description":"Ethereum perpetual futures.",
         "chain":"hyperliquid","provider":"hyperliquid","dex":"","szDecimals":4,"maxLeverage":40,
         "tradingAvailability":{"isAvailable":true},
         "context":{"markPx":"2000","prevDayPx":"1950","funding":"0.0001","fundingPercent":"0.01",
                    "fundingIntervalHours":8,"openInterest":"500","openInterestUsd":"1000000","dayNtlVlm":"250000"}}
        """)
    }

    private func quote() throws -> ApiPerpsQuote {
        try decode("""
        {"id":"quote","accountId":"wallet","assetId":"eth","kind":"close","side":"long","leverage":10,
         "inputAmount":"0","currentInputAmount":"100","collateral":"0","previousCollateral":"100",
         "equity":"125","profitLoss":"25","returnOnEquity":"0.25","size":"0","previousSize":"0.5",
         "notional":"0","previousNotional":"1000","markPrice":"2050","entryPrice":"2000","liquidationPrice":"1800",
         "paymentAmount":"0","receiveStatus":"pending","bridgeFee":"0.2","expiresAt":1792866060000,"createdAt":1792866000000}
        """)
    }

    private func position() throws -> ApiPerpsAccountPosition {
        try decode("""
        {"id":"wallet/eth","assetId":"eth","dex":"","side":"long","size":"0.5","collateral":"100","equity":"125",
         "returnOnEquity":"0.25","funding":"0.3","raw":{"coin":"ETH","entryPx":"2000","liquidationPx":"1800",
           "leverage":{"type":"isolated","value":10},"marginUsed":"125","positionValue":"1000",
           "returnOnEquity":"0.25","szi":"0.5","unrealizedPnl":"25"}}
        """)
    }

    private func fill() throws -> ApiPerpsFill {
        try decode("""
        {"coin":"ETH","tid":10,"oid":20,"time":1792866000000,"px":"2050","sz":"0.5","side":"A","dir":"Close Long",
         "startPosition":"0.5","closedPnl":"24.4","fee":"0.3","feeToken":"USDC","eventKind":"closed",
         "positionSide":"long","netPnl":"24.1","notional":"1025","previousNotional":"1000","positionNotional":"0",
         "entryPrice":"2000","endPosition":"0","positionOpenedAt":1792860000000}
        """)
    }

    private func normalizedFill(kind: String) throws -> ApiPerpsFill {
        var fill: ApiPerpsFill = try decode("""
        {"activityId":"oid:20","assetId":"eth","coin":"ETH","oid":20,"fillIds":[10],"time":1792866000000,
         "eventKind":"\(kind)","positionSide":"long","px":"2050","sz":"0.5","notional":"1025",
         "entryPrice":"2000","fee":"0.3","feeToken":"USDC","positionOpenedAt":1792860000000,
         "receiptFees":{"trading":"0.3","service":"0.1","exchange":"0.2","total":"0.3"}}
        """)
        if ["reduced", "closed", "liquidated"].contains(kind) {
            fill.netPnl = "24.1"
            fill.closedPnl = "24.4"
        }
        return fill
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
