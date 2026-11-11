import Foundation
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletContext
@testable import UIAssets

@Suite @MainActor
struct PerpsActivitySectionTests {
    @Test func timeZoneChangeUpdatesVisibleTradeWithoutReplacingItsCell() async throws {
        let section = PerpsActivitySectionDataProvider()
        section.activities = [activity()]
        let collection = PerpsCollectionView()
        collection.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        collection.update(sections: [section])
        let window = UIWindow(frame: collection.frame)
        let host = UIViewController()
        host.view = collection
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try #require(collection.cellForItem(at: indexPath) as? PerpsTradeActivityCell)
        cell.dateLabel.text = "Stale date"
        let amount = cell.amountLabel.attributedText
        let offset = collection.contentOffset

        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(20))

        #expect(cell.dateLabel.text == section.activities[0].date)
        #expect(cell.amountLabel.attributedText == amount)
        #expect(collection.cellForItem(at: indexPath) === cell)
        #expect(collection.contentOffset == offset)
    }

    private func activity() -> PerpsTradeActivity {
        .init(id: "fill", event: .increased, title: "Increased SOL", badge: "10x Long", date: "Aug 10 · 12:05",
              amount: .init("$125"), detail: lang("Trade Size"))
    }

    @Test func removedRowsCannotOpenReceipts() {
        let section = PerpsActivitySectionDataProvider()
        section.activities = [activity()]
        var selected: [String] = []
        section.onSelect = { selected.append($0) }
        section.didSelect(itemIdentifier: "fill")
        section.activities = []
        #expect(!section.shouldSelect(itemIdentifier: "fill"))
        section.didSelect(itemIdentifier: "fill")
        #expect(selected == ["fill"])
    }

    @Test func fillsUseEventAndDisplaySymbolWithoutInventingHistoricalLeverage() throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"xyz:BTC","name":"xyz:BTC","symbol":"BTC","dex":"xyz","szDecimals":4,"maxLeverage":40,
         "context":{"markPx":"100"}}
        """.utf8))
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"xyz:BTC","oid":1,"time":1786454400000,"px":"100","sz":"0.1","fee":"0","feeToken":"USDC",
         "eventKind":"reduced","positionSide":"long","notional":"10","netPnl":"-2"}
        """.utf8))
        for (event, title) in [(ApiPerpsFillEvent.opened, "Opened BTC"), (.increased, "Increased BTC"),
                                (.reduced, "Reduced BTC"), (.closed, "Closed BTC"), (.liquidated, "Liquidated BTC")] {
            fill.eventKind = event
            let row = PerpsTradeActivity(fill: fill, asset: asset)
            #expect(row.title == title)
            #expect(row.badge == "Long")
            #expect(row.amount.text == (event.realizesProfitLoss ? PerpsFormatting.profitLoss("-2").text : PerpsFormatting.money("10")))
            #expect(row.detail == lang(event.realizesProfitLoss ? "Profit and Loss" : "Trade Size"))
            #expect(row.date.contains(" · "))
        }
        fill.positionSide = .short
        #expect(PerpsTradeActivity(fill: fill, asset: asset).badge == "Short")
    }

    @Test(arguments: [ApiPerpsPositionSide.long, .short])
    func fillsDisplayOnlyKnownHistoricalLeverage(side: ApiPerpsPositionSide) throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","dex":"","szDecimals":4,"maxLeverage":40,
         "context":{"markPx":"100"}}
        """.utf8))
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"trade","coin":"BTC","time":1786454400000,"feeToken":"USDC",
         "eventKind":"opened","positionSide":"\(side.rawValue)","leverage":10,"notional":"100"}
        """.utf8))
        let direction = side == .long ? "Long" : "Short"
        #expect(PerpsTradeActivity(fill: fill, asset: asset).badge == "10x " + direction)
        for leverage: Int? in [nil, 0, -1] {
            fill.leverage = leverage
            #expect(PerpsTradeActivity(fill: fill, asset: asset).badge == direction)
        }
    }
}
