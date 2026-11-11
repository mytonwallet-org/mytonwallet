import WalletCore

/// Render-ready market content shared by Market and Futures. Formatting and pricing belong to callers.
public struct MarketItemDisplayData: Identifiable {
    public enum Chart: Hashable, Sendable {
        case bundled(fillImageName: String, lineImageName: String, tint: UInt32)
        case sparkline(points: [Double], tint: UInt32)

        var tint: UInt32 {
            switch self {
            case .bundled(_, _, let tint), .sparkline(_, let tint): tint
            }
        }
    }

    public let id: String
    public var token: ApiToken
    public var name: String
    public var priceText: String?
    public var changeText: String
    public var isPositive: Bool
    public var chart: Chart?
    public var showsChain: Bool
    public var isStale: Bool

    public init(id: String, token: ApiToken, name: String? = nil, price: String? = nil,
                change: String, isPositive: Bool, chart: Chart? = nil, showsChain: Bool = true, isStale: Bool = false) {
        self.id = id
        self.token = token
        self.name = name ?? token.displayName(strippingLabelWhenShown: true)
        self.priceText = price
        self.changeText = change
        self.isPositive = isPositive
        self.chart = chart
        self.showsChain = showsChain
        self.isStale = isStale
    }
}

public struct MarketSectionDisplayData: Identifiable {
    public enum Layout: Sendable, Hashable {
        case largeHorizontal, grid, rows

        init(_ layout: MarketSection.Layout) {
            self = switch layout {
            case .largeHorizontal: .largeHorizontal
            case .grid: .grid
            case .rows: .rows
            }
        }
    }
    public let id: String
    public var title: String
    public var layout: Layout
    public var tokens: [MarketItemDisplayData]
    public var showsSeeAll: Bool

    public init(id: String, title: String, layout: Layout, tokens: [MarketItemDisplayData], showsSeeAll: Bool = false) {
        self.id = id
        self.title = title
        self.layout = layout
        self.tokens = tokens
        self.showsSeeAll = showsSeeAll
    }
}

extension MarketToken {
    var presentation: MarketItemDisplayData {
        .init(id: id, token: token, name: name, price: priceText, change: changeText, isPositive: isPositive, chart: chart)
    }
}

extension MarketSection {
    func presentation(columnCount: Int) -> MarketSectionDisplayData {
        .init(id: id, title: title, layout: .init(layout), tokens: visibleTokens(columnCount: columnCount).map(\.presentation),
              showsSeeAll: showsSeeAll(columnCount: columnCount))
    }
}
