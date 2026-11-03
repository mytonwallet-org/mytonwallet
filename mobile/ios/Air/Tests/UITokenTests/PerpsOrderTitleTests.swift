import Testing
import UIKit
import WalletResources
@testable import UIToken

@MainActor
struct PerpsOrderTitleTests {
    @Test func pixelRoundingDoesNotReplaceAFittingName() throws {
        _ = WalletResourcesBundle.bundle.load()
        let title = PerpsOrderTitleView()
        title.configure(title: "Bitcoin Long", compactTitle: "BTC Long", price: "Price $64 845")
        let label = try #require(title.subviews.first as? UILabel)
        let measured = "Bitcoin Long".size(withAttributes: [.font: label.font!]).width
        title.frame = CGRect(x: 0, y: 0, width: floor(measured * 3) / 3, height: 44)
        title.layoutIfNeeded()
        #expect(label.text == "Bitcoin Long")
    }

    @Test func longNamesUseTickerBeforeShrinking() throws {
        _ = WalletResourcesBundle.bundle.load()
        let title = PerpsOrderTitleView()
        title.configure(title: "A very long market name Long", compactTitle: "BTC Long", price: "Price $64 845")
        #expect(title.bounds.width > 0 && title.bounds.height == 44)
        title.frame = CGRect(x: 0, y: 0, width: 140, height: 44)
        title.layoutIfNeeded()
        let label = try #require(title.subviews.first as? UILabel)
        #expect(label.text == "BTC Long")
        #expect(title.accessibilityLabel == "A very long market name Long")
        title.frame.size.width = 400
        title.setNeedsLayout()
        title.layoutIfNeeded()
        #expect(label.text == "A very long market name Long")
    }
}
