import Testing
import UIKit
import UIComponents
import WalletContext
import WalletCore
@testable import UIAssets

@Suite @MainActor
struct MarketSectionLayoutTests {
    private func section(_ layout: MarketSectionDisplayData.Layout, count: Int, title: String = "Market") -> MarketSectionDisplayData {
        .init(id: "test", title: title, layout: layout, tokens: (0..<count).map {
            .init(id: "token-\($0)", token: .TONCOIN, name: "Token \($0)", price: "$5.21", change: "+6.63%", isPositive: true)
        }, showsSeeAll: true)
    }

    @Test func allDesignVariantsHaveTheExpectedHeight() {
        #expect(MarketSectionContentView.height(for: section(.largeHorizontal, count: 3, title: "")) == 160)
        #expect(MarketSectionContentView.height(for: section(.grid, count: 8)) == 291)
        #expect(MarketSectionContentView.height(for: section(.grid, count: 4)) == 177)
        #expect(MarketSectionContentView.height(for: section(.grid, count: 5)) == 291)
        #expect(MarketSectionContentView.height(for: section(.rows, count: 1)) == 99)
        #expect(MarketSectionContentView.height(for: section(.rows, count: 3)) == 219)
        #expect(MarketSectionContentView.height(for: section(.grid, count: 0)) == 0)
    }

    @Test func gridUsesFourColumnsAndDesignInsetsAtCompactAndNormalWidths() throws {
        for width: CGFloat in [320, 402] {
            let view = makeView(section(.grid, count: 8), width: width)
            #expect(!view.collection.isScrollEnabled)
            #expect(!view.collection.delaysContentTouches)
            #expect(view.collection.frame == CGRect(x: 16, y: 39, width: width - 32, height: 252))
            let frames = try (0..<8).map { try #require(view.collection.layoutAttributesForItem(at: .init(item: $0, section: 0))).frame }
            #expect(frames[0].minX == 5)
            #expect(frames[0].minY == 20)
            #expect(frames[0].height == 98)
            #expect(frames[3].minY == frames[0].minY)
            #expect(frames[4].minY - frames[0].maxY == 16)
            #expect(abs(frames[3].maxX - (width - 37)) < 1)
        }
    }

    @Test func quoteUpdatesPreserveCarouselOffsetAndUseTheLatestItem() throws {
        let view = makeView(section(.largeHorizontal, count: 6, title: ""))
        #expect(view.collection.isScrollEnabled)
        #expect(!view.collection.delaysContentTouches)
        #expect(!view.collection.showsHorizontalScrollIndicator)
        let first = try #require(view.collection.layoutAttributesForItem(at: .init(item: 0, section: 0)))
        let second = try #require(view.collection.layoutAttributesForItem(at: .init(item: 1, section: 0)))
        #expect(first.size == CGSize(width: 160, height: 160))
        #expect(second.frame.minX - first.frame.maxX == 16)
        view.collection.contentOffset.x = 150
        view.collection.layoutIfNeeded()
        let previousCell = try #require(view.collection.cellForItem(at: .init(item: 1, section: 0)))
        var data = section(.largeHorizontal, count: 6, title: "")
        data.tokens[1].priceText = "$99"
        var selected: String?
        view.configure(data, onSeeAll: {}, onSelect: { selected = $0.priceText })
        view.layoutIfNeeded()
        view.collection.layoutIfNeeded()
        #expect(view.collection.contentOffset.x == 150)
        #expect(view.collection.cellForItem(at: .init(item: 1, section: 0)) === previousCell)
        #expect(previousCell.accessibilityLabel?.contains("$99") == true)
        view.collectionView(view.collection, didSelectItemAt: .init(item: 1, section: 0))
        #expect(selected == "$99")
    }

    @Test func gridHighlightFadesOnlyContentAndResetsWhenReused() throws {
        let view = makeView(section(.grid, count: 4))
        let cell = try #require(view.collection.cellForItem(at: .init(item: 0, section: 0)) as? MarketTileCell)
        cell.isHighlighted = true
        #expect(cell.backgroundColor == UIColor.clear)
        #expect(cell.contentView.alpha == 0.5)
        cell.isHighlighted = false
        #expect(cell.contentView.alpha == 1)
        cell.isHighlighted = true
        cell.prepareForReuse()
        #expect(cell.contentView.alpha == 1)
        #expect(!cell.isHighlighted)
    }

    @Test func futuresIconsOmitChainAccessoriesWithoutChangingMarketDefaults() throws {
        for layout in [MarketSectionDisplayData.Layout.rows, .largeHorizontal] {
            var data = section(layout, count: 1)
            data.tokens[0].token = .init(slug: "test-token", name: "Token", symbol: "TOKEN", decimals: 6, chain: .ton)
            let view = makeView(data)
            let cell = try #require(view.collection.cellForItem(at: .init(item: 0, section: 0)))
            func accessories(in view: UIView) -> [IconAccessoryView] {
                view.subviews.flatMap { ($0 as? IconAccessoryView).map { [$0] } ?? accessories(in: $0) }
            }
            let accessory = try #require(accessories(in: cell).first)
            #expect(!accessory.isHidden)
            data.tokens[0].showsChain = false
            view.configure(data, onSeeAll: {}, onSelect: { _ in })
            view.layoutIfNeeded()
            view.collection.layoutIfNeeded()
            #expect(accessory.isHidden)
            data.tokens[0].showsChain = true
            view.configure(data, onSeeAll: {}, onSelect: { _ in })
            view.layoutIfNeeded()
            view.collection.layoutIfNeeded()
            #expect(!accessory.isHidden)
        }
    }

    @Test func gridReflowsWhenTheColumnCountChanges() throws {
        let data = section(.grid, count: 12)
        let view = MarketSectionContentView()
        var firstCell: UICollectionViewCell?
        for columns in [4, 5, 6, 4] {
            view.configure(data, columnCount: columns, onSeeAll: {}, onSelect: { _ in })
            let height = MarketSectionContentView.height(for: data, columnCount: columns)
            view.frame = CGRect(x: 0, y: 0, width: columns == 4 ? 402 : 640, height: height)
            view.layoutIfNeeded()
            view.collection.layoutIfNeeded()
            let cell = try #require(view.collection.cellForItem(at: .init(item: 0, section: 0)))
            if let firstCell { #expect(cell === firstCell) }
            firstCell = cell
            let frames = try (0..<12).map {
                try #require(view.collection.layoutAttributesForItem(at: .init(item: $0, section: 0))).frame
            }
            #expect(frames[columns - 1].minY == frames[0].minY)
            #expect(frames[columns].minY - frames[0].maxY == 16)
            let pixelRounding = CGFloat(columns) / max(view.traitCollection.displayScale, 1)
            #expect(abs(frames[columns - 1].maxX - (view.collection.bounds.width - 5)) <= pixelRounding)
            #expect(frames.last!.maxY + 20 == view.collection.bounds.height)
            #expect(view.intrinsicContentSize.height == height)
        }
    }

    @Test func carouselKeepsItsLeadingMarginWhenTheParentResolvesInsetsAfterCreation() {
        let data = section(.largeHorizontal, count: 6, title: "")
        let view = MarketSectionContentView()
        view.configure(data, insets: .zero, onSeeAll: {}, onSelect: { _ in })
        view.frame = CGRect(x: 0, y: 0, width: 402, height: 160)
        view.layoutIfNeeded()
        view.configure(data, onSeeAll: {}, onSelect: { _ in })
        view.layoutIfNeeded()
        #expect(view.collection.contentOffset.x == -16)
    }

    @Test func reusedSectionCanSwitchLayoutsWithTheSameItemIDs() throws {
        let view = makeView(section(.grid, count: 4))
        #expect(view.collection.cellForItem(at: .init(item: 0, section: 0)) is MarketTileCell)
        let rows = section(.rows, count: 4)
        view.configure(rows, onSeeAll: {}, onSelect: { _ in })
        view.frame.size.height = MarketSectionContentView.height(for: rows)
        view.layoutIfNeeded()
        view.collection.layoutIfNeeded()
        let cell = try #require(view.collection.cellForItem(at: .init(item: 0, section: 0)) as? MarketRowCell)
        #expect(cell.frame.height == 60)
        cell.isHighlighted = true
        #expect(cell.backgroundColor == UIColor.air.highlight)
        cell.isHighlighted = false
        #expect(cell.backgroundColor == UIColor.clear)
    }

    @Test func reusedSectionReplacesItsItemsBeforeChangingLayout() throws {
        let view = makeView(section(.largeHorizontal, count: 6, title: ""))
        view.collection.contentOffset.x = 350
        view.collection.layoutIfNeeded()
        for (index, layout) in [MarketSectionDisplayData.Layout.grid, .rows, .largeHorizontal].enumerated() {
            let data = MarketSectionDisplayData(id: "replacement-\(index)", title: "", layout: layout,
                tokens: (0..<8).map {
                    .init(id: "replacement-\(index)-\($0)", token: .TONCOIN, price: "$10", change: "1%", isPositive: true)
                })
            var selected: String?
            view.configure(data, onSeeAll: {}, onSelect: { selected = $0.id })
            view.frame.size.height = MarketSectionContentView.height(for: data)
            view.layoutIfNeeded()
            view.collection.layoutIfNeeded()
            #expect(view.collection.numberOfItems(inSection: 0) == 8)
            let cell = try #require(view.collection.cellForItem(at: .init(item: 0, section: 0)))
            switch layout {
            case .grid: #expect(cell is MarketTileCell)
            case .rows: #expect(cell is MarketRowCell)
            case .largeHorizontal: #expect(cell is MarketMoverCell)
            }
            view.collectionView(view.collection, didSelectItemAt: .init(item: 0, section: 0))
            #expect(selected == data.tokens[0].id)
        }
    }

    @Test func featuredCardsScrollBehindTheParentSafeAreaWithoutSticking() throws {
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.additionalSafeAreaInsets.top = 100
        let scroll = UIScrollView(frame: controller.view.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 402, height: 1_500)
        controller.view.addSubview(scroll)
        let view = makeView(section(.largeHorizontal, count: 6, title: ""))
        view.frame.origin.y = 250
        scroll.addSubview(view)
        window.layoutIfNeeded()
        let initialFrame = try #require(view.collection.layoutAttributesForItem(at: .init(item: 0, section: 0))).frame
        for offset: CGFloat in [0, 180, 250, 300] {
            scroll.contentOffset.y = offset
            window.layoutIfNeeded()
            view.collection.layoutIfNeeded()
            let frame = try #require(view.collection.layoutAttributesForItem(at: .init(item: 0, section: 0))).frame
            #expect(frame == initialFrame)
            #expect(abs(view.collection.convert(frame, to: controller.view).minY - (250 - offset)) < 0.5)
        }
        #expect(view.collection.safeAreaInsets.top > 0)
    }

    @Test func consecutiveMembershipChangesKeepTheRetainedCellAndLatestSelection() async throws {
        let view = makeView(section(.largeHorizontal, count: 6, title: ""))
        view.collection.contentOffset.x = 150
        view.collection.layoutIfNeeded()
        let retainedCell = try #require(view.collection.cellForItem(at: .init(item: 1, section: 0)))
        var data = section(.largeHorizontal, count: 6, title: "")
        var selected: String?
        for iteration in 0..<10 {
            data.tokens = [data.tokens[0], data.tokens[1]] + (2..<6).map {
                .init(id: "new-\(iteration)-\($0)", token: .TONCOIN, price: "$10", change: "1%", isPositive: true)
            }
            data.tokens[1].priceText = "$\(iteration)"
            view.configure(data, onSeeAll: {}, onSelect: { selected = $0.priceText })
        }
        try await Task.sleep(for: .milliseconds(100))
        view.layoutIfNeeded()
        view.collection.layoutIfNeeded()
        #expect(view.collection.numberOfItems(inSection: 0) == 6)
        #expect(view.collection.cellForItem(at: .init(item: 1, section: 0)) === retainedCell)
        #expect(retainedCell.accessibilityLabel?.contains("$9") == true)
        #expect(view.collection.contentOffset.x == 150)
        view.collectionView(view.collection, didSelectItemAt: .init(item: 1, section: 0))
        #expect(selected == "$9")
    }

    private func makeView(_ data: MarketSectionDisplayData, width: CGFloat = 402) -> MarketSectionContentView {
        let view = MarketSectionContentView(frame: CGRect(x: 0, y: 0, width: width, height: MarketSectionContentView.height(for: data)))
        view.configure(data, onSeeAll: {}, onSelect: { _ in })
        view.layoutIfNeeded()
        view.collection.layoutIfNeeded()
        return view
    }
}
