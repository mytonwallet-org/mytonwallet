import Foundation

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
}
