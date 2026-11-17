import SwiftUI
import WalletContext
import WalletCore

struct MarketToken: Hashable, Identifiable, Sendable {
    typealias Chart = MarketItemDisplayData.Chart

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

        init(_ layout: ApiMarketSectionLayout) {
            self = switch layout {
            case .largeHorizontal: .largeHorizontal
            case .grid: .grid
            case .rows: .rows
            }
        }
    }

    let id: String
    let title: String
    let layout: Layout
    let tokens: [MarketToken]
    let mobileLimit: Int?
    let desktopLimit: Int?
    let hasMore: Bool

    func visibleTokens(columnCount: Int) -> [MarketToken] {
        guard let limit = visibleLimit(columnCount: columnCount) else { return tokens }
        return Array(tokens.prefix(limit))
    }

    func showsSeeAll(columnCount: Int) -> Bool {
        hasMore || visibleLimit(columnCount: columnCount).map { tokens.count > $0 } == true
    }

    private func visibleLimit(columnCount: Int) -> Int? {
        Self.visibleLimit(layout: layout, mobileLimit: mobileLimit, desktopLimit: desktopLimit, columnCount: columnCount)
    }

    /// Market and Futures previews share these limits; `nil` shows every item.
    static func visibleLimit(layout: Layout, mobileLimit: Int?, desktopLimit: Int?, columnCount: Int) -> Int? {
        guard layout == .grid else { return mobileLimit }
        let limit = columnCount > 4 ? desktopLimit ?? mobileLimit : mobileLimit ?? desktopLimit
        return min(limit ?? columnCount * 2, columnCount * 2)
    }

    /// Backend limits, where zero or a negative value means no limit.
    static func limits<Asset>(of section: ApiMarketSection<Asset>) -> (mobile: Int?, desktop: Int?) {
        ((section.mobileLimit ?? section.limit).flatMap { $0 > 0 ? $0 : nil },
         (section.desktopLimit ?? section.limit).flatMap { $0 > 0 ? $0 : nil })
    }
}

enum MarketGridLayout {
    static func columnCount(availableWidth: CGFloat) -> Int {
        // Match the web Market grid's 30rem and 35.5rem container breakpoints.
        if availableWidth >= 568 { return 6 }
        if availableWidth >= 480 { return 5 }
        return 4
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

            let limits = MarketSection.limits(of: section)
            return MarketSection(
                id: section.id,
                title: section.title,
                layout: .init(section.layout),
                tokens: tokens,
                mobileLimit: limits.mobile,
                desktopLimit: limits.desktop,
                hasMore: section.hasMore
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

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}
