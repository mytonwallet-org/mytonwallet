import Foundation
import WalletContext

public enum PerpsFormatting {
    public static func cashFlowTitle(_ value: ApiPerpsCashFlow) -> String {
        switch value.kind {
        case .funding: lang("Funding Payment")
        case .deposit: lang("Deposit")
        case .withdrawal: lang("Withdrawal")
        case .transfer: lang("Transfer")
        }
    }

    public static func cashFlowAmount(_ value: ApiPerpsCashFlow) -> String {
        let prefix = Decimal(string: value.amount) == 0 || value.direction == .internal ? ""
            : value.direction == .outgoing ? "−" : "+"
        return prefix + quantity(value.amount, symbol: value.token)
    }

    public static func perpsBook(_ dex: String) -> String {
        dex == "spot" ? lang("Spot Balance") : dex.isEmpty ? lang("Futures") : dex
    }

    public static func operationMessage(_ operation: ApiPerpsOperation) -> String {
        switch operation.state {
        case "running": lang("PerpsProcessing")
        case "partial": lang("PerpsWithdrawalPending")
        case "unknown": lang("PerpsExecutionUnknown")
        case "failed": errorMessage(operation.error)
        default: lang(operation.error == "PerpsPartialFill" ? "PerpsPartialFill" : "PerpsReconciled")
        }
    }

    public static func operationTitle(_ operation: ApiPerpsOperation, symbol: String) -> String {
        let key: String
        switch operation.kind {
        case "open": key = "Open Position"
        case "increase": key = "Increase Position"
        case "reduce": key = "Reduce Position"
        case "close": key = "Close Position"
        default: key = "Edit Position"
        }
        return lang(key) + (symbol.isEmpty ? "" : " · " + symbol)
    }

    public static func usd(_ value: String?) -> BaseCurrencyAmount {
        var result = BaseCurrencyAmount(0, .USD)
        guard let value else { result.optionalAmount = nil; return result }
        let negative = value.hasPrefix("-")
        let unsigned = negative ? String(value.dropFirst()) : value
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }), unsigned.contains(where: \.isNumber) else {
            result.optionalAmount = nil; return result
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let digits = String(parts[0]) + String((fraction + String(repeating: "0", count: result.decimals)).prefix(result.decimals))
        result.optionalAmount = BigInt((negative ? "-" : "") + digits)
        return result
    }

    public static func money(_ value: String?) -> String {
        guard let value else { return "—" }
        let amount = usd(value)
        return amount.optionalAmount == nil ? "—" : amount.formatted(.defaultAdaptive)
    }

    public static func token(_ asset: ApiPerpsAsset) -> ApiToken {
        var token = ApiToken(slug: "perps/" + asset.id, name: asset.displayName ?? asset.symbol, symbol: asset.symbol, decimals: asset.szDecimals,
                 chain: .hyperliquid, image: asset.image, priceUsd: Double(asset.context.markPx),
                 percentChange24h: asset.context.percentChange24h)
        token.label = asset.label
        token.keywords = asset.keywords
        return token
    }

    public static func quantity(_ value: String?, symbol: String) -> String {
        guard let value, let decimal = Decimal(string: value) else { return "—" }
        return decimal.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...12))) + " " + symbol
    }

    public static func profitLoss(_ amount: String?, returnOnEquity: String? = nil) -> String {
        guard let amount, let decimal = Decimal(string: amount) else { return "—" }
        var text = (decimal > 0 ? "+" : "") + money(amount)
        if let returnOnEquity, let ratio = Double(returnOnEquity) {
            text += " (" + formatPercent(ratio, showPlus: false, showMinus: false) + ")"
        }
        return text
    }

    public static func date(_ timestamp: Int64) -> String {
        let calendar = LocalizationSupport.shared.calendar
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: LocalizationSupport.shared.locale,
                                      calendar: calendar, timeZone: calendar.timeZone)
        return Date(timeIntervalSince1970: Double(timestamp) / 1000).formatted(format)
    }

    public static func error(_ error: Error) -> String {
        if let error = error as? PerpsError { return error.localizedDescription }
        return errorMessage(String(describing: error))
    }

    public static func errorMessage(_ code: String?) -> String {
        let description = code ?? ""
        let keys = ["PerpsReviewChanged", "PerpsWithdrawalPending", "PerpsQuoteExpired", "PerpsInsufficientUsdc", "PerpsInsufficientGas", "PerpsAmountTooSmall", "PerpsUnchanged",
                    "PerpsOrderTooSmall", "PerpsOrderNotFilled", "PerpsInsufficientMargin", "PerpsOrderRejected",
                    "PerpsPositionChanged", "PerpsPositionExists", "PerpsOperationPending", "PerpsUnsupportedAccount",
                    "PerpsInvalidLeverage", "PerpsInvalidAmount", "PerpsChangeLeverageSeparately", "PerpsTradingUnavailable"]
        if let key = keys.first(where: { description.contains($0) }) { return lang(key) }
        if let error = ApiAnyDisplayError.from(description) { return error.toLocalized }
        return lang("PerpsUnavailable")
    }
}
