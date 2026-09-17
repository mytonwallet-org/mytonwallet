import SwiftUI
import WalletContext
import WalletCore

struct MarketToken: Hashable, Identifiable, Sendable {
    enum Chart: Hashable, Sendable {
        case bundled(fillImageName: String, lineImageName: String, tint: UInt32)
        case sparkline(points: [Double], tint: UInt32)

        var tint: UInt32 {
            switch self {
            case .bundled(_, _, let tint), .sparkline(_, let tint):
                tint
            }
        }
    }

    let token: ApiToken
    let fallbackPrice: Double?
    let fallbackChange: Double
    let chart: Chart?

    var id: String { token.slug }
    var name: String { token.displayName(strippingLabelWhenShown: true) }
    var price: Double? { token.price ?? fallbackPrice.map { $0 * TokenStore.baseCurrencyRate } }
    var change: Double { token.percentChange24h ?? fallbackChange }
    var changeText: String { formatPercent(change / 100) }
    var isPositive: Bool { change >= 0 }

    var priceText: String? {
        price.map {
            BaseCurrencyAmount.fromDouble($0, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        }
    }
}

struct MarketSection: Hashable, Identifiable, Sendable {
    enum Layout: Hashable, Sendable {
        case largeHorizontal
        case grid
        case rows
    }

    let id: String
    let title: String
    let layout: Layout
    let tokens: [MarketToken]
    let visibleLimit: Int?
    let showsSeeAll: Bool

    var visibleTokens: [MarketToken] {
        guard let visibleLimit, visibleLimit > 0 else { return tokens }
        return Array(tokens.prefix(visibleLimit))
    }
}

extension MarketSection {
    @concurrent static func samples() async -> [MarketSection] {
        samples(tokens: TokenStore.tokens)
    }

    static func samples(tokens storeTokens: [String: ApiToken]) -> [MarketSection] {
        let knownFallbacks: [ApiToken] = [
            .TONCOIN, .ETH, .BNB, .SOLANA, .MYCOIN, .HYPERLIQUID, .TRX, .POLYGON,
            .ROBINHOOD, .AVALANCHE, .ARBITRUM, .MONAD, .BASE,
        ]
        let knownTokens = knownFallbacks.map { storeTokens[$0.slug] ?? $0 }

        func resolved(_ slug: String) -> ApiToken {
            storeTokens[slug] ?? knownTokens.first(where: { $0.slug == slug }) ?? .TONCOIN
        }

        func uniqueTokens(_ candidates: [ApiToken], count: Int, fallback: [ApiToken]) -> [ApiToken] {
            var seen = Set<String>()
            return (candidates + fallback)
                .filter { seen.insert($0.slug).inserted }
                .prefix(count)
                .map { $0 }
        }

        func marketTokens(
            _ tokens: [ApiToken],
            changes: [Double],
            fallbackPrices: [Double?] = [],
            charts: [MarketToken.Chart?] = []
        ) -> [MarketToken] {
            tokens.enumerated().map { index, token in
                MarketToken(
                    token: token,
                    fallbackPrice: fallbackPrices[safe: index] ?? nil,
                    fallbackChange: changes[safe: index] ?? 0,
                    chart: charts[safe: index] ?? nil
                )
            }
        }

        let movers = marketTokens(
            [resolved(MYCOIN_SLUG), resolved(HYPERLIQUID_SLUG), resolved(SOLANA_SLUG)],
            changes: [6.63, -0.74, -3.52],
            fallbackPrices: [5.21, 65.85, 163.44],
            charts: [
                .bundled(
                    fillImageName: "MarketMyWalletChartFill",
                    lineImageName: "MarketMyWalletChartLine",
                    tint: 0x016FFA
                ),
                .bundled(
                    fillImageName: "MarketJupiterChartFill",
                    lineImageName: "MarketJupiterChartLine",
                    tint: 0x1BB0CA
                ),
                .bundled(
                    fillImageName: "MarketHyperliquidChartFill",
                    lineImageName: "MarketHyperliquidChartLine",
                    tint: 0x208D80
                ),
            ]
        )

        let popular = marketTokens(
            [TONCOIN_SLUG, ETH_SLUG, BNB_SLUG, SOLANA_SLUG, MYCOIN_SLUG, HYPERLIQUID_SLUG, TRX_SLUG, POLYGON_SLUG]
                .map(resolved),
            changes: [1.29, 0.12, -0.36, 0.48, 6.63, 5.28, 2.44, -0.12]
        )

        let rwaTokens = storeTokens.values
            .filter(\.isRwaStock)
            .sorted { $0.displayName(strippingLabelWhenShown: true) < $1.displayName(strippingLabelWhenShown: true) }
        let stocks = marketTokens(
            uniqueTokens(rwaTokens, count: 8, fallback: knownTokens),
            changes: [0.38, -1.15, 0.91, 1.45, 3.28, 0.05, -0.12, 0.54]
        )

        let goldCandidate = storeTokens.values
            .filter {
                $0.symbol.localizedCaseInsensitiveContains("XAUT")
                    || $0.name.localizedCaseInsensitiveContains("gold")
            }
            .sorted {
                let leftIsExactXAUT = $0.symbol.caseInsensitiveCompare("XAUT") == .orderedSame
                let rightIsExactXAUT = $1.symbol.caseInsensitiveCompare("XAUT") == .orderedSame
                if leftIsExactXAUT != rightIsExactXAUT {
                    return leftIsExactXAUT
                }
                return $0.displayName(strippingLabelWhenShown: true)
                    < $1.displayName(strippingLabelWhenShown: true)
            }
            .first ?? resolved(TON_USDT_SLUG)
        let gold = marketTokens([goldCandidate], changes: [1.39], fallbackPrices: [4_005.68])

        let indexCandidates = rwaTokens.filter {
            let name = $0.name.lowercased()
            return name.contains("index")
                || name.contains("market")
                || name.contains("s&p")
                || name.contains("nasdaq")
        }
        let indices = marketTokens(
            uniqueTokens(indexCandidates, count: 4, fallback: Array(knownTokens.reversed())),
            changes: [0.07, -1.61, 0.83, 1.72]
        )

        return [
            MarketSection(
                id: "movers",
                title: lang("Today's Movers"),
                layout: .largeHorizontal,
                tokens: movers,
                visibleLimit: nil,
                showsSeeAll: false
            ),
            MarketSection(
                id: "popular-tokens",
                title: lang("Popular Tokens"),
                layout: .grid,
                tokens: popular,
                visibleLimit: nil,
                showsSeeAll: true
            ),
            MarketSection(
                id: "tokenized-stocks",
                title: lang("Tokenized Stocks"),
                layout: .grid,
                tokens: stocks,
                visibleLimit: nil,
                showsSeeAll: true
            ),
            MarketSection(
                id: "tokenized-gold",
                title: lang("Tokenized Gold"),
                layout: .rows,
                tokens: gold,
                visibleLimit: nil,
                showsSeeAll: false
            ),
            MarketSection(
                id: "index-funds",
                title: lang("Index Funds"),
                layout: .grid,
                tokens: indices,
                visibleLimit: nil,
                showsSeeAll: true
            ),
        ]
    }
}

enum MarketSectionBuilder {
    @concurrent static func build(from response: ApiMarketAssetsResponse) async -> [MarketSection] {
        build(from: response, storeTokens: TokenStore.tokens)
    }

    static func build(
        from response: ApiMarketAssetsResponse,
        storeTokens: [String: ApiToken]
    ) -> [MarketSection] {
        response.sections.compactMap { section in
            let tokens = section.assets.map { asset in
                marketToken(from: asset, storeTokens: storeTokens)
            }
            guard !tokens.isEmpty else { return nil }

            let layout: MarketSection.Layout = switch section.layout {
            case .largeHorizontal: .largeHorizontal
            case .grid: .grid
            case .rows: .rows
            }
            let visibleLimit = (section.mobileLimit ?? section.limit).flatMap { $0 > 0 ? $0 : nil }

            return MarketSection(
                id: section.id,
                title: section.title,
                layout: layout,
                tokens: tokens,
                visibleLimit: visibleLimit,
                showsSeeAll: section.hasMore
                    || visibleLimit.map { tokens.count > $0 } == true
            )
        }
    }

    private static func marketToken(
        from asset: ApiMarketAsset,
        storeTokens: [String: ApiToken]
    ) -> MarketToken {
        let token: ApiToken
        if var storedToken = storeTokens[asset.slug] {
            storedToken.localizedName = asset.name
            storedToken.image = storedToken.image?.nilIfEmpty ?? asset.image.nilIfEmpty
            storedToken.label = storedToken.label?.nilIfEmpty ?? asset.label?.nilIfEmpty
            token = storedToken
        } else {
            token = ApiToken(
                slug: asset.slug,
                name: asset.name,
                localizedName: asset.name,
                symbol: asset.symbol,
                decimals: 9,
                chain: asset.chain,
                tokenAddress: asset.tokenAddress,
                image: asset.image,
                label: asset.label,
                priceUsd: asset.price,
                percentChange24h: asset.percentChange24h
            )
        }

        return MarketToken(
            token: token,
            fallbackPrice: asset.price,
            fallbackChange: asset.percentChange24h,
            chart: .sparkline(values: asset.sparkline, tintColor: asset.tintColor)
        )
    }
}

extension MarketToken.Chart {
    static func sparkline(values: [Double]?, tintColor: String?) -> Self? {
        guard let tint = tintColor.flatMap(parseRGBColor),
              let values else { return nil }
        let finiteValues = values.filter(\.isFinite)
        guard finiteValues.count >= 2,
              let minimum = finiteValues.min(),
              let maximum = finiteValues.max() else { return nil }

        let range = maximum - minimum
        let points = finiteValues.map { value in
            range > 0 ? 1 - (value - minimum) / range : 0.5
        }
        return .sparkline(points: points, tint: tint)
    }
}

private func parseRGBColor(_ value: String) -> UInt32? {
    var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
        hex.removeFirst()
    }
    guard hex.count == 6 else { return nil }
    return UInt32(hex, radix: 16)
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}
