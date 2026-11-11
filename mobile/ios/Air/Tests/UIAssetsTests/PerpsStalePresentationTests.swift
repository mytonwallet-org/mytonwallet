import Dependencies
import Testing
import UIComponents
import UIKit
import WalletResources
@testable import UIAssets

@MainActor @Suite(.serialized)
struct PerpsStalePresentationTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func marketPricesRetainTheirTextAndClearTheirStaleAppearanceOnReuse() {
        let cell = MarketRowCell(frame: CGRect(x: 0, y: 0, width: 370, height: 60))
        var item = MarketItemDisplayData(id: "btc", token: .TONCOIN, price: "$100", change: "−2%", isPositive: false, isStale: true)
        cell.configure(item, showsChevron: false)
        cell.layoutIfNeeded()
        let shines = descendants(cell).compactMap { $0 as? TradeShineView }
        #expect(!shines.isEmpty)
        #expect(shines.allSatisfy { abs($0.content.alpha - 0.55) < 0.0001 })
        #expect(cell.accessibilityLabel?.contains("$100") == true)
        item.isStale = false
        item.priceText = "$101"
        cell.configure(item, showsChevron: false)
        #expect(shines.allSatisfy { $0.content.alpha == 1 })
        #expect(cell.accessibilityLabel?.contains("$101") == true)
    }

    @Test func fullMarketListRefreshesItsExistingRowsAndSelectionWithoutResettingScroll() async throws {
        try await withDependencies { $0.context = .live } operation: {
            var tokens = (0..<25).map { index in
                MarketItemDisplayData(id: "market-\(index)", token: .TONCOIN, price: "$100", change: "1%", isPositive: true, isStale: true)
            }
            var selected: MarketItemDisplayData?
            var visibility: [Bool] = []
            let controller = MarketTokenListVC(title: "Markets", tokens: tokens) { selected = $0 }
            controller.onVisibilityChanged = { visibility.append($0) }
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
            controller.view.layoutIfNeeded()
            let collection = try #require(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
            collection.contentOffset.y = 180
            tokens = tokens.map { item in
                var item = item
                item.priceText = "$200"
                item.isStale = false
                return item
            }
            controller.update(tokens: tokens)
            try await Task.sleep(for: .milliseconds(50))
            collection.layoutIfNeeded()
            #expect(collection.numberOfItems(inSection: 0) == 25)
            #expect(collection.contentOffset.y == 180)
            controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 0))
            #expect(selected?.id == "market-0")
            #expect(selected?.priceText == "$200")
            #expect(selected?.isStale == false)
            controller.viewDidAppear(false)
            controller.viewDidDisappear(false)
            #expect(visibility == [true, false])
        }
    }

    @Test func stalePositionValuesKeepTheirAutoLayoutSize() throws {
        try withDependencies { $0.context = .live } operation: {
            let cell = PerpsPositionCell(frame: CGRect(x: 0, y: 0, width: 370, height: 60))
            let row = PerpsPositionRowDisplayData(id: "btc", token: .TONCOIN, directionAndLeverage: "Long 2x",
                value: "$123.45", profitLoss: .init("+$1 (1%)"))
            cell.configure(row, isStale: true)
            cell.layoutIfNeeded()
            let shine = try #require(descendants(cell).compactMap { $0 as? TradeShineView }.first)
            let size = shine.bounds.size
            #expect(size.width > 0)
            #expect(size.height > 0)
            #expect(abs(shine.content.alpha - 0.55) < 0.0001)
            cell.configure(row, isStale: false)
            cell.layoutIfNeeded()
            #expect(shine.bounds.size == size)
            #expect(shine.content.alpha == 1)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
