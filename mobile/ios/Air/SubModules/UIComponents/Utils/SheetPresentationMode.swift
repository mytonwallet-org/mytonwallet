import UIKit

public enum SheetPresentationMode: Equatable, Sendable {
    case floating
    case bottomAttached
    case fullScreen

    public init?(traits: UITraitCollection, prefersEdgeAttachedInCompactHeight: Bool) {
        guard traits.horizontalSizeClass != .unspecified,
              traits.verticalSizeClass != .unspecified else { return nil }

        if traits.verticalSizeClass == .compact {
            self = prefersEdgeAttachedInCompactHeight ? .bottomAttached : .fullScreen
        } else {
            self = traits.horizontalSizeClass == .regular ? .floating : .bottomAttached
        }
    }
}
