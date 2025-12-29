import UIComponents
import UIKit
import WalletContext

let itemWidth: CGFloat = homeCardWidth
let itemHeight: CGFloat = round(itemWidth * CARD_RATIO)

let expansionOffset: CGFloat = 40
let collapseOffset: CGFloat = 10

let expansionInset: CGFloat = 30

var horizontalPadding: CGFloat { insetSectionHorizontalPadding }
let sectionSpacing: CGFloat = 16

var inset: CGFloat { (screenWidth - homeCardWidth) / 2 }
var spacing: CGFloat { max(homeCardMinSpacing, (screenWidth - homeCardWidth) / 2 - homeCardMaxVisibleInactiveCard) }
var itemWidthWithSpacing: CGFloat { spacing + itemWidth }
var visibleInactiveCard: CGFloat { (screenWidth - itemWidth - 2 * spacing) / 2  }
