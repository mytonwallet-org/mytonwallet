
import UIKit
import SwiftUI

@MainActor public var screenSize: CGSize { UIScreen.main.bounds.size }
@MainActor public var screenWidth: CGFloat { screenSize.width }
@MainActor public var screenHeight: CGFloat { screenSize.height }
@MainActor public var isCompactWidth: Bool { screenWidth < 600 }

public let designScreenWidth: CGFloat = 402

public let compactInsetSectionHorizontalPadding: CGFloat = 16
public let regularInsetSectionHorizontalPadding: CGFloat = 64
@MainActor public var insetSectionHorizontalPadding: CGFloat { isCompactWidth ? compactInsetSectionHorizontalPadding : regularInsetSectionHorizontalPadding }

public let homeCardMaxWidth: CGFloat = 450
public let homeCardMinSpacing: CGFloat = 8
public var homeCardMaxVisibleInactiveCard: CGFloat { regularInsetSectionHorizontalPadding - homeCardMinSpacing }
@MainActor public var homeCardWidth: CGFloat { min(screenWidth - 2 * compactInsetSectionHorizontalPadding, homeCardMaxWidth) }
