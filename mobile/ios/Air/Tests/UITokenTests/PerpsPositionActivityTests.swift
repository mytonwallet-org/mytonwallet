import Testing
import UIKit
import UIComponents
import WalletResources
@testable import UIToken

@Suite @MainActor
struct PerpsPositionActivityTests {
    private func activity(_ id: String, kind: PerpsPositionDisplayData.Activity.Kind = .opened,
                          canSelect: Bool = true) -> PerpsPositionDisplayData.Activity {
        .init(id: id, kind: kind, title: "Opened Long", date: "Aug 10 · 12:05",
              amount: .init("$1 000"), detail: "$200 · 5x leverage", canSelect: canSelect)
    }

    @Test func nativeHistoryDeduplicatesAndOnlyOpensAvailableDetails() {
        _ = WalletResourcesBundle.bundle.load()
        var selected: [String] = []
        let section = PerpsPositionActivitySectionView { selected.append($0) }
        section.configure(activities: [activity("one"), activity("one"), activity("two", canSelect: false)])
        let size = section.systemLayoutSizeFitting(CGSize(width: 343, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        #expect(size.height == 159)
        #expect(!section.collectionView.isScrollEnabled)
        #expect(!section.collectionView.delaysContentTouches)
        #expect(section.collectionView.numberOfItems(inSection: 0) == 2)
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 1, section: 0))
        #expect(selected == ["one"])
        section.configure(activities: [])
        #expect(section.systemLayoutSizeFitting(CGSize(width: 343, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height == 0)
    }

    @Test func allEventsKeepNativeIconsAndSeparateAmountLinesOnNarrowScreens() {
        _ = WalletResourcesBundle.bundle.load()
        let kinds: [PerpsPositionDisplayData.Activity.Kind] = [.opened, .increased, .reduced, .closed, .liquidated]
        for kind in kinds {
            let cell = PerpsPositionActivityCell(frame: CGRect(x: 0, y: 0, width: 288, height: 60))
            cell.configure(activity("fill", kind: kind))
            cell.layoutIfNeeded()
            #expect(cell.icon.frame == CGRect(x: 12, y: 8, width: 44, height: 44))
            #expect(cell.icon.imageView.image != nil)
            #expect(!cell.detailLabel.isHidden)
            let title = cell.titleLabel.convert(cell.titleLabel.bounds, to: cell.contentView)
            let amount = cell.amountLabel.convert(cell.amountLabel.bounds, to: cell.contentView)
            #expect(title.maxX <= amount.minX - 7.5)
            #expect(!cell.hasAmbiguousLayout)
            cell.isHighlighted = true
            #expect(cell.isHighlighted)
            cell.configure(activity("fill", kind: kind, canSelect: false))
            cell.isHighlighted = true
            #expect(!cell.isHighlighted)
        }
    }
}
