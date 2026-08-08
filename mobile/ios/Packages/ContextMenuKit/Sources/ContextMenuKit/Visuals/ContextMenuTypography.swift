import UIKit

@MainActor
public enum ContextMenuTypography {
    public struct Fonts {
        public let title: UIFont
        public let subtitle: UIFont
        public let badge: UIFont
        public let symbol: UIFont

        public init(title: UIFont, subtitle: UIFont, badge: UIFont, symbol: UIFont) {
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.symbol = symbol
        }
    }

    private static var fonts = Fonts(
        title: .systemFont(ofSize: 17, weight: .regular),
        subtitle: .systemFont(ofSize: 14, weight: .regular),
        badge: .systemFont(ofSize: 13, weight: .regular),
        symbol: .systemFont(ofSize: 13, weight: .semibold)
    )

    public static func configure(fonts: Fonts) {
        self.fonts = fonts
    }

    static var titleFont: UIFont { fonts.title }
    static var subtitleFont: UIFont { fonts.subtitle }
    static var badgeFont: UIFont { fonts.badge }
    static var symbolFont: UIFont { fonts.symbol }
}
