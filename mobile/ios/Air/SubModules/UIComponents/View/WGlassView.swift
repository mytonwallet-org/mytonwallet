import UIKit

/// A piece of Liquid Glass: interactive, so it stretches under the finger, and placed directly in a glass container's
/// content view, so it merges with the container's other glass when they meet. Without Liquid Glass it is a blur.
public final class WGlassView: UIVisualEffectView {
    /// Nil keeps the glass a capsule at any size
    private let cornerRadius: CGFloat?
    private var tint: UIColor?
    /// Glass ignores its alpha, so it appears and disappears by gaining and losing its effect, which animates inside
    /// an animation block
    public private(set) var isMaterialized = true

    public init(cornerRadius: CGFloat?) {
        self.cornerRadius = cornerRadius
        super.init(effect: nil)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        applyEffect()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Tints the glass, as for a prominent control; nil returns it to clear glass
    public func setTint(_ color: UIColor?) {
        guard color != tint else { return }
        tint = color
        applyEffect()
    }

    /// Shows or hides the glass and its content; call it inside an animation block to animate
    public func setMaterialized(_ isMaterialized: Bool) {
        guard isMaterialized != self.isMaterialized else { return }
        self.isMaterialized = isMaterialized
        contentView.alpha = isMaterialized ? 1 : 0
        if isMaterialized {
            applyEffect()
        } else {
            effect = nil
        }
    }

    public func applyEffect() {
        guard isMaterialized else { return }
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = tint
            self.effect = effect
            cornerConfiguration = cornerRadius.map { .corners(radius: .init(floatLiteral: $0)) } ?? .capsule()
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
            contentView.backgroundColor = tint ?? .clear
            layer.cornerRadius = cornerRadius ?? bounds.height / 2
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if !IOS_26_MODE_ENABLED, cornerRadius == nil {
            layer.cornerRadius = bounds.height / 2
        }
    }
}

/// The one size of the round glass buttons over content, the Agent's header buttons and the media viewer's alike, as
/// Telegram's bars draw them: a 44 pt circle, or a 44 pt capsule of several. A bar's back and "…" glyphs are 17 pt
/// semibold symbols, which a plain button draws at the large scale, as large as the system back button's chevron.
public enum WGlassButtonMetrics {
    public static let size: CGFloat = 44
    public static let symbolPointSize: CGFloat = 17
    public static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
}
