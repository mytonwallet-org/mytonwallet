import Foundation
import UIComponents
import WalletCore
import WalletContext

@MainActor public enum PerpsSDKAdapter {
    public static var usdc: ApiToken { PerpsFormatting.usdc }

    /// The USDC a balance-funded order spends on Hyperliquid.
    public static var hyperliquidUsdc: ApiToken { PerpsFormatting.hyperliquidUsdc }

    /// The Hyperliquid balance is offered as a payment source only above this many dollars.
    static let minimumHyperliquidBalance: Decimal = 0.25

    /// The two USDC balances an order can pay from.
    public struct FundingBalances: Equatable, Sendable {
        public var wallet: String?
        /// Spendable from the Hyperliquid balance in the asset's book.
        public var hyperliquid: String?

        public init(wallet: String?, hyperliquid: String?) {
            self.wallet = wallet
            self.hyperliquid = hyperliquid
        }
    }

    public static func market(_ asset: ApiPerpsAsset, canTrade: Bool, period: ApiPriceHistoryPeriod = .day,
                              history: [[Double]]? = nil, tradingUnavailableReason: String? = nil) -> PerpsMarketDisplayData {
        let available = canTrade && asset.tradingAvailability?.isAvailable == true
        let unavailableReason = tradingUnavailableReason
            ?? lang(asset.tradingAvailability?.reason ?? "PerpsUnavailable")
        let interval = asset.context.fundingIntervalHours.flatMap { duration(seconds: Double($0) * 3600, units: [.hour]) }
        return .init(title: L10n.perpsMarketTitle(asset: asset.displayName ?? asset.symbol),
              token: PerpsFormatting.token(asset), price: Double(asset.context.markPx),
              percentChange24h: asset.context.percentChange24h, period: period, history: history, description: asset.description ?? "",
              fundingRate: fundingRate(asset).map { $0 + (interval.map { " · " + $0 } ?? "") }, maxLeverage: "\(asset.maxLeverage)x",
              volume24h: asset.context.dayNtlVlm.flatMap(Double.init).map { formatCompactNumber($0, currency: MBaseCurrency.USD.sign) },
              openInterest: asset.context.openInterestUsd.flatMap(Double.init).map { formatCompactNumber($0, currency: MBaseCurrency.USD.sign) },
              canTrade: available, tradingUnavailableReason: available ? nil : unavailableReason)
    }

    public static func position(_ position: ApiPerpsAccountPosition, asset: ApiPerpsAsset,
                                fills: [ApiPerpsFill], canTrade: Bool, history: [[Double]]? = nil,
                                tradingUnavailableReason: String? = nil) -> PerpsPositionDisplayData {
        let market = market(asset, canTrade: canTrade, history: history, tradingUnavailableReason: tradingUnavailableReason)
        let recent = fills.filter { $0.coin == asset.name }
        let openedAt = recent.first.flatMap {
            $0.positionSize != nil && $0.positionSize == position.size && $0.positionSide == position.side
                ? $0.positionOpenedAt : nil
        }
        let historyFills = openedAt.map { start in recent.filter { $0.positionOpenedAt == start } } ?? recent
        var profitLoss = PerpsFormatting.profitLoss(position.raw.unrealizedPnl)
        let profitLossAmount = PerpsFormatting.usd(position.raw.unrealizedPnl)
        if let ratio = position.returnOnEquity.flatMap(Double.init), ratio.isFinite, profitLossAmount.optionalAmount != nil {
            profitLoss.text = formatPercent(ratio) + " · " + profitLossAmount.formatted(.baseCurrencyEquivalent, showMinus: false)
        }
        var data = PerpsPositionDisplayData(id: position.id, market: market,
              direction: position.side, leverage: position.raw.leverage.value,
              equity: PerpsFormatting.usd(position.equity), profitLoss: profitLoss,
              invested: PerpsFormatting.money(position.collateral), entryPrice: PerpsFormatting.money(position.raw.entryPx),
              liquidationPrice: position.raw.liquidationPx.map { PerpsFormatting.money($0) },
              positionSize: PerpsFormatting.money(position.raw.positionValue) + " · " + PerpsFormatting.quantity(position.size, symbol: asset.symbol),
              fundingPayments: PerpsFormatting.profitLoss(position.funding),
              activities: historyFills.map { PerpsTradeActivity(fill: $0, asset: asset) })
        if openedAt == nil { data.activityTitle = lang("Recent Market Activity") }
        return data
    }

    public static func order(asset: ApiPerpsAsset, account: MAccount, side: PerpsTradeDirection,
                             input: PerpsOrderInput, position: ApiPerpsAccountPosition? = nil,
                             quote: ApiPerpsQuote? = nil,
                             fundingRequirements: ApiPerpsFundingRequirements? = nil,
                             balances: FundingBalances? = nil) -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: PerpsFormatting.token(asset), direction: side,
                                         paymentToken: input.funding == .balance ? hyperliquidUsdc : usdc,
                                         input: input, maxLeverage: asset.maxLeverage)
        data.account = account
        data.walletBalance = balances?.wallet
        // A selected balance stays switchable after it falls below the minimum.
        data.hyperliquidBalance = balances?.hyperliquid.flatMap {
            input.funding == .balance || (Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) ?? 0) > minimumHyperliquidBalance
                ? $0 : nil
        }
        let requirements = fundingRequirements ?? quote?.fundingRequirements
        data.availableCollateral = requirements?.availableCollateral.map { .init(text: $0) }
        data.price = PerpsFormatting.money(quote?.markPrice ?? asset.context.markPx)
        data.fundingRate = fundingRate(asset)
        data.fundingRequirement = fundingRequirement(requirements, isEditing: position != nil)
        if let position {
            let collateral = quote?.previousCollateral ?? position.collateral
            let current = currentInput(collateral)
            data.editingPosition = .init(id: position.id, currentInput: current, currentCollateral: collateral,
                                         currentAmount: PerpsFormatting.money(current.text),
                                         currentLeverage: quote?.previousLeverage ?? position.raw.leverage.value,
                                         change: quote.flatMap {
                                             switch $0.kind {
                                             case "increase": .increase
                                             case "reduce": .reduce
                                             default: nil
                                             }
                                         },
                                         liquidationPrice: (quote?.liquidationPrice ?? position.raw.liquidationPx).map { PerpsFormatting.money($0) })
            if input.amount == current {
                data.positionSize = PerpsFormatting.money(position.raw.positionValue)
                data.conversion = PerpsFormatting.quantity(position.size, symbol: asset.symbol)
            }
        }
        if let quote {
            // A reduction releases its margin to the wallet; the selected funding stays for a later increase.
            if quote.kind == "reduce" { data.paymentToken = usdc }
            data.status = quote.kind == "unchanged" ? .idle : .ready
            data.positionSize = PerpsFormatting.money(quote.notional)
            data.paymentAmount = quote.kind == "unchanged" ? nil
                : quote.receiveStatus == .pending ? quote.estimatedReceiveAmount.map { "≈ " + $0 } : quote.paymentAmount
            data.conversion = PerpsFormatting.quantity(quote.size, symbol: asset.symbol)
            // A balance-funded order crosses no bridge.
            data.bridgeFee = quote.funding == .balance ? nil : PerpsFormatting.money(quote.estimatedFees?.bridge ?? quote.bridgeFee)
            data.tradingFee = quote.estimatedFees.map { estimatedMoney($0.trading) }
            data.networkFee = networkFee(quote)
            data.leverageEstimate = leverageEstimate(quote)
            if quote.kind != "unchanged" {
                data.editingPosition?.liquidationPrice = quote.estimatedLiquidationPrice.map(estimatedMoney)
            }
        }
        return data
    }

    /// A position's collateral in cents, as the order screen enters it.
    public static func currentInput(_ collateral: String) -> TradeAmountInput {
        Decimal(string: collateral, locale: Locale(identifier: "en_US_POSIX")).map(TradeAmountInput.cents) ?? .init(text: collateral)
    }

    /// The SDK draft for the order screen's input. A percentage and the current collateral are sent as intents,
    /// which the SDK applies to the exact balance or collateral that the amount shows in cents.
    public static func draft(assetId: String, side: PerpsTradeDirection, input: PerpsOrderInput, isEditing: Bool) -> ApiPerpsDraft {
        ApiPerpsDraft(assetId: assetId, side: side, amount: input.amount.text, leverage: input.leverage, editing: isEditing,
                      fraction: input.fraction, reset: isEditing && input.intent == .current,
                      funding: input.funding == .balance ? .balance : nil)
    }

    public static func fundingRequirement(_ requirements: ApiPerpsFundingRequirements?, isEditing: Bool = false) -> PerpsOrderDisplayData.FundingRequirement? {
        guard let requirements, requirements.needsUsdc || requirements.needsEth else { return nil }
        let amount: (String) -> String = { value in
            Decimal(string: value)?.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6))) ?? value
        }
        let usdc = fundingUsdc(requirements)
        let eth = amount(requirements.requiredEth)
        if requirements.needsUsdc && requirements.needsEth {
            return .init(title: lang("PerpsFundingMissingTitle"),
                         message: L10n.perpsFundingMissing(minUSDC: usdc, feeETH: eth),
                         buttonTitle: lang("Not Enough Funds"), actionTitle: L10n.buyToken(token: "USDC"), action: .buyUsdc)
        } else if requirements.needsUsdc {
            let message = if let (amount, fees) = fundingUsdcBreakdown(requirements) {
                isEditing ? L10n.perpsFundingUsdcIncreaseFees(minUSDC: usdc, amount: amount, fees: fees)
                    : L10n.perpsFundingUsdcFees(minUSDC: usdc, amount: amount, fees: fees)
            } else {
                isEditing ? L10n.perpsFundingUsdcIncrease(minUSDC: usdc) : L10n.perpsFundingUsdc(minUSDC: usdc)
            }
            return .init(title: L10n.notEnoughSymbolLowercase(symbol: "USDC"), message: message,
                         buttonTitle: L10n.notEnoughSymbol(symbol: "USDC"), actionTitle: L10n.buyToken(token: "USDC"), action: .buyUsdc)
        } else {
            return .init(title: lang("PerpsFundingGasTitle"),
                         message: L10n.perpsFundingGas(feeETH: eth, feeFiat: PerpsFormatting.money(requirements.requiredEthUsd)),
                         buttonTitle: L10n.notEnoughSymbol(symbol: "ETH"), actionTitle: L10n.buyToken(token: "ETH"), action: .buyEth)
        }
    }

    /// Deposit plus the gasless paymaster reserve. Buying only the deposit leaves the reserve unpaid.
    private static func fundingUsdc(_ requirements: ApiPerpsFundingRequirements) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let deposit = Decimal(string: requirements.requiredUsdc, locale: locale) else {
            return requirements.requiredUsdc
        }
        let gas = Decimal(string: requirements.requiredGasUsdc, locale: locale) ?? 0
        return (deposit + gas).formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6)))
    }

    /// The order amount, as the minimum-amount warning states it, and the bridge and paymaster fees on top of it.
    private static func fundingUsdcBreakdown(_ requirements: ApiPerpsFundingRequirements) -> (amount: String, fees: String)? {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let deposit = Decimal(string: requirements.requiredUsdc, locale: locale),
              let bridgeFee = requirements.requiredBridgeFeeUsdc.flatMap({ Decimal(string: $0, locale: locale) }) else { return nil }
        let amount = deposit - bridgeFee
        let fees = bridgeFee + (Decimal(string: requirements.requiredGasUsdc, locale: locale) ?? 0)
        guard amount > 0, fees > 0 else { return nil }
        let format = Decimal.FormatStyle.number.locale(.forNumberFormatters).precision(.fractionLength(0...6))
        return (amount.formatted(format), fees.formatted(format))
    }

    public static func balanceWithdrawalReview(_ quote: ApiPerpsBalanceWithdrawalQuote) -> PerpsBalanceWithdrawalReviewDisplayData {
        let token = hyperliquidUsdc
        return .init(token: token,
              receiveAmount: TokenAmount(normalizedAmountValue(quote.receiveAmount, digits: token.decimals), token),
              amount: PerpsFormatting.quantity(quote.amount, symbol: "USDC"),
              fee: formatWithdrawalFee(quote),
              bridgeFee: PerpsFormatting.quantity(quote.bridgeFee, symbol: "USDC"),
              firstTransferFee: quote.firstTransferFee.map { PerpsFormatting.quantity($0, symbol: "USDC") },
              destination: formatStartEndAddress(quote.destination))
    }

    public static func balanceWithdrawalReceipt(_ operation: ApiPerpsOperation) -> PerpsPositionReceiptDisplayData? {
        guard let quote = operation.balanceWithdrawal else { return nil }
        var withdrawal = balanceWithdrawalReview(quote)
        // A refused withdrawal leaves the USDC on the balance, so nothing is on its way.
        if operation.state == "failed" { withdrawal.receiveAmount.optionalAmount = nil }
        var data = PerpsPositionReceiptDisplayData(balanceWithdrawal: withdrawal, timestamp: operation.createdAt)
        switch operation.state {
        case "running": data.status = operation.stage == "withdrawal" ? .submitted : .pending
        case "completed": data.status = .completed
        case "failed": data.status = .failed(PerpsFormatting.operationMessage(operation))
        default: data.status = .attention(PerpsFormatting.operationMessage(operation))
        }
        return data
    }

    public static func review(_ quote: ApiPerpsQuote, asset: ApiPerpsAsset) -> PerpsOrderReviewDisplayData {
        var data = PerpsOrderReviewDisplayData(token: PerpsFormatting.token(asset), direction: quote.side,
            leverage: quote.leverage, margin: PerpsFormatting.usd(quote.estimatedCollateral ?? quote.collateral),
            positionSize: PerpsFormatting.money(quote.notional), price: PerpsFormatting.money(quote.markPrice),
            liquidationPrice: quote.estimatedLiquidationPrice.map(estimatedMoney),
            paymentAmount: PerpsFormatting.quantity(quote.paymentAmount, symbol: "USDC")
                + (quote.funding == .balance ? " · " + ApiChain.hyperliquid.config.title : ""),
            fee: quote.estimatedFees.map { estimatedFee($0.total) }, paymentToken: quote.funding == .balance ? hyperliquidUsdc : usdc)
        data.isEstimated = quote.kind != "close"
        data.feeRows = quote.estimatedFees.map {
            feeRows($0, estimated: true, format: estimatedFee, bridges: quote.funding != .balance)
        } ?? []
        // The total covers USDC trading fees. Deposit gas follows it, in ETH or in USDC when the deposit is gasless.
        if let network = networkFee(quote) {
            data.feeRows.append(.init(id: "network", title: lang("Network Fee"), value: network))
        }
        data.remainingCollateral = positiveRemainder(quote.estimatedRemainingCollateral, estimated: true)
        data.accountNotice = quote.switchesToUnified == true ? lang("PerpsSwitchesToUnifiedAccount") : nil
        let previous = PerpsPositionChange(margin: PerpsFormatting.usd(quote.previousCollateral),
                                          positionSize: PerpsFormatting.money(quote.previousNotional),
                                          liquidationPrice: quote.liquidationPrice.map { PerpsFormatting.money($0) })
        data.positionID = quote.kind == "open" ? nil : quote.accountId + "/" + quote.assetId
        switch quote.kind {
        case "increase": data.mode = .increase(previous)
        case "reduce": data.mode = .reduce(previous)
        case "leverage": data.status = .unavailable(lang("PerpsUnavailable"))
        case "close":
            data.mode = .close(.init(invested: PerpsFormatting.money(quote.previousCollateral),
                                     currentValue: PerpsFormatting.money(quote.equity), entryPrice: PerpsFormatting.money(quote.entryPrice)))
            data.margin = PerpsFormatting.usd(quote.profitLoss)
            data.positionSize = PerpsFormatting.money(quote.previousNotional)
        default: break
        }
        if quote.kind == "reduce" || quote.kind == "close" {
            data.paymentAmount = quote.estimatedReceiveAmount.map { "≈ " + PerpsFormatting.quantity($0, symbol: "USDC") } ?? "—"
        }
        return data
    }

    public static func receipt(fill: ApiPerpsFill, asset: ApiPerpsAsset) -> PerpsPositionReceiptDisplayData {
        let pnl = PerpsFormatting.profitLoss(fill.netPnl)
        let receivedAmount = fill.eventKind == .closed && fill.withdrawal?.status == "completed" ? fill.withdrawal?.receivedAmount : nil
        let outcome = PerpsPositionOutcome(invested: PerpsFormatting.money(fill.collateralBefore),
                                          closingValue: PerpsFormatting.money(receivedAmount), entryPrice: PerpsFormatting.money(fill.entryPrice),
                                          exitPrice: PerpsFormatting.money(fill.px), profitLoss: pnl, heldDuration: heldDuration(fill),
                                          closingValueAmount: PerpsFormatting.usd(receivedAmount))
        let previous = PerpsPositionChange(margin: PerpsFormatting.usd(fill.collateralBefore), positionSize: PerpsFormatting.money(fill.previousNotional), liquidationPrice: nil)
        let event: PerpsPositionReceiptDisplayData.Event = switch fill.eventKind {
        case .liquidated: .liquidated(outcome)
        case .closed: .closed(outcome)
        case .reduced: .reduced(previous, profitLoss: pnl, entryPrice: PerpsFormatting.money(fill.entryPrice))
        case .increased: .increased(previous)
        case .opened: .opened
        }
        let positionSize = fill.eventKind.endsPosition ? fill.previousNotional : fill.positionNotional
        var data = PerpsPositionReceiptDisplayData(token: PerpsFormatting.token(asset), direction: fill.positionSide,
                     leverage: fill.leverage ?? 0, margin: PerpsFormatting.usd(fill.eventKind.endsPosition ? fill.netPnl : fill.collateralAfter),
                     timestamp: fill.time, positionSize: PerpsFormatting.money(positionSize), price: PerpsFormatting.money(fill.px), liquidationPrice: nil,
                     paymentAmount: fill.deposit.map { PerpsFormatting.quantity($0.grossAmount, symbol: "USDC") }
                        ?? fill.withdrawal.map { $0.status == "completed" ? PerpsFormatting.quantity($0.receivedAmount, symbol: "USDC") : "—" } ?? "—",
                     fee: PerpsFormatting.quantity(fill.receiptFees?.total ?? fill.fee, symbol: fill.feeToken),
                     transferID: fill.deposit?.txHash ?? fill.withdrawal?.txHash, event: event)
        let tradeSize = PerpsFormatting.usd(fill.notional)
        if tradeSize.optionalAmount != nil, tradeSize.amount >= 0 {
            if !fill.eventKind.endsPosition, data.margin.optionalAmount == nil {
                data.summaryTradeSize = tradeSize
            }
            if PerpsFormatting.usd(positionSize).optionalAmount == nil {
                data.positionSize = PerpsFormatting.money(fill.notional)
                data.isTradeSize = true
            }
        }
        if let fees = fill.receiptFees { data.feeRows = feeRows(fees, estimated: false) }
        return data
    }

    public static func receipt(operation: ApiPerpsOperation, asset: ApiPerpsAsset,
                               fill: ApiPerpsFill? = nil) -> PerpsPositionReceiptDisplayData? {
        guard let quote = operation.reviewedQuote else { return nil }
        let position = operation.receiptPosition
        let isClose = operation.kind == "close"
        let partialFill = operation.error == "PerpsPartialFill"
        let withdrawalRejected = operation.isWithdrawalRejected
        let canUseEstimate = !partialFill && !withdrawalRejected && ["running", "completed"].contains(operation.state)
        let settledFees = operation.receiptDetails?.fees ?? fill?.receiptFees
        let receivedAmount: String? = if let withdrawal = fill?.withdrawal {
            withdrawal.status == "completed" ? withdrawal.receivedAmount : nil
        } else {
            operation.receiptDetails?.receiveAmount
        }
        let price = (fill?.px ?? operation.averagePrice).map { PerpsFormatting.money($0) }
            ?? (canUseEstimate ? estimatedMoney(quote.markPrice) : "—")
        let previous = PerpsPositionChange(margin: PerpsFormatting.usd(fill?.collateralBefore ?? quote.previousCollateral),
            positionSize: PerpsFormatting.money(fill?.previousNotional ?? quote.previousNotional),
            liquidationPrice: quote.liquidationPrice.map { PerpsFormatting.money($0) })
        var pnl = PerpsFormatting.profitLoss(fill?.netPnl)
        if isClose, fill == nil, canUseEstimate, let profitLoss = quote.profitLoss {
            pnl = PerpsFormatting.profitLoss(profitLoss)
            pnl.text = "≈ " + pnl.text
        }
        let event: PerpsPositionReceiptDisplayData.Event
        switch operation.kind {
        case "increase": event = .increased(previous)
        case "reduce": event = .reduced(previous, profitLoss: pnl, entryPrice: PerpsFormatting.money(fill?.entryPrice ?? quote.entryPrice))
        case "leverage": event = .leverageChanged
        case "close": event = .closed(.init(invested: PerpsFormatting.money(fill?.collateralBefore ?? quote.previousCollateral),
            closingValue: PerpsFormatting.money(receivedAmount),
            entryPrice: PerpsFormatting.money(fill?.entryPrice ?? quote.entryPrice),
            exitPrice: price, profitLoss: pnl,
            heldDuration: fill.flatMap { heldDuration($0) }, closingValueAmount: PerpsFormatting.usd(receivedAmount)))
        default: event = .opened
        }
        var data = PerpsPositionReceiptDisplayData(token: PerpsFormatting.token(asset),
            direction: fill?.positionSide ?? quote.side, leverage: fill?.leverage ?? quote.leverage,
            margin: PerpsFormatting.usd(isClose ? (fill?.netPnl ?? (canUseEstimate ? quote.profitLoss : nil))
                : fill?.collateralAfter ?? position?.collateral ?? (canUseEstimate ? quote.estimatedCollateral ?? quote.collateral : nil)),
            timestamp: fill?.time ?? operation.createdAt,
            positionSize: isClose ? PerpsFormatting.money(fill?.previousNotional ?? quote.previousNotional)
                : (fill?.positionNotional ?? position?.raw.positionValue).map { PerpsFormatting.money($0) }
                    ?? (canUseEstimate ? estimatedMoney(quote.notional) : "—"),
            price: price,
            liquidationPrice: position?.raw.liquidationPx.map { PerpsFormatting.money($0) }
                ?? (canUseEstimate ? quote.estimatedLiquidationPrice.map(estimatedMoney) : nil),
            paymentAmount: isClose || operation.kind == "reduce"
                ? receivedAmount.map { PerpsFormatting.quantity($0, symbol: "USDC") } ?? "—"
                : PerpsFormatting.quantity(fill?.deposit?.grossAmount ?? quote.paymentAmount, symbol: "USDC"),
            fee: settledFees.map { PerpsFormatting.quantity($0.total, symbol: "USDC") }
                ?? fill.map { PerpsFormatting.quantity($0.fee, symbol: $0.feeToken) }
                ?? (canUseEstimate ? quote.estimatedFees.map { estimatedQuantity($0.total) } : nil) ?? lang("PerpsFeesAtExecution"),
            transferID: fill?.deposit?.txHash ?? fill?.withdrawal?.txHash ?? operation.depositTxHash, event: event)
        if let fees = settledFees {
            data.feeRows = feeRows(fees, estimated: false)
        } else if canUseEstimate, let fees = quote.estimatedFees {
            data.feeRows = feeRows(fees, estimated: true)
            data.feesAreEstimated = true
        }
        if let details = operation.receiptDetails {
            data.remainingCollateral = positiveRemainder(details.remainingCollateral, estimated: false)
        } else if canUseEstimate {
            data.remainingCollateral = positiveRemainder(quote.estimatedRemainingCollateral, estimated: true)
        }
        data.isEstimated = canUseEstimate && (isClose ? fill?.netPnl == nil : fill?.collateralAfter == nil && position == nil)
        switch operation.state {
        case "running":
            data.status = partialFill ? .attention(lang("PerpsPartialFill"))
                : ["deposit", "trade", "withdrawal"].contains(operation.stage) ? .submitted : .pending
        case "failed": data.status = .failed(PerpsFormatting.errorMessage(operation.error))
        case "partial": data.status = .attention(lang("PerpsWithdrawalPending"))
        case "completed":
            data.status = withdrawalRejected ? .attention(PerpsFormatting.errorMessage(operation.error))
                : partialFill ? .attention(lang("PerpsPartialFill")) : .completed
        default: data.status = .attention(lang("PerpsExecutionUnknown"))
        }
        return data
    }

    public static func leverageEstimate(_ estimate: ApiPerpsLeverageEstimate) -> PerpsOrderDisplayData.LeverageEstimate {
        .init(leverage: estimate.leverage, liquidationPrice: estimate.liquidationPrice.map(estimatedMoney))
    }

    private static func leverageEstimate(_ quote: ApiPerpsQuote) -> PerpsOrderDisplayData.LeverageEstimate {
        .init(leverage: quote.leverage,
              liquidationPrice: (quote.estimatedLiquidationPrice ?? (quote.kind == "unchanged" ? quote.liquidationPrice : nil)).map(estimatedMoney))
    }

    private static func estimatedMoney(_ amount: String) -> String { "≈ " + PerpsFormatting.money(amount) }
    private static func estimatedQuantity(_ amount: String) -> String { "≈ " + PerpsFormatting.quantity(amount, symbol: "USDC") }

    private static func estimatedFee(_ amount: String) -> String {
        let value = PerpsFormatting.usd(amount)
        guard let fixedAmount = value.optionalAmount else { return "—" }
        if fixedAmount == 0, let decimal = Decimal(string: amount), decimal > 0 {
            return BaseCurrencyAmount(1, .USD).formatted(.baseCurrencyEquivalent, precision: .lessThan)
        }
        return "≈ " + value.formatted(.baseCurrencyEquivalent)
    }

    /// Arbitrum gas of the deposit a quote makes; absent when the quote does not deposit.
    private static func networkFee(_ quote: ApiPerpsQuote) -> String? {
        if let usdc = quote.estimatedNetworkFeeUsdc {
            return "≈ " + PerpsFormatting.quantity(usdc, symbol: "USDC")
        }
        if let usd = quote.estimatedNetworkFeeUsd { return estimatedFee(usd) }
        if let eth = quote.estimatedNetworkFeeEth { return "≈ " + PerpsFormatting.quantity(eth, symbol: "ETH") }
        // A deposit pays gas even when the SDK could not estimate it; the Hyperliquid balance pays none.
        let deposits = quote.funding != .balance && quote.receiveStatus != .pending && (Decimal(string: quote.paymentAmount) ?? 0) > 0
        return deposits ? "—" : nil
    }

    private static func formatWithdrawalFee(_ quote: ApiPerpsBalanceWithdrawalQuote) -> String {
        guard let bridgeFee = Decimal(string: quote.bridgeFee),
              let firstTransferFee = Decimal(string: quote.firstTransferFee ?? "0") else { return "—" }
        return PerpsFormatting.quantity(NSDecimalNumber(decimal: bridgeFee + firstTransferFee).stringValue, symbol: "USDC")
    }

    private static func fundingRate(_ asset: ApiPerpsAsset) -> String? {
        asset.context.fundingPercent.flatMap { Decimal(string: $0) }.map {
            $0.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6))) + "%"
        }
    }

    private static func positiveRemainder(_ amount: String?, estimated: Bool) -> String? {
        guard let amount, let value = Decimal(string: amount), value > 0 else { return nil }
        return (estimated ? "≈ " : "") + PerpsFormatting.quantity(amount, symbol: "USDC")
    }

    /// An order paid from the Hyperliquid balance crosses no bridge, so it has no bridge row.
    private static func feeRows(_ fees: ApiPerpsFees, estimated: Bool, format: ((String) -> String)? = nil,
                                bridges: Bool = true) -> [PerpsFeeRow] {
        let format = format ?? { (estimated ? "≈ " : "") + PerpsFormatting.quantity($0, symbol: "USDC") }
        var rows: [PerpsFeeRow] = []
        if let exchange = fees.exchange, let service = fees.service {
            rows += [.init(id: "exchange", title: lang("PerpsExchangeFee"), value: format(exchange)),
                     .init(id: "service", title: lang("PerpsServiceFee"), value: format(service))]
        } else {
            rows.append(.init(id: "trading", title: lang("Trading Fee"), value: format(fees.trading)))
        }
        if bridges { rows.append(.init(id: "bridge", title: lang("PerpsBridgeFee"), value: fees.bridge.map(format) ?? "—")) }
        if let firstTransfer = fees.firstTransfer {
            rows.append(.init(id: "firstTransfer", title: lang("PerpsFirstWithdrawalFee"), value: format(firstTransfer)))
        }
        if fees.bridge != nil {
            rows.append(.init(id: "total", title: lang("PerpsTotalFees"), value: format(fees.total)))
        }
        return rows
    }

    private static func heldDuration(_ fill: ApiPerpsFill) -> String? {
        guard let openedAt = fill.positionOpenedAt, openedAt <= fill.time else { return nil }
        return duration(seconds: Double(fill.time - openedAt) / 1000, units: [.day, .hour, .minute])
    }

    private static func duration(seconds: Double, units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        var calendar = LocalizationSupport.shared.calendar
        calendar.locale = LocalizationSupport.shared.locale
        formatter.calendar = calendar
        formatter.allowedUnits = units
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }
}
