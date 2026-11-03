import Testing
import UIKit
import UIComponents
import WalletResources
@testable import UIAssets

@Suite @MainActor
struct HomeExploreLayoutTests {
    @Test func nativeExploreTracksItsRowsAndUsesImmediateTouches() {
        _ = WalletResourcesBundle.bundle.load()
        let section = HomeExploreSectionContentView()
        var selected: [HomeExploreDestination] = []
        section.configure(destinations: [.market, .agent, .futures, .apps, .apps]) { selected.append($0) }
        #expect(section.intrinsicContentSize.height == 279)
        #expect(!section.collectionView.delaysContentTouches)
        #expect(!section.collectionView.isScrollEnabled)
        #expect(section.collectionView.numberOfItems(inSection: 0) == 4)
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 1, section: 0))
        section.collectionView(section.collectionView, didSelectItemAt: IndexPath(item: 2, section: 0))
        #expect(selected == [.agent, .futures])
        section.configure(destinations: []) { _ in }
        #expect(section.intrinsicContentSize.height == 0)
        #expect(section.systemLayoutSizeFitting(CGSize(width: 343, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height == 0)
    }

    @Test func exploreUsesStandardIconAndLocalizedLabelMetrics() {
        _ = WalletResourcesBundle.bundle.load()
        for destination in HomeExploreDestination.allCases {
            let cell = HomeExploreCell(frame: CGRect(x: 0, y: 0, width: 288, height: 60))
            cell.configure(destination)
            cell.layoutIfNeeded()
            #expect(cell.icon.frame == CGRect(x: 16, y: 15, width: 30, height: 30))
            #expect(cell.titleLabel.frame.height >= 22)
            #expect(cell.subtitleLabel.frame.height >= 18)
            #expect(cell.titleLabel.font == WTypography.uiFont(.callout))
            #expect(cell.subtitleLabel.font == WTypography.uiFont(.supporting))
            #expect(cell.accessibilityTraits.contains(.button))
            #expect(!cell.hasAmbiguousLayout)
        }
    }
}
