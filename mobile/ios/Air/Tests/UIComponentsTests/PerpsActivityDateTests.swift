import UIKit
import WalletCore
import WalletContext
import WalletResources
import XCTest
@testable import UIComponents

@MainActor
final class PerpsActivityDateTests: XCTestCase {
    func testTradeDateReformatsAcrossYearsAndTimeZonesFromItsTimestamp() throws {
        let activity = try makeActivity()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")
        let december = Date(timeIntervalSince1970: 1_798_675_200)
        let january = Date(timeIntervalSince1970: 1_798_761_600)
        XCTAssertTrue(activity.formatDate(relativeTo: december, calendar: calendar, locale: locale).hasPrefix("Dec 31 · 11:30"))
        XCTAssertTrue(activity.formatDate(relativeTo: january, calendar: calendar, locale: locale).hasPrefix("Dec 31, 2026 · 11:30"))
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        XCTAssertTrue(activity.formatDate(relativeTo: january, calendar: calendar, locale: locale).hasPrefix("Jan 1 · 1:30"))
    }

    func testVisibleTradeUpdatesOnlyDateAndAccessibilityAndClearsOnReuse() throws {
        _ = WalletResourcesBundle.bundle.load()
        let activity = try makeActivity()
        let cell = PerpsTradeActivityCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        cell.configure(activity, isStale: false, accessibilityPrefix: "trade.")
        let amount = cell.amountLabel.attributedText
        let title = cell.titleLabel.text
        let now = Date(timeIntervalSince1970: 1_798_761_600)
        XCTAssertNil(cell.updateDate(relativeTo: now))
        XCTAssertEqual(cell.dateLabel.text, activity.formatDate(relativeTo: now))
        XCTAssertTrue(cell.accessibilityLabel?.contains(activity.formatDate(relativeTo: now)) == true)
        XCTAssertEqual(cell.amountLabel.attributedText, amount)
        XCTAssertEqual(cell.titleLabel.text, title)
        cell.prepareForReuse()
        cell.dateLabel.text = "Reused"
        cell.updateDate(relativeTo: .distantFuture)
        XCTAssertEqual(cell.dateLabel.text, "Reused")
    }

    private func makeActivity() throws -> PerpsTradeActivity {
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"trade","coin":"BTC","time":1798759800000,"feeToken":"USDC",
         "eventKind":"opened","positionSide":"long","leverage":10,"notional":"100"}
        """.utf8))
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"btc","name":"BTC","symbol":"BTC","dex":"","szDecimals":4,"maxLeverage":40,
         "context":{"markPx":"100"}}
        """.utf8))
        return PerpsTradeActivity(fill: fill, asset: asset)
    }
}
