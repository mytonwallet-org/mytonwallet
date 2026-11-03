import Perception
import SwiftUI
import UIActivityList
import UIAssets
import UIKit

/// Optional home sections, enabled only when an adapter supplies content for the displayed wallet.
@MainActor @Perceptible
final class HomePerpsSections {
    let positionsID = "home-perps-positions"
    let exploreID = "home-explore"
    var data: PerpsPositionsDisplayData? { didSet { positionsDescriptor.data = data } }
    var destinations: [HomeExploreDestination] = []
    var onPositionAction: ((PerpsHomeAction) -> Void)?
    var onExplore: ((HomeExploreDestination) -> Void)?

    @PerceptionIgnored private lazy var exploreRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, _ in
        cell.contentConfiguration = UIHostingConfiguration {
            WithPerceptionTracking {
                if let self {
                    HomeExploreSectionView(destinations: self.destinations) { self.onExplore?($0) }
                }
            }
        }.background { Color.clear }.margins(.all, 0)
    }

    @PerceptionIgnored lazy var positionsDescriptor: PerpsPositionsSectionDataProvider = {
        let provider = PerpsPositionsSectionDataProvider(id: positionsID)
        provider.onAction = { [weak self] in self?.onPositionAction?($0) }
        return provider
    }()
    @PerceptionIgnored lazy var exploreDescriptor = ActivityListViewController.CustomSectionDescriptor(
        id: exploreID, usesInsetGroupedMargins: true, topSpacing: 16, bottomSpacing: 0
    ) { [unowned self] collection, index in
        collection.dequeueConfiguredReusableCell(using: exploreRegistration, for: index, item: exploreID)
    }

    init() { positionsDescriptor.prepareForUse(); _ = exploreRegistration }
}
