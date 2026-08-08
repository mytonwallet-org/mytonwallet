import UIKit

extension UIUserInterfaceLayoutDirection {
    var contextMenuSemanticContentAttribute: UISemanticContentAttribute {
        switch self {
        case .rightToLeft:
            return .forceRightToLeft
        case .leftToRight:
            return .forceLeftToRight
        @unknown default:
            return .forceLeftToRight
        }
    }

    var contextMenuIsRightToLeft: Bool {
        self == .rightToLeft
    }
}
