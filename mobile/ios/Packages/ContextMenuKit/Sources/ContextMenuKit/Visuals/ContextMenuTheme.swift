import UIKit

enum ContextMenuVisuals {
    static func titleFont() -> UIFont {
        UIFont.systemFont(ofSize: 17.0, weight: .regular)
    }

    static func subtitleFont() -> UIFont {
        UIFont.systemFont(ofSize: 14.0, weight: .regular)
    }

    static func badgeFont() -> UIFont {
        UIFont.systemFont(ofSize: 13.0, weight: .regular)
    }

    static func primaryTextColor(for traits: UITraitCollection, role: ContextMenuRole, enabled: Bool) -> UIColor {
        let base: UIColor
        switch role {
        case .normal:
            base = traits.userInterfaceStyle == .dark ? .white : .black
        case .destructive:
            base = .systemRed
        }
        return enabled ? base : base.withAlphaComponent(0.4)
    }

    static func secondaryTextColor(for traits: UITraitCollection) -> UIColor {
        let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        return base.withAlphaComponent(0.56)
    }

    static func separatorColor(for traits: UITraitCollection) -> UIColor {
        let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        return base.withAlphaComponent(0.12)
    }

    static func badgeForegroundColor(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark ? .black : .white
    }

    static func badgeFillColor(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.9) : UIColor.black.withAlphaComponent(0.88)
    }

    static func backdropTintColor(for traits: UITraitCollection) -> UIColor {
        .black
    }

    static func highlightTintColor(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark ? .white : .black
    }

    static func highlightAlpha() -> CGFloat {
        0.1
    }

    static var supportsNativeGlass: Bool {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    @available(iOS 26.0, *)
    @MainActor
    static func nativePanelEffect(for traits: UITraitCollection, interactive: Bool) -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = interactive
        effect.tintColor = traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.025)
            : UIColor(white: 1.0, alpha: 0.1)
        return effect
    }

    @MainActor
    static func legacyPanelEffect() -> UIBlurEffect {
        UIBlurEffect(style: .systemChromeMaterial)
    }

    static func legacyPanelTintColor(for traits: UITraitCollection) -> UIColor {
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1.0, alpha: 0.08)
        } else {
            return UIColor(white: 1.0, alpha: 0.2)
        }
    }

    static func legacyPanelStrokeColor(for traits: UITraitCollection) -> UIColor {
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.14)
        } else {
            return UIColor.white.withAlphaComponent(0.34)
        }
    }

    @MainActor
    static func chevronImage() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        return UIImage(systemName: "chevron.right", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
    }

    static func makeBadgeImage(text: String, traits: UITraitCollection) -> UIImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont(),
            .foregroundColor: badgeForegroundColor(for: traits)
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let horizontalInset: CGFloat = 5.0
        let verticalInset: CGFloat = 1.0
        let badgeSize = CGSize(
            width: max(textSize.width + horizontalInset * 2.0, textSize.height + verticalInset * 2.0),
            height: textSize.height + verticalInset * 2.0
        )
        let renderer = UIGraphicsImageRenderer(size: badgeSize)
        return renderer.image { _ in
            badgeFillColor(for: traits).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: badgeSize), cornerRadius: badgeSize.height * 0.5).fill()
            let origin = CGPoint(
                x: floor((badgeSize.width - textSize.width) * 0.5),
                y: floor((badgeSize.height - textSize.height) * 0.5)
            )
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }.withRenderingMode(.alwaysOriginal)
    }
}
