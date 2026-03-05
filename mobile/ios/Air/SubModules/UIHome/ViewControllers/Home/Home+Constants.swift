import UIComponents
import UIKit
import WalletContext

public struct HomeCardLayoutMetrics: Equatable {
    public let containerWidth: CGFloat
    public let itemWidth: CGFloat
    public let itemHeight: CGFloat
    public let inset: CGFloat
    public let spacing: CGFloat
    
    public var itemWidthWithSpacing: CGFloat { spacing + itemWidth }
    public var visibleInactiveCard: CGFloat { (containerWidth - itemWidth - 2 * spacing) / 2 }
    
    @MainActor public static var screen: HomeCardLayoutMetrics {
        forContainerWidth(screenWidth)
    }
    
    public static func forContainerWidth(_ containerWidth: CGFloat) -> HomeCardLayoutMetrics {
        let width = max(containerWidth, 1)
        let itemWidth = min(max(width - 2 * compactInsetSectionHorizontalPadding, 0), homeCardMaxWidth)
        let inset = max(0, (width - itemWidth) / 2)
        let spacing = max(homeCardMinSpacing, (width - itemWidth) / 2 - homeCardMaxVisibleInactiveCard)
        return HomeCardLayoutMetrics(
            containerWidth: width,
            itemWidth: itemWidth,
            itemHeight: round(itemWidth * CARD_RATIO),
            inset: inset,
            spacing: spacing
        )
    }
}

@MainActor var itemWidth: CGFloat { HomeCardLayoutMetrics.screen.itemWidth }
@MainActor var itemHeight: CGFloat { HomeCardLayoutMetrics.screen.itemHeight }

let expansionOffset: CGFloat = 40
let collapseOffset: CGFloat = 10

let expansionInset: CGFloat = 30

@MainActor var horizontalPadding: CGFloat { insetSectionHorizontalPadding }
let sectionSpacing: CGFloat = 16

@MainActor var inset: CGFloat { HomeCardLayoutMetrics.screen.inset }
@MainActor var spacing: CGFloat { HomeCardLayoutMetrics.screen.spacing }
@MainActor var itemWidthWithSpacing: CGFloat { HomeCardLayoutMetrics.screen.itemWidthWithSpacing }
@MainActor var visibleInactiveCard: CGFloat { HomeCardLayoutMetrics.screen.visibleInactiveCard }
