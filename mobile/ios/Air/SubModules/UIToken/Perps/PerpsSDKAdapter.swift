import Foundation
import UIComponents
import WalletCore
import WalletContext

@MainActor public enum PerpsSDKAdapter {
    public static var usdc: ApiToken {
        TokenStore.tokens["arbitrum-0xaf88d065"] ?? ApiToken(
            slug: "arbitrum-0xaf88d065", name: "USD Coin", symbol: "USDC", decimals: 6,
            chain: .arbitrum, tokenAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
            image: ApiToken.SOLANA_USDC_MAINNET.image, priceUsd: 1)
    }

    public static func market(_ asset: ApiPerpsAsset, canTrade: Bool, period: ApiPriceHistoryPeriod = .day,
                              history: [[Double]]? = nil, tradingUnavailableReason: String? = nil) -> PerpsMarketDisplayData {
        let available = canTrade && asset.tradingAvailability?.isAvailable == true
        let unavailableReason = tradingUnavailableReason
            ?? lang(asset.tradingAvailability?.reason ?? "PerpsUnavailable")
        let funding = fundingRate(asset)
        let interval = asset.context.fundingIntervalHours.flatMap { hours in
            let formatter = DateComponentsFormatter()
            var calendar = LocalizationSupport.shared.calendar
            calendar.locale = LocalizationSupport.shared.locale
            formatter.calendar = calendar
            formatter.allowedUnits = [.hour]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: Double(hours) * 3600).map { " · " + $0 }
        } ?? ""
        return .init(title: L10n.perpsMarketTitle(asset: asset.displayName ?? asset.symbol),
              token: PerpsFormatting.token(asset), price: Double(asset.context.markPx),
              percentChange24h: asset.context.percentChange24h, period: period, history: history, description: asset.description ?? "",
              fundingRate: funding.map { $0 + interval }, maxLeverage: "\(asset.maxLeverage)x",
              volume24h: asset.context.dayNtlVlm.flatMap(Double.init).map { AssetInfoFormatting.compactCurrency($0, currency: .USD) },
              openInterest: asset.context.openInterestUsd.flatMap(Double.init).map { AssetInfoFormatting.compactCurrency($0, currency: .USD) },
              canTrade: available, tradingUnavailableReason: available ? nil : unavailableReason)
    }

    public static func position(_ position: ApiPerpsAccountPosition, asset: ApiPerpsAsset,
                                fills: [ApiPerpsFill], canTrade: Bool, history: [[Double]]? = nil,
                                tradingUnavailableReason: String? = nil) -> PerpsPositionDisplayData {
        let market = market(asset, canTrade: canTrade, history: history, tradingUnavailableReason: tradingUnavailableReason)
        let recent = fills.filter { $0.coin == asset.name }
        let openedAt = recent.first.flatMap {
            $0.eventKind != nil && $0.positionSize != nil && $0.positionSize == position.size && $0.positionSide == position.side
                ? $0.positionOpenedAt : nil
        }
        let historyFills = (openedAt.map { start in recent.filter { $0.positionOpenedAt == start } } ?? recent)
            .filter { $0.eventKind != nil }
        var profitLoss = value(position.raw.unrealizedPnl)
        let profitLossAmount = PerpsFormatting.usd(position.raw.unrealizedPnl)
        if let ratio = position.returnOnEquity.flatMap(Double.init), ratio.isFinite, profitLossAmount.optionalAmount != nil {
            profitLoss.text = formatPercent(ratio) + " · " + profitLossAmount.formatted(.baseCurrencyEquivalent, showMinus: false)
        }
        var data = PerpsPositionDisplayData(id: position.id, market: market,
              direction: position.side == "long" ? .long : .short, leverage: position.raw.leverage.value,
              equity: PerpsFormatting.usd(position.equity), profitLoss: profitLoss,
              invested: PerpsFormatting.money(position.collateral), entryPrice: PerpsFormatting.money(position.raw.entryPx),
              liquidationPrice: position.raw.liquidationPx.map { PerpsFormatting.money($0) },
              positionSize: PerpsFormatting.money(position.raw.positionValue) + " · " + PerpsFormatting.quantity(position.size, symbol: asset.symbol),
              fundingPayments: value(position.funding),
              activities: historyFills.map { fill in
                  let kind: PerpsPositionDisplayData.Activity.Kind = switch fill.eventKind {
                  case "increased": .increased
                  case "reduced": .reduced
                  case "closed": .closed
                  case "liquidated": .liquidated
                  default: .opened
                  }
                  let direction = lang(fill.positionSide == "short" ? "Short" : "Long")
                  let side = if let leverage = fill.leverage, leverage > 0 {
                      L10n.perpsLeverageDirection(leverage: leverage.formatted(.number.locale(.forNumberFormatters)), direction: direction)
                  } else {
                      direction
                  }
                  let title = switch kind {
                  case .opened: L10n.perpsActivityOpened(asset: side)
                  case .increased: L10n.perpsActivityIncreased(asset: side)
                  case .reduced: L10n.perpsActivityReduced(asset: side)
                  case .closed: L10n.perpsActivityClosed(asset: side)
                  case .liquidated: L10n.perpsActivityLiquidated(asset: side)
                  }
                  let realizesPnl = ["reduced", "closed", "liquidated"].contains(fill.eventKind)
                  let positionNotional = ["closed", "liquidated"].contains(fill.eventKind) ? fill.previousNotional : fill.positionNotional
                  let hasPositionNotional = PerpsFormatting.usd(positionNotional).optionalAmount != nil
                  return .init(id: fill.id, kind: kind, title: title, date: PerpsFormatting.date(fill.time),
                        amount: realizesPnl ? value(fill.netPnl) : .init(PerpsFormatting.money(fill.notional)),
                        detail: realizesPnl ? lang(hasPositionNotional ? "Position Size" : "Trade Size") + ": "
                            + PerpsFormatting.money(hasPositionNotional ? positionNotional : fill.notional)
                            : PerpsFormatting.quantity(fill.sz, symbol: asset.symbol), canSelect: true)
              }, canEdit: market.canTrade, canClose: market.canTrade)
        if openedAt == nil { data.activityTitle = lang("Recent Market Activity") }
        return data
    }

    public static func order(asset: ApiPerpsAsset, account: MAccount, side: PerpsTradeDirection,
                             input: PerpsOrderInput, position: ApiPerpsAccountPosition? = nil,
                             quote: ApiPerpsQuote? = nil,
                             fundingRequirements: ApiPerpsFundingRequirements? = nil) -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: PerpsFormatting.token(asset), direction: side, paymentToken: usdc, input: input)
        data.account = account
        data.currencyDecimals = 6
        data.canSelectPayment = false
        let requirements = fundingRequirements ?? quote?.fundingRequirements
        data.availableCollateral = requirements?.availableCollateral.map { .init(text: $0) }
        data.canUseFractions = position != nil || data.availableCollateral != nil
        data.price = PerpsFormatting.money(quote?.markPrice ?? asset.context.markPx)
        data.fundingPayments = fundingRate(asset)
        data.fundingRequirement = fundingRequirement(requirements, isEditing: position != nil)
        data.leverageOptions = (1...max(1, asset.maxLeverage)).map { value in
            let selectedPrice = quote?.leverage == value
                ? quote?.estimatedLiquidationPrice ?? (quote?.kind == "unchanged" ? quote?.liquidationPrice : nil)
                : nil
            let liquidationPrice = selectedPrice ?? quote?.leverageEstimates?.first { $0.leverage == value }?.liquidationPrice
            let payment = position != nil && quote?.leverage == value ? quote?.paymentAmount : nil
            return .init(value: value, liquidationPrice: liquidationPrice.map(estimatedMoney),
                         paymentAmount: payment.map { PerpsFormatting.quantity($0, symbol: "USDC") },
                         isPreset: [1, 2, 5, 10, 20, 50].contains(value))
        }
        if let position {
            data.editingPosition = .init(id: position.id, currentInput: .init(text: quote?.currentInputAmount ?? position.collateral),
                                        currentAmount: PerpsFormatting.money(quote?.previousCollateral ?? position.collateral),
                                        change: quote.flatMap {
                                            switch $0.kind {
                                            case "increase": .increase
                                            case "reduce": .reduce
                                            case "leverage": .leverage
                                            default: nil
                                            }
                                        },
                                        liquidationPrice: (quote?.liquidationPrice ?? position.raw.liquidationPx).map { PerpsFormatting.money($0) },
                                        currentLeverage: quote?.previousLeverage ?? position.raw.leverage.value)
            if input.amount.text == position.collateral {
                data.positionSize = PerpsFormatting.money(position.raw.positionValue)
                data.conversion = PerpsFormatting.quantity(position.size, symbol: asset.symbol)
            }
        }
        if let quote {
            data.input.amount = .init(text: quote.inputAmount)
            data.input.leverageOnly = quote.kind == "leverage"
            data.status = quote.kind == "unchanged" ? .idle : .ready
            data.positionSize = PerpsFormatting.money(quote.notional)
            data.paymentAmount = quote.receiveStatus == "pending" ? quote.receiveAmount : quote.paymentAmount
            data.conversion = PerpsFormatting.quantity(quote.size, symbol: asset.symbol)
            data.swapFee = PerpsFormatting.money(quote.estimatedFees?.bridge ?? quote.bridgeFee)
            data.tradingFee = quote.estimatedFees.map { estimatedMoney($0.trading) }
            if quote.kind != "unchanged" {
                data.editingPosition?.liquidationPrice = quote.estimatedLiquidationPrice.map(estimatedMoney)
            }
        }
        return data
    }

    public static func fundingRequirement(_ requirements: ApiPerpsFundingRequirements?, isEditing: Bool = false) -> PerpsOrderDisplayData.FundingRequirement? {
        guard let requirements, requirements.needsUsdc || requirements.needsEth else { return nil }
        let amount: (String) -> String = { value in
            Decimal(string: value)?.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6))) ?? value
        }
        let usdc = amount(requirements.requiredUsdc)
        let eth = amount(requirements.requiredEth)
        if requirements.needsUsdc && requirements.needsEth {
            return .init(title: lang("PerpsFundingMissingTitle"),
                         message: L10n.perpsFundingMissing(minUSDC: usdc, feeETH: eth),
                         buttonTitle: lang("Not Enough Funds"), actionTitle: L10n.buyToken(token: "USDC"), action: .buyUsdc)
        } else if requirements.needsUsdc {
            return .init(title: L10n.notEnoughSymbolLowercase(symbol: "USDC"),
                         message: isEditing ? L10n.perpsFundingUsdcIncrease(minUSDC: usdc) : L10n.perpsFundingUsdc(minUSDC: usdc),
                         buttonTitle: L10n.notEnoughSymbol(symbol: "USDC"), actionTitle: L10n.buyToken(token: "USDC"), action: .buyUsdc)
        } else {
            return .init(title: lang("PerpsFundingGasTitle"),
                         message: L10n.perpsFundingGas(feeETH: eth, feeFiat: PerpsFormatting.money(requirements.requiredEthUsd)),
                         buttonTitle: L10n.notEnoughSymbol(symbol: "ETH"), actionTitle: L10n.buyToken(token: "ETH"), action: .buyEth)
        }
    }

    public static func review(_ quote: ApiPerpsQuote, asset: ApiPerpsAsset) -> PerpsOrderReviewDisplayData {
        var data = PerpsOrderReviewDisplayData(token: PerpsFormatting.token(asset), direction: quote.side == "long" ? .long : .short,
            leverage: quote.leverage, margin: PerpsFormatting.usd(quote.estimatedCollateral ?? quote.collateral),
            positionSize: PerpsFormatting.money(quote.notional), price: PerpsFormatting.money(quote.markPrice),
            liquidationPrice: quote.estimatedLiquidationPrice.map(estimatedMoney),
            paymentAmount: PerpsFormatting.quantity(quote.paymentAmount, symbol: "USDC"),
            fee: quote.estimatedFees.map { estimatedFee($0.total) } ?? lang("PerpsFeesAtExecution"))
        data.isEstimated = quote.kind != "close"
        data.feeRows = quote.estimatedFees.map { feeRows($0, estimated: true, format: estimatedFee) } ?? []
        data.remainingCollateral = positiveRemainder(quote.estimatedRemainingCollateral, estimated: true)
        let previous = PerpsPositionChange(margin: PerpsFormatting.usd(quote.previousCollateral),
                                          positionSize: PerpsFormatting.money(quote.previousNotional),
                                          liquidationPrice: quote.liquidationPrice.map { PerpsFormatting.money($0) })
        data.positionID = quote.kind == "open" ? nil : quote.accountId + "/" + quote.assetId
        switch quote.kind {
        case "increase": data.mode = .increase(previous)
        case "reduce": data.mode = .reduce(previous)
        case "leverage": data.mode = .leverage(previous)
        case "close":
            data.mode = .close(.init(invested: PerpsFormatting.money(quote.previousCollateral),
                                     currentValue: PerpsFormatting.money(quote.equity), entryPrice: PerpsFormatting.money(quote.entryPrice)))
            data.margin = PerpsFormatting.usd(quote.profitLoss)
            data.positionSize = PerpsFormatting.money(quote.previousNotional)
        default: break
        }
        data.feeExplanation = quote.estimatedFees == nil ? lang("PerpsFeesAtExecution") : nil
        data.paymentToken = usdc
        if quote.kind == "reduce" || quote.kind == "close" {
            data.paymentQuantity = quote.receiveAmount
            data.paymentAmount = quote.receiveAmount.map { PerpsFormatting.quantity($0, symbol: "USDC") } ?? "—"
        } else {
            data.paymentQuantity = quote.paymentAmount
        }
        return data
    }

    public static func receipt(fill: ApiPerpsFill, asset: ApiPerpsAsset,
                               operation: ApiPerpsOperation? = nil) -> PerpsPositionReceiptDisplayData {
        if let operation, let data = receipt(operation: operation, asset: asset, fill: fill) { return data }
        let pnl = value(fill.netPnl)
        let receivedAmount = fill.eventKind == "closed" && fill.withdrawal?.status == "completed" ? fill.withdrawal?.receivedAmount : nil
        let outcome = PerpsPositionOutcome(invested: PerpsFormatting.money(fill.collateralBefore),
                                          closingValue: PerpsFormatting.money(receivedAmount), entryPrice: PerpsFormatting.money(fill.entryPrice),
                                          exitPrice: PerpsFormatting.money(fill.px), profitLoss: pnl, heldDuration: heldDuration(fill),
                                          closingValueAmount: PerpsFormatting.usd(receivedAmount))
        let previous = PerpsPositionChange(margin: PerpsFormatting.usd(fill.collateralBefore), positionSize: PerpsFormatting.money(fill.previousNotional), liquidationPrice: nil)
        let event: PerpsPositionReceiptDisplayData.Event = switch fill.eventKind {
        case "liquidated": .liquidated(outcome)
        case "closed": .closed(outcome)
        case "reduced": .reduced(previous, profitLoss: pnl, entryPrice: PerpsFormatting.money(fill.entryPrice))
        case "increased": .increased(previous)
        default: .opened
        }
        let closed = fill.eventKind == "closed" || fill.eventKind == "liquidated"
        let positionSize = ["closed", "liquidated"].contains(fill.eventKind) ? fill.previousNotional : fill.positionNotional
        var data = PerpsPositionReceiptDisplayData(token: PerpsFormatting.token(asset), direction: fill.positionSide == "short" ? .short : .long,
                     leverage: fill.leverage ?? 0, margin: PerpsFormatting.usd(closed ? fill.netPnl : fill.collateralAfter), timestamp: fill.time,
                     positionSize: PerpsFormatting.money(positionSize), price: PerpsFormatting.money(fill.px), liquidationPrice: nil,
                     paymentAmount: fill.deposit.map { PerpsFormatting.quantity($0.grossAmount, symbol: "USDC") }
                        ?? fill.withdrawal.map { $0.status == "completed" ? PerpsFormatting.quantity($0.receivedAmount, symbol: "USDC") : "—" } ?? "—",
                     fee: PerpsFormatting.quantity(fill.receiptFees?.total ?? fill.fee, symbol: fill.feeToken),
                     transferID: fill.hash ?? fill.deposit?.txHash ?? fill.withdrawal?.txHash, event: event)
        let tradeSize = PerpsFormatting.usd(fill.notional)
        if tradeSize.optionalAmount != nil, tradeSize.amount >= 0 {
            if ["opened", "increased", "reduced"].contains(fill.eventKind), data.margin.optionalAmount == nil {
                data.summaryTradeSize = tradeSize
            }
            if ["opened", "increased", "reduced", "closed", "liquidated"].contains(fill.eventKind),
               PerpsFormatting.usd(positionSize).optionalAmount == nil {
                data.positionSize = PerpsFormatting.money(fill.notional)
                data.isTradeSize = true
            }
        }
        if let fees = fill.receiptFees { data.feeRows = feeRows(fees, estimated: false) }
        return data
    }

    public static func receipt(operation: ApiPerpsOperation, asset: ApiPerpsAsset,
                               fill: ApiPerpsFill? = nil) -> PerpsPositionReceiptDisplayData? {
        guard let quote = operation.reviewedQuote, quote.accountId == operation.accountId,
              quote.assetId == operation.assetId, quote.kind == operation.kind, asset.id == operation.assetId else { return nil }
        if let fill, operation.orderId == nil || fill.oid != operation.orderId || fill.coin != asset.name { return nil }
        let position = operation.receiptPosition
        let isClose = operation.kind == "close"
        let partialFill = operation.error == "PerpsPartialFill"
        let canUseEstimate = !partialFill && ["running", "completed"].contains(operation.state)
        var settledFees = fill?.receiptFees ?? operation.receiptDetails?.fees
        if settledFees?.bridge == nil, let reconciledFees = operation.receiptDetails?.fees,
           reconciledFees.bridge != nil, reconciledFees.trading == settledFees?.trading {
            settledFees?.bridge = reconciledFees.bridge
            settledFees?.total = reconciledFees.total
        }
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
        var pnl = value(fill?.netPnl)
        if isClose, fill == nil, canUseEstimate, let profitLoss = quote.profitLoss {
            pnl = value(profitLoss)
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
            direction: (fill?.positionSide ?? quote.side) == "short" ? .short : .long, leverage: fill?.leverage ?? quote.leverage,
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
                ? receivedAmount.map { PerpsFormatting.quantity($0, symbol: "USDC") }
                    ?? (canUseEstimate && fill?.withdrawal == nil ? quote.receiveAmount.map(estimatedQuantity) : nil) ?? "—"
                : PerpsFormatting.quantity(fill?.deposit?.grossAmount ?? quote.paymentAmount, symbol: "USDC"),
            fee: settledFees.map { PerpsFormatting.quantity($0.total, symbol: "USDC") }
                ?? fill.map { PerpsFormatting.quantity($0.fee, symbol: $0.feeToken) }
                ?? (canUseEstimate ? quote.estimatedFees.map { estimatedQuantity($0.total) } : nil) ?? lang("PerpsFeesAtExecution"),
            transferID: fill?.hash ?? fill?.deposit?.txHash ?? fill?.withdrawal?.txHash ?? operation.depositTxHash, event: event)
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
        case "completed": data.status = partialFill ? .attention(lang("PerpsPartialFill")) : .completed
        default: data.status = .attention(lang("PerpsExecutionUnknown"))
        }
        return data
    }

    public static func leverageOptions(_ estimates: [ApiPerpsLeverageEstimate]) -> [PerpsOrderDisplayData.LeverageOption] {
        estimates.map { .init(value: $0.leverage, liquidationPrice: $0.liquidationPrice.map(estimatedMoney),
                             isPreset: [1, 2, 5, 10, 20, 50].contains($0.leverage)) }
    }

    public static func leverageOption(_ quote: ApiPerpsQuote) -> PerpsOrderDisplayData.LeverageOption {
        .init(value: quote.leverage,
              liquidationPrice: (quote.estimatedLiquidationPrice ?? (quote.kind == "unchanged" ? quote.liquidationPrice : nil)).map(estimatedMoney),
              paymentAmount: PerpsFormatting.quantity(quote.paymentAmount, symbol: "USDC"),
              isPreset: [1, 2, 5, 10, 20, 50].contains(quote.leverage))
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

    private static func fundingRate(_ asset: ApiPerpsAsset) -> String? {
        asset.context.fundingPercent.flatMap { Decimal(string: $0) }.map {
            $0.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6))) + "%"
        }
    }

    private static func positiveRemainder(_ amount: String?, estimated: Bool) -> String? {
        guard let amount, let value = Decimal(string: amount), value > 0 else { return nil }
        return (estimated ? "≈ " : "") + PerpsFormatting.quantity(amount, symbol: "USDC")
    }

    private static func feeRows(_ fees: ApiPerpsFees, estimated: Bool, format: ((String) -> String)? = nil) -> [PerpsFeeRow] {
        let format = format ?? { (estimated ? "≈ " : "") + PerpsFormatting.quantity($0, symbol: "USDC") }
        var rows: [PerpsFeeRow] = []
        if let exchange = fees.exchange, let service = fees.service {
            rows += [.init(id: "exchange", title: lang("PerpsExchangeFee"), value: format(exchange)),
                     .init(id: "service", title: lang("PerpsServiceFee"), value: format(service))]
        } else {
            rows.append(.init(id: "trading", title: lang("Trading Fee"), value: format(fees.trading)))
        }
        rows.append(.init(id: "bridge", title: lang("PerpsBridgeFee"), value: fees.bridge.map(format) ?? "—"))
        if fees.bridge != nil {
            rows.append(.init(id: "total", title: lang("PerpsTotalFees"), value: format(fees.total)))
        }
        return rows
    }

    private static func heldDuration(_ fill: ApiPerpsFill) -> String? {
        fill.positionOpenedAt.flatMap { openedAt -> String? in
            guard openedAt <= fill.time else { return nil }
            let formatter = DateComponentsFormatter()
            var calendar = LocalizationSupport.shared.calendar
            calendar.locale = LocalizationSupport.shared.locale
            formatter.calendar = calendar
            formatter.allowedUnits = [.day, .hour, .minute]
            formatter.maximumUnitCount = 2
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: Double(fill.time - openedAt) / 1000)
        }
    }

    public static func value(_ value: String?, returnOnEquity: String? = nil) -> PerpsPositionDisplayData.Value {
        let number = value.flatMap { Decimal(string: $0) }
        return .init(PerpsFormatting.profitLoss(value, returnOnEquity: returnOnEquity),
                     tone: number == nil || number == 0 ? .neutral : number! < 0 ? .negative : .positive)
    }
    public static func fillTitle(_ fill: ApiPerpsFill) -> String {
        switch fill.eventKind { case "increased": "Position Increased"; case "reduced": "Position Reduced";
        case "closed": "Position Closed"; case "liquidated": "Position Liquidated"; default: "Position Opened" }
    }
}
