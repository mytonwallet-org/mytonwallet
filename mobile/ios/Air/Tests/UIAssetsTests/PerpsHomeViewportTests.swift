import Dependencies
import Testing
import UIKit
import WalletCore
import WalletContext
import WalletResources
@testable import UIAssets

@Suite @MainActor
struct PerpsHomeViewportTests {
    @Test func operationBannerFitsItsMessageAndProvidesSeparateStatusAndDismissActions() throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            let controller = PerpsHomeVC(data: .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: [])), onAction: { _ in })
            var selected = false
            var dismissed = false
            let message = lang("PerpsExecutionUnknown")
            controller.updateOperationStatus(.init(title: "Open Position · BTC", message: message, onSelect: { selected = true }, onDismiss: {
                dismissed = true
                controller.updateOperationStatus(nil)
            }))
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
            #expect(collection.numberOfSections == 1)
        }
    }

    @Test func parentInsetsWorkWithoutInheritedSafeAreaAndPreserveScrollPosition() throws {
        try withDependencies { $0.context = .live } operation: {
            let activities = (0..<20).map {
                PerpsHomeActivity(id: "fill-\($0)", kind: .opened, title: "Opened BTC", badge: "Long",
                                  date: "Oct 25 · 12:00", amount: .init("0.1 BTC"))
            }
            let controller = PerpsHomeVC(data: .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD),
                profitLoss: .init("$0"), positions: []), activities: activities), onAction: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            #expect(controller.view.safeAreaInsets == .zero)
            controller.updateScrollInsets(.init(top: 116, left: 0, bottom: 98, right: 0))
            controller.view.layoutIfNeeded()
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
            #expect(collection.frame == controller.view.bounds)
            #expect(collection.adjustedContentInset == .init(top: 116, left: 0, bottom: 130, right: 0))
            #expect(collection.contentOffset.y == -116)
            collection.contentOffset.y = 100
            controller.updateScrollInsets(.init(top: 132, left: 0, bottom: 80, right: 0))
            #expect(collection.contentOffset.y == 100)
            #expect(collection.adjustedContentInset.bottom == 112)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}
