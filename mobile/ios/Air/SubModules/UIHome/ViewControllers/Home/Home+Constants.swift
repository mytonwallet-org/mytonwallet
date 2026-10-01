import UIComponents
import UIKit
import WalletContext

public struct HomeCardLayoutMetrics: Equatable {
    public let itemWidth: CGFloat
    public let itemHeight: CGFloat
    public let leadingInset: CGFloat
    public let trailingInset: CGFloat
    public let spacing: CGFloat
    
    public var itemWidthWithSpacing: CGFloat { spacing + itemWidth }
    
    @MainActor public static var screen: HomeCardLayoutMetrics {
        forContainerWidth(screenWidth)
    }
    
    public static func forContainerWidth(
        _ containerWidth: CGFloat,
        contentMargins: NSDirectionalEdgeInsets = .init(top: 0, leading: compactInsetSectionHorizontalPadding, bottom: 0, trailing: compactInsetSectionHorizontalPadding)
    ) -> HomeCardLayoutMetrics {
        let width = max(containerWidth, 1)
        let availableWidth = max(0, width - contentMargins.leading - contentMargins.trailing)
        let itemWidth = min(availableWidth, homeCardMaxWidth)
        let centeringInset = (availableWidth - itemWidth) / 2
        let leadingInset = contentMargins.leading + centeringInset
        let trailingInset = contentMargins.trailing + centeringInset
        let spacing = max(homeCardMinSpacing, min(leadingInset, trailingInset) - homeCardMaxVisibleInactiveCard)
        return HomeCardLayoutMetrics(
            itemWidth: itemWidth,
            itemHeight: round(itemWidth * CARD_RATIO),
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            spacing: spacing
        )
    }
}

let expansionOffset: CGFloat = 40
let collapseOffset: CGFloat = 10

let expansionInset: CGFloat = 30

let sectionSpacing: CGFloat = 16

extension HomeRootNavigationStyle {
    var usesTopTabs: Bool {
        self != .standard
    }

    var usesNavigationBarTopTabs: Bool {
        self == .topTabsNavigationBar
    }

    var collapsedHeaderSnapOffset: CGFloat {
        usesNavigationBarTopTabs ? collapseOffset : 110
    }

    var collapsedHeaderSnapRange: CGFloat {
        usesNavigationBarTopTabs ? 166 : 120
    }

    var collapsedHeaderSnapThreshold: CGFloat {
        usesNavigationBarTopTabs ? collapseOffset : 52
    }
}
