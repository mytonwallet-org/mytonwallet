
import UIKit
import SwiftUI
import WalletContext

@MainActor public var screenSize: CGSize {
    UIApplication.shared.sceneKeyWindow?.bounds.size
        ?? UIApplication.shared.anySceneKeyWindow?.bounds.size
        ?? UIApplication.shared.connectedWindowScene?.coordinateSpace.bounds.size
        ?? .zero
}
@MainActor public var screenWidth: CGFloat { screenSize.width }
@MainActor public var screenHeight: CGFloat { screenSize.height }
@MainActor public var isCompactWidth: Bool { screenWidth < 600 }
@MainActor public var screenScale: CGFloat {
    let scale = UIApplication.shared.sceneKeyWindow?.screen.scale
        ?? UIApplication.shared.anySceneKeyWindow?.screen.scale
        ?? UITraitCollection.current.displayScale
    return max(scale, 1)
}
@MainActor public var screenMaximumFramesPerSecond: Int {
    UIApplication.shared.sceneKeyWindow?.screen.maximumFramesPerSecond
        ?? UIApplication.shared.anySceneKeyWindow?.screen.maximumFramesPerSecond
        ?? 60
}

public let designScreenWidth: CGFloat = 402

public let compactInsetSectionHorizontalPadding: CGFloat = 16
public let regularInsetSectionHorizontalPadding: CGFloat = 64
@MainActor public var insetSectionHorizontalPadding: CGFloat { isCompactWidth ? compactInsetSectionHorizontalPadding : regularInsetSectionHorizontalPadding }

public let homeCardMaxWidth: CGFloat = 450
public let homeCardMinSpacing: CGFloat = 8
public var homeCardMaxVisibleInactiveCard: CGFloat { regularInsetSectionHorizontalPadding - homeCardMinSpacing }
@MainActor public var homeCardWidth: CGFloat { min(screenWidth - 2 * compactInsetSectionHorizontalPadding, homeCardMaxWidth) }
