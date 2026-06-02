import UIComponents
import UIKit
import WalletContext

public struct HomeCardLayoutMetrics: Equatable {
    public let itemWidth: CGFloat
    public let itemHeight: CGFloat
    public let inset: CGFloat
    public let spacing: CGFloat
    
    public var itemWidthWithSpacing: CGFloat { spacing + itemWidth }
    
    @MainActor public static var screen: HomeCardLayoutMetrics {
        forContainerWidth(screenWidth)
    }
    
    public static func forContainerWidth(_ containerWidth: CGFloat) -> HomeCardLayoutMetrics {
        let width = max(containerWidth, 1)
        let itemWidth = min(max(width - 2 * compactInsetSectionHorizontalPadding, 0), homeCardMaxWidth)
        let inset = max(0, (width - itemWidth) / 2)
        let spacing = max(homeCardMinSpacing, (width - itemWidth) / 2 - homeCardMaxVisibleInactiveCard)
        return HomeCardLayoutMetrics(
            itemWidth: itemWidth,
            itemHeight: round(itemWidth * CARD_RATIO),
            inset: inset,
            spacing: spacing
        )
    }
}

let expansionOffset: CGFloat = 40
let collapseOffset: CGFloat = 10

let expansionInset: CGFloat = 30

let sectionSpacing: CGFloat = 16
