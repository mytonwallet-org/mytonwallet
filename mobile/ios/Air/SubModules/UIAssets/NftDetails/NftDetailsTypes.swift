import Foundation
import UIKit

enum NftDetailsHeroLayout {
    static func frame(in size: CGSize, safeAreaInsets: UIEdgeInsets, userInterfaceIdiom: UIUserInterfaceIdiom,
                      navigationBarHeight: CGFloat = 0) -> CGRect {
        let maximumSide: CGFloat = 560
        if userInterfaceIdiom == .phone, size.width <= maximumSide, size.height > size.width {
            return CGRect(x: 0, y: 0, width: size.width, height: size.width)
        }
        // The 44pt navigation button is centered within the navigation bar.
        let navigationButtonInset = navigationBarHeight > 0 ? (navigationBarHeight + 44) / 2 : 0
        let top = max(16, safeAreaInsets.top - navigationButtonInset)
        // Leave space for the title and actions even in a short landscape window.
        let availableHeight = max(1, size.height - top - safeAreaInsets.bottom - 160)
        let side = min(size.width, maximumSide, availableHeight)
        return CGRect(x: (size.width - side) / 2, y: side < size.width ? top : 0,
                      width: side, height: side)
    }

    static func scrolledFrame(_ frame: CGRect, offsetY: CGFloat) -> CGRect {
        let overscroll = -min(0, offsetY)
        return CGRect(x: frame.minX - overscroll / 2, y: frame.minY - max(0, offsetY) / 2,
                      width: frame.width + overscroll, height: frame.height + overscroll)
    }
}

enum NftDetailsPageTransitionState<Page: Equatable>: Equatable, CustomStringConvertible {
    case staticPage(Page)
    
    /// Progress is  0..1 (both ends exclusive)
    case transition(leftPage: Page, rightPage: Page, progress: CGFloat)
    
    /// Normalize the data. We either have a static left side at progress 0 or have a transition left => right at 0..1 (both ends exclusive)
    init(leftPage: Page, rightPage: Page?, progress: CGFloat) {
        
        var effectiveProgress = progress
        var effectiveRight = rightPage
        var effectiveLeft = leftPage
        
        if effectiveProgress < 0 {
            effectiveProgress = 0
        }
        if effectiveProgress == 0 {
            effectiveRight = nil
        }
        if effectiveProgress > 0 {
            if let rightPage {
                if effectiveProgress >= 1 {
                    effectiveLeft = rightPage
                    effectiveRight = nil
                    effectiveProgress = 0
                }
            } else {
                effectiveProgress = 0
            }
        }
        
        assert(effectiveProgress >= 0 && effectiveProgress < 1)
        assert(effectiveRight == nil || effectiveProgress > 0 )
        
        if let effectiveRight {
            assert(effectiveProgress > 0 && effectiveProgress < 1)
            self = .transition(leftPage: effectiveLeft, rightPage: effectiveRight, progress: effectiveProgress)
        } else {
            assert(effectiveProgress == 0)
            self = .staticPage(effectiveLeft)
        }
    }
    
    var description: String {
        switch self {
        case let .staticPage(leftPage): return "STATIC \(leftPage)"
        case let .transition(leftPage, rightPage, progress): return "TRANSITION: \(leftPage) => \(rightPage) at \(progress)"
        }
    }
    
    var isStatic: Bool {
        if case .staticPage = self {
            return true
        }
        return false
    }
    
    var isTransitioning: Bool {
        if case .transition = self {
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let nftDetailsStopLottieAnimations = Notification.Name("nftDetailsStopLottieAnimations")
}


/// CISwipeTransition with a feather width of three screen widths is a linear
/// alpha ramp. Share its geometry with Core Animation so live video can use the
/// identical wipe without readback, snapshots, or per-frame image uploads.
enum NftDetailsPageWipe {
    static let widthRatio: CGFloat = 3

    static func configure(_ mask: CAGradientLayer, progress: CGFloat, showingLeft: Bool, isRTL: Bool) {
        let start = 1 - (1 + widthRatio) * progress
        let end = start + widthRatio
        mask.startPoint = CGPoint(x: isRTL ? 1 - start : start, y: 0.5)
        mask.endPoint = CGPoint(x: isRTL ? 1 - end : end, y: 0.5)
        mask.colors = showingLeft ? [UIColor.white.cgColor, UIColor.clear.cgColor]
            : [UIColor.clear.cgColor, UIColor.white.cgColor]
        mask.locations = [0, 1]
    }
}
