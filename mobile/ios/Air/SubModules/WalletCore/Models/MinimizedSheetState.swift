
import UIKit

public enum MinimizedSheetState: Equatable, Hashable, Codable, Sendable {
    case closed
    case closedExternally
    case minimized
    case expanded
    case replacedWithPlaceholder
}

extension UISheetPresentationController.Detent.Identifier {
    public static let minimized: UISheetPresentationController.Detent.Identifier = .init("min")
}
