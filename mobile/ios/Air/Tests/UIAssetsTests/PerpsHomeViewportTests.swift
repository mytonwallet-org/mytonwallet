import Dependencies
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletContext
import WalletResources
@testable import UIAssets

@Suite @MainActor
struct PerpsHomeViewportTests {
    @Test func operationBannerFitsItsMessageAndProvidesSeparateStatusAndDismissActions() throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            var data = PerpsHomeDisplayData(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: []))
            let controller = PerpsHomeVC(data: data, onAction: { _ in })
            var selected = false
            var dismissed = false
            let message = lang("PerpsExecutionUnknown")
            data.operationStatus = .init(title: "Open Position · BTC", message: message, onSelect: { selected = true }, onDismiss: {
                dismissed = true
                data.operationStatus = nil
                controller.update(data: data)
            })
            controller.update(data: data)
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 874)
            controller.view.layoutIfNeeded()
            let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
            let cell = try #require(collection.visibleCells.first { $0.accessibilityIdentifier == "perps.operation.banner" } as? UICollectionViewListCell)
            let configuration = try #require(cell.contentConfiguration as? UIListContentConfiguration)
            #expect(configuration.text == "Open Position · BTC")
            #expect(configuration.secondaryText == message)
            #expect(cell.bounds.height > 48)
            let index = try #require(collection.indexPath(for: cell))
            collection.delegate?.collectionView?(collection, didSelectItemAt: index)
            #expect(selected)
            let dismiss = try #require(descendants(cell).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "perps.operation.dismiss" })
            dismiss.sendActions(for: .touchUpInside)
            #expect(dismissed)
            #expect(collection.numberOfSections == 0)
        }
    }

    @Test func parentInsetsWorkWithoutInheritedSafeAreaAndPreserveScrollPosition() throws {
        try withDependencies { $0.context = .live } operation: {
            let activities = (0..<20).map {
                PerpsTradeActivity(id: "fill-\($0)", event: .opened, title: "Opened BTC", badge: "Long",
                                   date: "Oct 25 · 12:00", amount: .init("0.1 BTC"), detail: "Trade Size")
            }
            let controller = PerpsHomeVC(data: .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: []), activities: activities), onAction: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            #expect(controller.view.safeAreaInsets == .zero)
            controller.updateScrollInsets(.init(top: 116, left: 0, bottom: 98, right: 0), layoutMargins: .init(top: 0, left: 20, bottom: 0, right: 20))
            controller.view.layoutIfNeeded()
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
            #expect(collection.frame == controller.view.bounds)
            #expect(collection.adjustedContentInset == .init(top: 116, left: 0, bottom: 130, right: 0))
            #expect(collection.contentOffset.y == -116)
            collection.contentOffset.y = 100
            controller.updateScrollInsets(.init(top: 132, left: 0, bottom: 80, right: 0), layoutMargins: .init(top: 0, left: 20, bottom: 0, right: 20))
            #expect(collection.contentOffset.y == 100)
            #expect(collection.adjustedContentInset.bottom == 112)
        }
    }

    @Test(arguments: [
        (CGSize(width: 440, height: 956), UIEdgeInsets(top: 116, left: 0, bottom: 98, right: 0)),
        (CGSize(width: 956, height: 440), UIEdgeInsets(top: 62, left: 62, bottom: 21, right: 62)),
        (CGSize(width: 466, height: 678), UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)),
        (CGSize(width: 842, height: 640), UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0)),
        (CGSize(width: 466, height: 678), UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 86)),
        (CGSize(width: 466, height: 678), UIEdgeInsets(top: 24, left: 86, bottom: 24, right: 0)),
        (CGSize(width: 842, height: 640), UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 86)),
    ])
    func parentSideInsetsDoNotCreateHorizontalScrollRange(size: CGSize, insets: UIEdgeInsets) throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            let activities = (0..<20).map {
                PerpsTradeActivity(id: "fill-\($0)", event: .opened, title: "Opened BTC", badge: "Long",
                                  date: "Oct 25 · 12:00", amount: .init("0.1 BTC"), detail: "Trade Size")
            }
            let controller = PerpsHomeVC(data: .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: []), activities: activities, showsOnboarding: true), onAction: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: size)
            let margins = UIEdgeInsets(top: 0, left: max(20, insets.left), bottom: 0, right: max(20, insets.right))
            controller.updateScrollInsets(insets, layoutMargins: margins)
            controller.view.layoutIfNeeded()
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            controller.view.layoutIfNeeded()
            let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
            let horizontalScrollRange = collection.contentSize.width + collection.adjustedContentInset.left
                + collection.adjustedContentInset.right - collection.bounds.width
            #expect(abs(horizontalScrollRange) < 1)
            #expect(collection.frame == controller.view.bounds)
            let banner = try #require(collection.layoutAttributesForItem(at: .init(item: 0, section: 0)))
            #expect(banner.frame.minX == margins.left)
            #expect(banner.frame.maxX == size.width - margins.right)
            let visibleBannerFrame = collection.convert(banner.frame, to: controller.view)
            #expect(visibleBannerFrame.minY >= 16)
            if insets.top > 0 { #expect(visibleBannerFrame.minY == insets.top) }
            #expect(collection.contentSize.height > collection.bounds.height)
            #expect(collection.contentOffset.x == -collection.adjustedContentInset.left)

            collection.contentOffset.y = 100
            let changedInsets = UIEdgeInsets(top: insets.top, left: insets.right, bottom: insets.bottom, right: insets.left + 12)
            let changedMargins = UIEdgeInsets(top: 0, left: margins.right, bottom: 0, right: margins.left + 12)
            controller.updateScrollInsets(changedInsets, layoutMargins: changedMargins)
            controller.view.layoutIfNeeded()
            #expect(collection.frame == controller.view.bounds)
            let changedBanner = try #require(collection.layoutAttributesForItem(at: .init(item: 0, section: 0)))
            #expect(changedBanner.frame.minX == changedMargins.left)
            #expect(changedBanner.frame.maxX == size.width - changedMargins.right)
            #expect(abs(collection.contentSize.width - collection.bounds.width) < 1)
            #expect(collection.contentOffset == CGPoint(x: 0, y: 100))
        }
    }

    @Test(arguments: [CGSize(width: 466, height: 678), CGSize(width: 956, height: 440)], [false, true])
    func marketCardsRemainLoadedUntilTheyLeaveTheScreen(size: CGSize, isSidebarOnLeft: Bool) throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            let market = MarketSectionDisplayData(id: "featured", title: "", layout: .largeHorizontal, tokens: (0..<6).map {
                .init(id: "token-\($0)", token: .TONCOIN, name: "Token \($0)", price: "$5", change: "+1%", isPositive: true)
            }, showsSeeAll: false)
            let grid = MarketSectionDisplayData(id: "popular", title: "Popular", layout: .grid,
                                               tokens: Array(market.tokens.prefix(4)), showsSeeAll: true)
            let controller = PerpsHomeVC(data: .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: []), marketSections: [market, grid]), onAction: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: size)
            let insets = UIEdgeInsets(top: 24, left: isSidebarOnLeft ? 86 : 0, bottom: 24, right: isSidebarOnLeft ? 0 : 86)
            let margins = UIEdgeInsets(top: 0, left: max(20, insets.left), bottom: 0, right: max(20, insets.right))
            controller.updateScrollInsets(insets, layoutMargins: margins)
            controller.view.layoutIfNeeded()
            let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
            let section = try #require(collection.visibleCells.compactMap { $0 as? MarketSectionCell }.first { $0.market.section?.id == market.id })
            #expect(collection.contentSize.width == collection.bounds.width)
            let gridCell = try #require(collection.visibleCells.compactMap { $0 as? MarketSectionCell }.first { $0.market.section?.id == grid.id })
            gridCell.layoutIfNeeded()
            gridCell.market.layoutIfNeeded()
            let gridFrame = gridCell.market.collection.convert(gridCell.market.collection.bounds, to: controller.view)
            #expect(gridFrame.minX == margins.left)
            #expect(gridFrame.maxX == size.width - margins.right)
            section.layoutIfNeeded()
            section.market.layoutIfNeeded()
            let carousel = section.market.collection
            #expect(carousel.contentInset.left == margins.left)
            #expect(carousel.contentInset.right == margins.right)
            let viewport = carousel.convert(carousel.bounds, to: controller.view)
            #expect(viewport.minX == 0)
            #expect(viewport.width == controller.view.bounds.width)
            let offsets = stride(from: CGFloat(-16), through: 600, by: 8).map { $0 }
            for offset in offsets + offsets.reversed() {
                carousel.contentOffset.x = offset
                carousel.layoutIfNeeded()
                for index in market.tokens.indices {
                    let indexPath = IndexPath(item: index, section: 0)
                    let attributes = try #require(carousel.layoutAttributesForItem(at: indexPath))
                    let frame = carousel.convert(attributes.frame, to: controller.view)
                    guard frame.intersection(controller.view.bounds).width > 1 else { continue }
                    let card = try #require(carousel.cellForItem(at: indexPath), "Card \(index) at offset \(offset) intersects the screen")
                    var visibleFrame = card.convert(card.bounds, to: controller.view)
                    var ancestor = card.superview
                    while let view = ancestor {
                        if view.clipsToBounds {
                            visibleFrame = visibleFrame.intersection(view.convert(view.bounds, to: controller.view))
                        }
                        ancestor = view.superview
                    }
                    #expect(visibleFrame == frame.intersection(controller.view.bounds))
                }
            }
            #expect(collection.contentOffset.x == 0)
            #expect(carousel.contentSize.width > carousel.bounds.width)

            carousel.contentOffset.x = 40
            controller.updateScrollInsets(.init(top: 24, left: insets.right, bottom: 24, right: insets.left),
                                          layoutMargins: .init(top: 0, left: margins.right, bottom: 0, right: margins.left))
            controller.view.layoutIfNeeded()
            section.layoutIfNeeded()
            section.market.layoutIfNeeded()
            gridCell.layoutIfNeeded()
            gridCell.market.layoutIfNeeded()
            let updatedViewport = carousel.convert(carousel.bounds, to: controller.view)
            #expect(updatedViewport.minX == 0)
            #expect(updatedViewport.width == size.width)
            #expect(carousel.contentOffset.x == 40)
            #expect(carousel.contentInset.left == margins.right)
            #expect(carousel.contentInset.right == margins.left)
            let updatedGridFrame = gridCell.market.collection.convert(gridCell.market.collection.bounds, to: controller.view)
            #expect(updatedGridFrame.minX == margins.right)
            #expect(updatedGridFrame.maxX == size.width - margins.left)
            #expect(collection.contentSize.width == collection.bounds.width)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}
