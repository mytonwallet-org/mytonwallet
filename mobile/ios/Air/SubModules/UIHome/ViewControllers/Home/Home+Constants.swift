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
    
    public static var screen: HomeCardLayoutMetrics {
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

var itemWidth: CGFloat { HomeCardLayoutMetrics.screen.itemWidth }
var itemHeight: CGFloat { HomeCardLayoutMetrics.screen.itemHeight }

let expansionOffset: CGFloat = 40
let collapseOffset: CGFloat = 10

let expansionInset: CGFloat = 30

var horizontalPadding: CGFloat { insetSectionHorizontalPadding }
let sectionSpacing: CGFloat = 16

var inset: CGFloat { HomeCardLayoutMetrics.screen.inset }
var spacing: CGFloat { HomeCardLayoutMetrics.screen.spacing }
var itemWidthWithSpacing: CGFloat { HomeCardLayoutMetrics.screen.itemWidthWithSpacing }
var visibleInactiveCard: CGFloat { HomeCardLayoutMetrics.screen.visibleInactiveCard }
