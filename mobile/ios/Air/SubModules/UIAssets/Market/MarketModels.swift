import SwiftUI
import WalletContext
import WalletCore

struct MarketToken: Hashable, Identifiable {
    struct Chart: Hashable {
        let fillImageName: String
        let lineImageName: String
        let tint: UInt32
    }

    let token: ApiToken
    let fallbackPrice: Double?
    let fallbackChange: Double
    let chart: Chart?

    var id: String { token.slug }
    var name: String { token.displayName(strippingLabelWhenShown: true) }
    var price: Double? { token.price ?? fallbackPrice }
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

struct MarketSection: Hashable, Identifiable {
    enum Layout: Hashable {
        case largeHorizontal
        case grid
        case rows
    }

    let id: String
    let title: String
    let layout: Layout
    let tokens: [MarketToken]
    let showsSeeAll: Bool
}

extension MarketSection {
    static func samples() -> [MarketSection] {
        let storeTokens = TokenStore.tokens
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
                .init(
                    fillImageName: "MarketMyWalletChartFill",
                    lineImageName: "MarketMyWalletChartLine",
                    tint: 0x016FFA
                ),
                .init(
                    fillImageName: "MarketJupiterChartFill",
                    lineImageName: "MarketJupiterChartLine",
                    tint: 0x1BB0CA
                ),
                .init(
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
                title: "Today's Movers",
                layout: .largeHorizontal,
                tokens: movers,
                showsSeeAll: false
            ),
            MarketSection(
                id: "popular-tokens",
                title: "Popular Tokens",
                layout: .grid,
                tokens: popular,
                showsSeeAll: true
            ),
            MarketSection(
                id: "tokenized-stocks",
                title: "Tokenized Stocks",
                layout: .grid,
                tokens: stocks,
                showsSeeAll: true
            ),
            MarketSection(
                id: "tokenized-gold",
                title: "Tokenized Gold",
                layout: .rows,
                tokens: gold,
                showsSeeAll: false
            ),
            MarketSection(
                id: "index-funds",
                title: "Index Funds",
                layout: .grid,
                tokens: indices,
                showsSeeAll: true
            ),
        ]
    }
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
