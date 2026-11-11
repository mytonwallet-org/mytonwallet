import Testing
import UIKit
import UIComponents
import WalletResources
@testable import UIAssets

@Suite @MainActor
struct HomeExploreLayoutTests {
    @Test func exploreSectionListsItsDestinationsAndSelectsOnlyThose() {
        let section = HomeExploreSectionDataProvider(id: "explore")
        var selected: [HomeExploreDestination] = []
        section.onSelect = { selected.append($0) }
        section.destinations = [.market, .agent, .futures]
        #expect(section.itemIdentifiers == ["market", "agent", "futures"])
        section.didSelect(itemIdentifier: "agent")
        section.didSelect(itemIdentifier: "apps")
        section.destinations = []
        #expect(section.itemIdentifiers.isEmpty)
        #expect(!section.shouldSelect(itemIdentifier: "futures"))
        section.didSelect(itemIdentifier: "futures")
        #expect(selected == [.agent])
    }

    @Test func repeatedDestinationsAppearOnce() {
        let section = HomeExploreSectionDataProvider(id: "explore")
        section.destinations = [.market, .apps, .market, .apps]
        #expect(section.itemIdentifiers == ["market", "apps"])
    }

    @Test func exploreDestinationsFollowDefaultTabOrder() {
        #expect(HomeExploreDestination.allCases == [.market, .futures, .agent, .apps])
    }

    @Test func exploreDescriptionsWrapWithEqualVerticalMargins() {
        _ = WalletResourcesBundle.bundle.load()
        let cell = HomeExploreCell(frame: CGRect(x: 0, y: 0, width: 288, height: 60))
        cell.configure(.market)
        cell.subtitleLabel.text = "Торгуйте криптовалютой и реальными активами"
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = cell.bounds.size
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        cell.frame.size = fitted.size
        cell.layoutIfNeeded()

        #expect(fitted.size.height > 60)
        #expect(cell.subtitleLabel.numberOfLines == 2)
        #expect(cell.subtitleLabel.frame.height >= cell.subtitleLabel.font.lineHeight * 2)
        let titleFrame = cell.titleLabel.convert(cell.titleLabel.bounds, to: cell.contentView)
        let subtitleFrame = cell.subtitleLabel.convert(cell.subtitleLabel.bounds, to: cell.contentView)
        #expect(abs(titleFrame.minY - 10) < 1)
        #expect(abs(cell.contentView.bounds.height - subtitleFrame.maxY - 10) < 1)
        #expect(cell.icon.center.y == cell.contentView.bounds.midY)

        attributes.size.width = 600
        let wide = cell.preferredLayoutAttributesFitting(attributes)
        #expect(wide.size.height == 60)
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
