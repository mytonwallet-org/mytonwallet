import UIKit

public struct ContentOverlayAppearance: Equatable {
    public var usesClearGlass: Bool
    public var foregroundColor: UIColor?
    public var userInterfaceStyle: UIUserInterfaceStyle

    public static var standard: ContentOverlayAppearance { .init() }

    public init(usesClearGlass: Bool = false, foregroundColor: UIColor? = nil,
                userInterfaceStyle: UIUserInterfaceStyle = .unspecified) {
        self.usesClearGlass = usesClearGlass
        self.foregroundColor = foregroundColor
        self.userInterfaceStyle = userInterfaceStyle
    }
}

/// Appearance of container-owned controls over the visible screen's content.
@MainActor
public protocol ContentOverlayAppearanceProviding: AnyObject {
    var onContentOverlayAppearanceChange: ((_ animated: Bool) -> Void)? { get set }
    func contentOverlayAppearance(in rectInWindow: CGRect) -> ContentOverlayAppearance
}
