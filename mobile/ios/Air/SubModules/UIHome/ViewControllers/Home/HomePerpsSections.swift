import UIActivityList
import UIAssets
import UIKit

/// Optional home sections, enabled only when an adapter supplies content for the displayed wallet.
@MainActor
final class HomePerpsSections {
    let positionsID = "home-perps-positions"
    let exploreID = "home-explore"
    var data: PerpsPositionsDisplayData? { didSet { positionsDescriptor.data = data } }
    var destinations: [HomeExploreDestination] {
        get { exploreDescriptor.destinations }
        set { exploreDescriptor.destinations = newValue }
    }
    var onPositionAction: ((PerpsHomeAction) -> Void)?
    var onExplore: ((HomeExploreDestination) -> Void)?

    lazy var positionsDescriptor: PerpsPositionsSectionDataProvider = {
        let provider = PerpsPositionsSectionDataProvider(id: positionsID)
        provider.onAction = { [weak self] in self?.onPositionAction?($0) }
        return provider
    }()
    lazy var exploreDescriptor: HomeExploreSectionDataProvider = {
        let provider = HomeExploreSectionDataProvider(id: exploreID)
        provider.onSelect = { [weak self] in self?.onExplore?($0) }
        return provider
    }()

    init() {
        positionsDescriptor.prepareForUse()
        exploreDescriptor.prepareForUse()
    }
}
