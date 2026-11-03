import Testing
import UIKit
import WalletCore
import WalletContext
@testable import UIAssets

@Suite @MainActor
struct PerpsActivitySectionTests {
    private func activity(title: String = "Increased SOL") -> PerpsHomeActivity {
        .init(id: "fill", kind: .increased, title: title, badge: "10x Long", date: "Aug 10 · 12:05",
              amount: .init("$125"), previousAmount: "$100")
    }

    @Test func titleBadgeAndAmountStaySeparateOnNarrowScreens() {
        for width: CGFloat in [288, 343, 370] {
            for title in ["Increased SOL", "Увеличена SOL", "افزایش SOL"] {
                let cell = PerpsActivityCell(frame: CGRect(x: 0, y: 0, width: width, height: 60))
                cell.configure(activity(title: title))
                cell.layoutIfNeeded()
                let titleFrame = cell.titleLabel.convert(cell.titleLabel.bounds, to: cell.contentView)
                let badgeFrame = cell.badge.convert(cell.badge.bounds, to: cell.contentView)
                let amountFrame = cell.amountLabel.convert(cell.amountLabel.bounds, to: cell.contentView)
                #expect(cell.icon.frame == CGRect(x: 12, y: 10, width: 40, height: 40))
                #expect(abs(titleFrame.minX - 62) < 0.5)
                #expect(abs(badgeFrame.minX - titleFrame.maxX - 4) < 0.5)
                #expect(badgeFrame.maxX <= amountFrame.minX - 7.5)
                #expect(abs(amountFrame.maxX - width + 12) < 0.5)
                #expect(cell.amountLabel.attributedText?.string == "$100 → $125")
                #expect(!cell.hasAmbiguousLayout)
            }
        }
    }

    @Test func staleAccountRowsAndDisabledRowsCannotOpenReceipts() {
        let section = PerpsActivitySectionDataProvider()
        section.accountID = "first"
        section.activities = [activity(), activity()]
        #expect(section.itemIdentifiers.count == 1)
        let oldID = section.itemIdentifiers[0]
        var selected: [String] = []
        section.onSelect = { selected.append($0) }
        section.didSelect(itemIdentifier: oldID)
        section.accountID = "second"
        #expect(!section.shouldSelect(itemIdentifier: oldID))
        section.didSelect(itemIdentifier: oldID)
        section.activities[0].canSelect = false
        #expect(!section.shouldSelect(itemIdentifier: section.itemIdentifiers[0]))
        section.didSelect(itemIdentifier: section.itemIdentifiers[0])
        #expect(selected == ["fill"])
    }

    @Test func fillsUseEventAndDisplaySymbolWithoutInventingHistoricalLeverage() throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"xyz:BTC","name":"xyz:BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"xyz","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}
        """.utf8))
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"xyz:BTC","tid":123,"oid":1,"time":1786454400000,"px":"100","sz":"0.1","side":"A",
         "dir":"Close Long","startPosition":"1","closedPnl":"0","fee":"0","feeToken":"USDC","hash":"hash",
         "eventKind":"reduced","positionSide":"long","notional":"10","netPnl":"-2"}
        """.utf8))
        for (event, title) in [("opened", "Opened BTC"), ("increased", "Increased BTC"),
                                ("reduced", "Reduced BTC"), ("closed", "Closed BTC"), ("liquidated", "Liquidated BTC")] {
            fill.eventKind = event
            let row = try #require(PerpsHomeAdapter.activity(fill: fill, asset: asset))
            #expect(row.title == title)
            #expect(row.badge == "Long")
            let realizesPnl = ["reduced", "closed", "liquidated"].contains(event)
            #expect(row.amount.text == (realizesPnl ? PerpsFormatting.profitLoss("-2") : PerpsFormatting.money("10")))
            #expect(row.amountDetail == lang(realizesPnl ? "Profit and Loss" : "Trade Size"))
            #expect(row.previousAmount == nil)
            #expect(row.date.contains(" · "))
        }
        fill.positionSide = "short"
        #expect(PerpsHomeAdapter.activity(fill: fill, asset: asset)?.badge == "Short")
        fill.eventKind = "unknown"
        #expect(PerpsHomeAdapter.activity(fill: fill, asset: asset) == nil)
    }

    @Test(arguments: ["long", "short"])
    func fillsDisplayOnlyKnownHistoricalLeverage(side: String) throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}
        """.utf8))
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"trade","coin":"BTC","time":1786454400000,"feeToken":"USDC",
         "eventKind":"opened","positionSide":"\(side)","leverage":10,"notional":"100"}
        """.utf8))
        let direction = side == "long" ? "Long" : "Short"
        #expect(PerpsHomeAdapter.activity(fill: fill, asset: asset)?.badge == "10x " + direction)
        for leverage: Int? in [nil, 0, -1] {
            fill.leverage = leverage
            #expect(PerpsHomeAdapter.activity(fill: fill, asset: asset)?.badge == direction)
        }
    }
}
