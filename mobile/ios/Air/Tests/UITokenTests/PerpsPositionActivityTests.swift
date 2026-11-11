import Foundation
import Testing
import UIKit
import UIComponents
import WalletContext
import WalletCore
import WalletResources
@testable import UIToken

@Suite @MainActor
struct PerpsPositionActivityTests {
    @Test func timeChangeUpdatesVisiblePositionHistoryWithoutReplacingItsCell() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let section = PerpsPositionActivitySectionView { _ in }
        let activity = try activity(id: "one", event: .opened)
        section.configure(activities: [activity])
        let host = UIViewController()
        host.view.addSubview(section)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            section.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            section.topAnchor.constraint(equalTo: host.view.topAnchor),
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try #require(section.collectionView.cellForItem(at: indexPath) as? PerpsTradeActivityCell)
        cell.dateLabel.text = "Stale date"

        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))

        #expect(cell.dateLabel.text == activity.date)
        #expect(section.collectionView.cellForItem(at: indexPath) === cell)
    }

    @Test func historyDeduplicatesTradesAndOpensEachOne() throws {
        _ = WalletResourcesBundle.bundle.load()
        var selected: [String] = []
        let section = PerpsPositionActivitySectionView { selected.append($0) }
        let one = try activity(id: "one", event: .opened)
        section.configure(activities: [one, one, try activity(id: "two", event: .closed)])
        #expect(section.collectionView.numberOfItems(inSection: 0) == 2)
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 1, section: 0))
        #expect(selected == ["one", "two"])
    }

    private func activity(id: String, event: ApiPerpsFillEvent) throws -> PerpsTradeActivity {
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"\(id)","coin":"BTC","oid":1,"time":1786454400000,"px":"100","sz":"0.1","feeToken":"USDC",
         "eventKind":"\(event.rawValue)","positionSide":"short","leverage":5,"notional":"10","netPnl":"-2"}
        """.utf8))
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"btc","name":"BTC","symbol":"BTC","dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100"}}
        """.utf8))
        return PerpsTradeActivity(fill: fill, asset: asset)
    }
}
