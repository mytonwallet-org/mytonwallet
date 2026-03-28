import Foundation

/// Builds MyTonWallet deep links from classified intents.
public struct DeeplinkBuilder: Sendable {
    public static let baseURL = "https://my.tt"

    private let tokenResolver: TokenResolver
    private let currencyRates: CurrencyRates
    private let i18n: I18n

    public init(tokenResolver: TokenResolver, currencyRates: CurrencyRates = CurrencyRates(), i18n: I18n = I18n()) {
        self.tokenResolver = tokenResolver
        self.currencyRates = currencyRates
        self.i18n = i18n
    }

    /// Build an IntentResult with deep links for the given intent.
    /// Returns nil for unsupported intent types (question, searchNews).
    public func build(intent: Intent, lang: String = "en", baseCurrency: String = "USD") async -> IntentResult? {
        switch intent.type {
        case .sendToken:
            return await buildSendToken(intent: intent, lang: lang)
        case .receive:
            return await buildReceive(intent: intent, lang: lang)
        case .swap:
            return await buildSwap(intent: intent, lang: lang)
        case .buyWithCard:
            return await buildBuyWithCard(intent: intent, lang: lang)
        case .buyWithCrypto:
            return await buildBuyWithCrypto(intent: intent, lang: lang)
        case .price:
            return await buildPrice(intent: intent, lang: lang, baseCurrency: baseCurrency)
        case .stake:
            return buildStake(lang: lang)
        case .portfolio:
            return buildPortfolio(lang: lang)
        case .question, .searchNews:
            return nil
        }
    }

    // MARK: - Send Token

    private func buildSendToken(intent: Intent, lang: String) async -> IntentResult {
        let toAddr = intent.to ?? ""
        let tokenQuery = intent.token ?? "TON"
        guard let asset = await tokenResolver.resolve(tokenQuery) else {
            return tokenNotFound(tokenQuery, lang: lang)
        }

        let token = asset.symbol
        var params: [(String, String)] = []
        var link = "\(Self.baseURL)/transfer/\(toAddr)"

        if asset.slug != "toncoin" {
            params.append(("jetton", asset.slug))
        }
        if let amount = intent.amount {
            params.append(("amount", toSmallestUnits(amount, decimals: asset.decimals)))
        }
        if !params.isEmpty {
            link += "?" + queryString(params)
        }

        var summaryLines: [String] = []
        if !toAddr.isEmpty {
            summaryLines.append(i18n.t("send.summary.to", lang: lang, args: ["address": toAddr]))
        }
        if let amount = intent.amount {
            summaryLines.append(i18n.t("send.summary.amount", lang: lang, args: [
                "amount": fmtAmount(amount, token: token),
                "name": asset.name,
            ]))
        }
        summaryLines.append(i18n.t("send.summary.fee", lang: lang))

        return IntentResult(
            type: "sendToken",
            message: i18n.t("send.message", lang: lang, args: ["summary": summaryLines.joined(separator: "\n")]),
            deeplinks: [Deeplink(title: i18n.t("send.button", lang: lang, args: ["token": token]), url: link)]
        )
    }

    // MARK: - Receive

    private func buildReceive(intent: Intent, lang: String) async -> IntentResult {
        let address = intent.address
        let tokenQuery = intent.token
        let comment = intent.comment

        if let address {
            let asset = tokenQuery != nil ? await tokenResolver.resolve(tokenQuery) : nil
            var params: [(String, String)] = []

            if let amount = intent.amount, let asset {
                params.append(("amount", toSmallestUnits(amount, decimals: asset.decimals)))
            } else if let amount = intent.amount {
                params.append(("amount", toSmallestUnits(amount, decimals: 9)))
            }
            if let asset, let tokenAddress = asset.tokenAddress {
                params.append(("jetton", tokenAddress))
            }
            if let comment {
                params.append(("text", comment))
            }

            var link = "ton://transfer/\(address)"
            if !params.isEmpty {
                link += "?" + queryString(params)
            }

            let tokenName = asset?.symbol ?? "TON"
            var summaryLines = [i18n.t("receive.summary.to", lang: lang, args: ["address": address])]
            if let amount = intent.amount {
                summaryLines.append(i18n.t("receive.summary.amount", lang: lang, args: ["amount": fmtAmount(amount, token: tokenName)]))
            }
            if let comment {
                summaryLines.append(i18n.t("receive.summary.comment", lang: lang, args: ["comment": comment]))
            }

            return IntentResult(
                type: "receive",
                message: i18n.t("receive.message.withAddress", lang: lang, args: ["summary": summaryLines.joined(separator: "\n")]),
                deeplinks: [Deeplink(title: i18n.t("receive.button", lang: lang, args: ["token": tokenName]), url: link)]
            )
        }

        return IntentResult(
            type: "receive",
            message: i18n.t("receive.message.noAddress", lang: lang),
            deeplinks: [Deeplink(title: i18n.t("receive.button.default", lang: lang), url: "\(Self.baseURL)/receive")]
        )
    }

    // MARK: - Swap

    private func buildSwap(intent: Intent, lang: String) async -> IntentResult {
        let inQuery = intent.in ?? ""
        let outQuery = intent.out ?? ""

        let assetIn = !inQuery.isEmpty ? await tokenResolver.resolve(inQuery) : nil
        let assetOut = !outQuery.isEmpty ? await tokenResolver.resolve(outQuery) : nil

        if !inQuery.isEmpty && assetIn == nil {
            return tokenNotFound(inQuery, lang: lang)
        }
        if !outQuery.isEmpty && assetOut == nil {
            return tokenNotFound(outQuery, lang: lang)
        }

        let tokenIn = assetIn?.symbol ?? ""
        let tokenOut = assetOut?.symbol ?? ""

        var params: [(String, String)] = []
        if let assetIn { params.append(("in", assetIn.slug)) }
        if let assetOut { params.append(("out", assetOut.slug)) }
        if let amountIn = intent.amountIn, assetIn != nil {
            params.append(("amountIn", "\(amountIn)"))
        }

        var url = "\(Self.baseURL)/swap"
        if !params.isEmpty {
            url += "?" + queryString(params)
        }

        var summaryLines: [String] = []
        if !tokenIn.isEmpty {
            summaryLines.append(i18n.t("swap.summary.from", lang: lang, args: ["amount": fmtAmount(intent.amountIn, token: tokenIn)]))
        }
        if !tokenOut.isEmpty {
            summaryLines.append(i18n.t("swap.summary.to", lang: lang, args: ["token": tokenOut]))
        }
        summaryLines.append(i18n.t("swap.summary.fee", lang: lang))

        return IntentResult(
            type: "swap",
            message: i18n.t("swap.message", lang: lang, args: ["summary": summaryLines.joined(separator: "\n")]),
            deeplinks: [Deeplink(title: i18n.t("swap.button", lang: lang), url: url)]
        )
    }

    // MARK: - Buy with Card

    private func buildBuyWithCard(intent: Intent, lang: String) async -> IntentResult {
        let tokenQuery = intent.token ?? ""
        var token = ""

        if !tokenQuery.isEmpty {
            guard let asset = await tokenResolver.resolve(tokenQuery) else {
                return tokenNotFound(tokenQuery, lang: lang)
            }
            token = asset.symbol
        }

        var summaryLines: [String] = []
        if let amount = intent.amount, !token.isEmpty {
            summaryLines.append(i18n.t("buyWithCard.summary.amount", lang: lang, args: ["amount": fmtAmount(amount, token: token)]))
        }
        summaryLines.append(i18n.t("buyWithCard.summary.payment", lang: lang))

        return IntentResult(
            type: "buyWithCard",
            message: i18n.t("buyWithCard.message", lang: lang, args: ["summary": summaryLines.joined(separator: "\n")]),
            deeplinks: [Deeplink(title: i18n.t("buyWithCard.button", lang: lang), url: "\(Self.baseURL)/buy-with-card")]
        )
    }

    // MARK: - Buy with Crypto

    private func buildBuyWithCrypto(intent: Intent, lang: String) async -> IntentResult {
        let inQuery = intent.in ?? intent.token ?? ""
        let outQuery = intent.out ?? ""

        let assetIn = !inQuery.isEmpty ? await tokenResolver.resolve(inQuery) : nil
        let assetOut = !outQuery.isEmpty ? await tokenResolver.resolve(outQuery) : nil

        if !inQuery.isEmpty && assetIn == nil {
            return tokenNotFound(inQuery, lang: lang)
        }
        if !outQuery.isEmpty && assetOut == nil {
            return tokenNotFound(outQuery, lang: lang)
        }

        var params: [(String, String)] = []
        if let assetIn { params.append(("in", assetIn.slug)) }
        if let assetOut { params.append(("out", assetOut.slug)) }
        if let amount = intent.amount, let assetIn {
            params.append(("amount", toSmallestUnits(amount, decimals: assetIn.decimals)))
        }

        var url = "\(Self.baseURL)/buy-with-crypto"
        if !params.isEmpty {
            url += "?" + queryString(params)
        }

        let tokenIn = assetIn?.symbol ?? ""
        let tokenOut = assetOut?.symbol ?? ""
        var summaryLines: [String] = []
        if !tokenIn.isEmpty {
            summaryLines.append(i18n.t("buyWithCrypto.summary.from", lang: lang, args: ["amount": fmtAmount(intent.amount, token: tokenIn)]))
        }
        if !tokenOut.isEmpty {
            summaryLines.append(i18n.t("buyWithCrypto.summary.to", lang: lang, args: ["token": tokenOut]))
        }
        summaryLines.append(i18n.t("buyWithCrypto.summary.fee", lang: lang))

        return IntentResult(
            type: "buyWithCrypto",
            message: i18n.t("buyWithCrypto.message", lang: lang, args: ["summary": summaryLines.joined(separator: "\n")]),
            deeplinks: [Deeplink(title: i18n.t("buyWithCrypto.button", lang: lang), url: url)]
        )
    }

    // MARK: - Price

    private func buildPrice(intent: Intent, lang: String, baseCurrency: String) async -> IntentResult {
        guard let tokenQuery = intent.token else {
            return IntentResult(type: "price")
        }
        guard let asset = await tokenResolver.resolve(tokenQuery) else {
            return tokenNotFound(tokenQuery, lang: lang)
        }

        let token = asset.symbol
        var summaryLines: [String] = []

        if let priceUsd = asset.priceUsd {
            // If the token is the same as the base currency (e.g. TON priced in TON), fall back to USD
            let effectiveCurrency = asset.symbol.uppercased() == baseCurrency.uppercased() ? "USD" : baseCurrency.uppercased()

            let displayPrice: Double
            let currencyLabel: String

            if effectiveCurrency == "USD" {
                displayPrice = priceUsd
                currencyLabel = "$"
            } else if let converted = await currencyRates.convert(usdAmount: priceUsd, to: effectiveCurrency) {
                displayPrice = converted
                currencyLabel = await currencyRates.currencySymbol(for: effectiveCurrency)
            } else {
                // Unknown currency, fall back to USD
                displayPrice = priceUsd
                currencyLabel = "$"
            }

            let priceStr = formatPrice(displayPrice)
            summaryLines.append(i18n.t("price.summary.price", lang: lang, args: [
                "price": priceStr,
                "currency": currencyLabel,
            ]))
        }
        if let change = asset.percentChange24h {
            let direction = change >= 0 ? "\u{1F4C8}" : "\u{1F4C9}"
            summaryLines.append(i18n.t("price.summary.change", lang: lang, args: [
                "direction": direction,
                "change": String(format: "%+.2f", change),
            ]))
        }

        let msg: String
        if !summaryLines.isEmpty {
            msg = i18n.t("price.message.withData", lang: lang, args: [
                "token": token,
                "name": asset.name,
                "summary": summaryLines.joined(separator: "\n"),
            ])
        } else {
            msg = i18n.t("price.message.noData", lang: lang, args: ["token": token])
        }

        return IntentResult(
            type: "price",
            message: msg,
            deeplinks: [Deeplink(title: i18n.t("price.button", lang: lang, args: ["token": token]), url: "\(Self.baseURL)/token/\(asset.slug)")]
        )
    }

    // MARK: - Stake

    private func buildStake(lang: String) -> IntentResult {
        IntentResult(
            type: "stake",
            message: i18n.t("stake.message", lang: lang),
            deeplinks: [Deeplink(title: i18n.t("stake.button", lang: lang), url: "\(Self.baseURL)/stake")]
        )
    }

    // MARK: - Portfolio

    private func buildPortfolio(lang: String) -> IntentResult {
        IntentResult(
            type: "portfolio",
            message: i18n.t("portfolio.message", lang: lang),
            deeplinks: [Deeplink(title: i18n.t("portfolio.button", lang: lang), url: "https://portfolio.mytonwallet.io")]
        )
    }

    // MARK: - Helpers

    private func tokenNotFound(_ query: String, lang: String) -> IntentResult {
        IntentResult(
            type: "error",
            message: i18n.t("error.tokenNotFound", lang: lang, args: ["token": query]),
            error: "tokenNotFound"
        )
    }

    private func fmtAmount(_ amount: Double?, token: String) -> String {
        if let amount {
            return "\(formatNumber(amount)) \(token)"
        }
        return token
    }

    /// Convert human-readable amount to smallest units using exact decimal math.
    private func toSmallestUnits(_ amount: Double, decimals: Int) -> String {
        let d = Decimal(amount)
        var multiplier = Decimal(1)
        for _ in 0..<decimals {
            multiplier *= 10
        }
        let result = d * multiplier
        return NSDecimalNumber(decimal: result).intValue != 0
            ? "\(NSDecimalNumber(decimal: result).uint64Value)"
            : NSDecimalNumber(decimal: result).stringValue
    }

    private func queryString(_ params: [(String, String)]) -> String {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.query ?? ""
    }

    private func formatPrice(_ price: Double) -> String {
        let str = String(format: "%.6f", price)
        // Strip trailing zeros, then trailing dot
        var trimmed = str
        while trimmed.hasSuffix("0") { trimmed = String(trimmed.dropLast()) }
        if trimmed.hasSuffix(".") { trimmed = String(trimmed.dropLast()) }
        return trimmed
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() && n < 1e15 {
            return String(format: "%.0f", n)
        }
        return "\(n)"
    }
}
