import Foundation
import WalletContext

/// Display text with the color role of its sign.
public struct PerpsValue: Sendable {
    public enum Tone: Sendable { case neutral, positive, negative }
    public var text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

public enum PerpsFormatting {
    private static let NETWORK_ERROR_MESSAGES: Set<String> = [
        "Load failed", "Failed to fetch", "NetworkError when attempting to fetch resource.", "Request timed out.",
    ]

    /// The account's USDC on Arbitrum, which funds orders and receives withdrawals.
    public static var usdc: ApiToken {
        TokenStore.tokens["arbitrum-0xaf88d065"] ?? ApiToken(
            slug: "arbitrum-0xaf88d065", name: "USD Coin", symbol: "USDC", decimals: 6,
            chain: .arbitrum, tokenAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
            image: ApiToken.SOLANA_USDC_MAINNET.image, priceUsd: 1)
    }

    /// The USDC on the Hyperliquid balance.
    public static var hyperliquidUsdc: ApiToken {
        ApiToken(slug: "perps/hyperliquid-usdc", name: usdc.name, symbol: usdc.symbol, decimals: usdc.decimals,
                 chain: .hyperliquid, image: usdc.image, priceUsd: 1)
    }

    public static func operationMessage(_ operation: ApiPerpsOperation) -> String {
        if operation.isWithdrawalRejected { return errorMessage(operation.error) }
        if operation.isBalanceWithdrawal {
            return switch operation.state {
            case "running": lang("PerpsWithdrawalProcessing")
            case "unknown": lang("PerpsWithdrawalUnknown")
            case "failed": errorMessage(operation.error)
            default: lang("PerpsWithdrawalOnItsWay")
            }
        }
        return switch operation.state {
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
        case ApiPerpsOperation.balanceWithdrawalKind: key = "Withdrawal"
        default: key = "Edit Position"
        }
        return lang(key) + (symbol.isEmpty ? "" : " · " + symbol)
    }

    /// Decimal strings convert without rounding through `Double`; anything else is unknown.
    public static func usd(_ value: String?) -> BaseCurrencyAmount {
        var result = BaseCurrencyAmount(0, .USD)
        let negative = value?.hasPrefix("-") == true
        guard let unsigned = value.map({ negative ? String($0.dropFirst()) : $0 }),
              unsigned.contains(where: \.isNumber), unsigned.allSatisfy({ $0.isNumber || $0 == "." }),
              unsigned.filter({ $0 == "." }).count <= 1 else {
            result.optionalAmount = nil
            return result
        }
        let amount = normalizedAmountValue(unsigned, digits: result.decimals)
        result.optionalAmount = negative ? -amount : amount
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

    /// Signed fiat followed by the unsigned return: in parentheses for rows, after a middle dot in a summary.
    public static func profitLoss(_ amount: String?, returnOnEquity: String? = nil, summary: Bool = false) -> PerpsValue {
        guard let amount, let decimal = Decimal(string: amount) else { return .init("—") }
        var text = (decimal > 0 ? "+" : "") + money(amount)
        if let returnOnEquity, let ratio = Double(returnOnEquity) {
            let percentage = formatPercent(ratio, showPlus: false, showMinus: false)
            text += summary ? " · " + percentage : " (" + percentage + ")"
        }
        return .init(text, tone: decimal == 0 ? .neutral : decimal < 0 ? .negative : .positive)
    }

    public static func error(_ error: Error) -> String {
        if let error = error as? PerpsError { return error.localizedDescription }
        if let error = error as? SdkError {
            if case .javaScriptException(let exception) = error,
               exception.name == "NetworkError" || exception.name == "TimeoutError" {
                return lang("Please make sure your internet connection is working and try again.")
            }
            if case .javaScriptException(let exception) = error, let data = exception.data,
               let details = try? JSONDecoder().decode(PerpsInputErrorPayload.self, fromString: data).additionalData,
               let message = formatInputError(exception.message, details: details) {
                return message
            }
            return errorMessage(error.backendMessage)
        }
        return errorMessage(String(describing: error))
    }

    private static func formatInputError(_ code: String, details: PerpsInputErrorPayload.Details) -> String? {
        if code == "PerpsAmountTooSmall" {
            if var minimum = parseInputAmount(details.minimumAmount) {
                var rounded = Decimal()
                NSDecimalRound(&rounded, &minimum, 2, details.isMinimumExclusive == true ? .down : .up)
                if details.isMinimumExclusive == true { rounded += Decimal(string: "0.01")! }
                return L10n.perpsMinimumAmount(amount: formatInputAmount(rounded))
            }
            if let reduction = parseInputAmount(details.minimumReduction) {
                return L10n.perpsMinimumReduction(amount: formatInputAmount(reduction))
            }
        }
        if code == "PerpsInsufficientBalance", let available = parseInputAmount(details.availableBalance) {
            if let required = parseInputAmount(details.requiredBalance) {
                return L10n.perpsRequiredBalance(required_: formatInputAmount(required), available: formatInputAmount(available))
            }
            return L10n.perpsAvailableBalance(available: formatInputAmount(available))
        }
        return nil
    }

    private static func parseInputAmount(_ value: String?) -> Decimal? {
        guard let value, !value.isEmpty, value.contains(where: \.isNumber),
              value.allSatisfy({ ("0"..."9").contains($0) || $0 == "." }), value.filter({ $0 == "." }).count <= 1,
              let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        return amount
    }

    private static func formatInputAmount(_ amount: Decimal) -> String {
        amount.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6)))
    }

    public static func errorMessage(_ code: String?) -> String {
        let description = code ?? ""
        let keys = ["PerpsReviewChanged", "PerpsWithdrawalPending", "PerpsQuoteExpired", "PerpsInsufficientUsdc", "PerpsInsufficientBalance", "PerpsMarketNeedsUnifiedAccount", "PerpsInsufficientGas", "PerpsAmountTooSmall", "PerpsUnchanged",
                    "PerpsOrderTooSmall", "PerpsOrderNotFilled", "PerpsOrderNotPlaced", "PerpsInsufficientMargin", "PerpsOrderRejected",
                    "PerpsPositionChanged", "PerpsPositionExists", "PerpsOperationPending", "PerpsUnsupportedAccount",
                    "PerpsInvalidLeverage", "PerpsInvalidAmount", "PerpsChangeLeverageSeparately", "PerpsTradingUnavailable",
                    "PerpsNothingToWithdraw", "PerpsWithdrawalRejected"]
        if let key = keys.first(where: { description.contains($0) }) { return lang(key) }
        if let error = ApiAnyDisplayError.from(description) { return error.toLocalized }
        let fetchMessage = description.components(separatedBy: " | ").last ?? description
        let isRetriedRequest = description.contains(" | attempts=") && !description.contains(" | status=")
        if NETWORK_ERROR_MESSAGES.contains(description) || (isRetriedRequest && NETWORK_ERROR_MESSAGES.contains(fetchMessage)) {
            return lang("Please make sure your internet connection is working and try again.")
        }
        return lang("PerpsUnavailable")
    }
}

private struct PerpsInputErrorPayload: Decodable {
    struct Details: Decodable {
        let minimumAmount: String?
        let isMinimumExclusive: Bool?
        let minimumReduction: String?
        let requiredBalance: String?
        let availableBalance: String?
    }
    let additionalData: Details
}
