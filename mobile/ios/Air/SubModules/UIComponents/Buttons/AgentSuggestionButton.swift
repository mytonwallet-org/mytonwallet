import UIKit
import WalletContext

@MainActor
public final class AgentSuggestionButton: UIButton {
    public static let height: CGFloat = 40
    public static let spacing: CGFloat = 12
    private static let horizontalInset: CGFloat = 12
    private static let singleLineTitleHeight: CGFloat = 20
    private static let arrowWidth: CGFloat = 19
    private static let pressScaleInset: CGFloat = 15
    private static let minimumPressScale: CGFloat = 0.7
    private static let pressAnimationDuration: TimeInterval = 0.2
    private static let contentAppearanceKey = "contentAppearance"

    /// Rounded as the glass under it is, also once a wrapped title makes it taller than a capsule
    private let capsuleView = AgentSuggestionBackgroundView(cornerRadius: AgentSuggestionButton.height / 2, cornerCurve: .continuous)
    /// Interactive Liquid Glass under the pill, which takes the touch: the pill swells and stretches toward the finger
    /// and springs back as the system's glass does. Nil before iOS 26, where the pill shrinks under the finger.
    private let glassView: UIVisualEffectView?
    private let labelMask = UILabel()
    private let titleGradient = CAGradientLayer()
    private let arrowView = UIImageView()
    private var suggestionTitle = ""
    private var showsArrow = false
    private var hasIcon = false
    private static let arrowImage = UIImage(named: "AgentFollowupArrow", in: AirBundle, compatibleWith: nil)?
        .withRenderingMode(.alwaysOriginal)

    public var maximumNumberOfLines = 1 {
        didSet {
            guard maximumNumberOfLines != oldValue else { return }
            labelMask.numberOfLines = maximumNumberOfLines
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            guard abs(preferredMaxLayoutWidth - oldValue) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    /// Where the pill shows, in the button's coordinates, while set: a placeholder's pill on its way to the size of the
    /// suggestion it gets. The title and the arrow keep their places in the button.
    public var pillFrameOverride: CGRect? {
        didSet {
            guard pillFrameOverride != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// A view over the pill's fill and inside its border, which resizes with the pill, as a placeholder's passing light
    public var pillOverlayView: UIView? {
        didSet {
            guard pillOverlayView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let pillOverlayView {
                capsuleView.addSubview(pillOverlayView)
            }
            setNeedsLayout()
        }
    }

    /// The title's fade-in while it plays
    public var contentAppearance: CAAnimation? {
        titleGradient.animation(forKey: Self.contentAppearanceKey)
    }

    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updatePressedAppearance()
        }
    }

    public override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }

    public init() {
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effect = UIGlassEffect(style: .clear)
            effect.isInteractive = true
            let glassView = UIVisualEffectView(effect: effect)
            glassView.cornerConfiguration = .corners(radius: .init(floatLiteral: Self.height / 2))
            self.glassView = glassView
        } else {
            glassView = nil
        }
        super.init(frame: .zero)
        capsuleView.isUserInteractionEnabled = false
        if let glassView {
            // The glass is the touch target, so a tap on it stands in for the button's own tracking
            glassView.contentView.addSubview(capsuleView)
            glassView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleGlassTap)))
            addSubview(glassView)
        } else {
            addSubview(capsuleView)
        }
        labelMask.textColor = .black
        labelMask.lineBreakMode = .byTruncatingTail
        titleGradient.startPoint = CGPoint(x: 0, y: 0.5)
        titleGradient.mask = labelMask.layer
        titleGradient.actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull()]
        capsuleView.layer.addSublayer(titleGradient)
        arrowView.image = Self.arrowImage
        arrowView.contentMode = .scaleAspectFit
        arrowView.isAccessibilityElement = false
        capsuleView.addSubview(arrowView)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        accessibilityTraits = .button
        updateColors()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// With `icon`, a template image, the pill shows it before the title in the title's colour, in the arrow's place
    public func configure(title: String, showsArrow: Bool = false, icon: UIImage? = nil) {
        suggestionTitle = title
        self.showsArrow = showsArrow || icon != nil
        hasIcon = icon != nil
        arrowView.image = icon ?? Self.arrowImage
        labelMask.attributedText = NSAttributedString(string: title, attributes: Self.textAttributes)
        labelMask.layer.setNeedsDisplay()
        arrowView.isHidden = !self.showsArrow
        accessibilityLabel = title
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// The title's font, which a question sent from the suggestion grows from into its bubble's
    public static var titleFont: UIFont {
        WTypography.uiFont(.subheadlineEmphasized)
    }

    /// The title as it shows in its gradient, without the pill or a transition under way, and its frame in `view`
    public func makeTitlePicture(in view: UIView) -> (image: UIImage, frame: CGRect)? {
        layoutIfNeeded()
        guard !titleGradient.bounds.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: titleGradient.bounds, format: format).image { context in
            // The text's shape, filled with the gradient
            let cgContext = context.cgContext
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            labelMask.layer.render(in: cgContext)
            cgContext.setBlendMode(.sourceIn)
            titleGradient.render(in: cgContext)
            cgContext.endTransparencyLayer()
        }
        return (image, capsuleView.layer.convert(titleGradient.frame, to: view.layer))
    }

    public static func width(for title: String, showsArrow: Bool = false) -> CGFloat {
        let textWidth = (title as NSString).size(withAttributes: textAttributes).width
        let scale = UIScreen.main.scale
        return ceil((textWidth + horizontalInset * 2 + (showsArrow ? arrowWidth : 0)) * scale) / scale
    }

    public override var intrinsicContentSize: CGSize {
        let width = Self.width(for: suggestionTitle, showsArrow: showsArrow)
        guard maximumNumberOfLines != 1, preferredMaxLayoutWidth > 0, width > preferredMaxLayoutWidth else {
            return CGSize(width: width, height: Self.height)
        }
        // A wrapped title keeps the pill as wide as its longest line, as a single line does
        let chrome = Self.horizontalInset * 2 + (showsArrow ? Self.arrowWidth : 0)
        let textWidth = labelMask.textRect(
            forBounds: CGRect(x: 0, y: 0, width: max(0, preferredMaxLayoutWidth - chrome), height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: maximumNumberOfLines
        ).width
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let fittedWidth = min(preferredMaxLayoutWidth, ceil((textWidth + chrome) * scale) / scale + 1 / scale)
        let titleHeight = titleHeight(forWidth: fittedWidth)
        return CGSize(width: fittedWidth, height: Self.height - Self.singleLineTitleHeight + titleHeight)
    }

    private func titleHeight(forWidth width: CGFloat) -> CGFloat {
        guard maximumNumberOfLines != 1 else { return Self.singleLineTitleHeight }
        let titleWidth = max(0, width - Self.horizontalInset * 2 - (showsArrow ? Self.arrowWidth : 0))
        let textHeight = labelMask.textRect(
            forBounds: CGRect(x: 0, y: 0, width: titleWidth, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: maximumNumberOfLines
        ).height
        return max(Self.singleLineTitleHeight, ceil(textHeight))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let pillFrame = pillFrameOverride ?? bounds
        // By bounds and centre, which a press's transform leaves alone
        glassView?.bounds = CGRect(origin: .zero, size: pillFrame.size)
        glassView?.center = CGPoint(x: pillFrame.midX, y: pillFrame.midY)
        capsuleView.bounds = CGRect(origin: .zero, size: pillFrame.size)
        // Inside the glass, the pill fills it
        capsuleView.center = glassView == nil
            ? CGPoint(x: pillFrame.midX, y: pillFrame.midY)
            : CGPoint(x: pillFrame.width / 2, y: pillFrame.height / 2)
        pillOverlayView?.frame = capsuleView.bounds
        // The title and the arrow lie on the pill, placed in the button
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let arrowInset = showsArrow ? Self.arrowWidth : 0
        let titleHeight = titleHeight(forWidth: bounds.width)
        let titleFrame = CGRect(
            x: Self.horizontalInset + (isRTL ? 0 : arrowInset),
            y: (bounds.height - titleHeight) / 2,
            width: max(0, bounds.width - Self.horizontalInset * 2 - arrowInset),
            height: titleHeight
        )
        titleGradient.frame = titleFrame.offsetBy(dx: -pillFrame.minX, dy: -pillFrame.minY)
        labelMask.frame = titleGradient.bounds
        labelMask.layer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        arrowView.frame = CGRect(
            x: isRTL ? bounds.width - Self.horizontalInset - 15 : Self.horizontalInset,
            y: titleFrame.minY,
            width: 15,
            height: Self.singleLineTitleHeight
        ).offsetBy(dx: -pillFrame.minX, dy: -pillFrame.minY)
        arrowView.transform = isRTL && !hasIcon ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    /// Fades the title and the arrow in after `delay`, as a placeholder's pill gets its suggestion
    public func animateContentAppearance(delay: CFTimeInterval, duration: CFTimeInterval) {
        for layer in [titleGradient, arrowView.layer] {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.duration = duration
            animation.fillMode = .backwards
            layer.add(animation, forKey: Self.contentAppearanceKey)
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: WTypography.uiFont(.subheadlineEmphasized), .foregroundColor: UIColor.black]
    }

    private func updateColors() {
        AgentSuggestionAppearance.configureTitleGradient(titleGradient, for: traitCollection)
        arrowView.tintColor = AgentSuggestionAppearance.titleGradientColors(for: traitCollection).first.map(UIColor.init(cgColor:))
    }

    @objc private func handleGlassTap() {
        guard isEnabled else { return }
        sendActions(for: [.touchUpInside, .primaryActionTriggered])
    }

    /// The whole pill, its glass with what is on it, which a press shrinks together, as when a cell the pill fills
    /// passes its highlight on. A touch on the glass itself swells it as the system's glass does instead.
    private var pressedView: UIView {
        glassView ?? capsuleView
    }

    private func updatePressedAppearance() {
        let width = max(bounds.width, 1)
        let pressedScale = max(Self.minimumPressScale, (width - Self.pressScaleInset) / width)
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : Self.pressAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.pressedView.transform = self.isHighlighted
                ? CGAffineTransform(scaleX: pressedScale, y: pressedScale)
                : .identity
        }
    }

    public func resetPressedAppearance() {
        UIView.performWithoutAnimation {
            isHighlighted = false
            pressedView.layer.removeAllAnimations()
            pressedView.transform = .identity
        }
    }
}

@MainActor
public enum AgentSuggestionAppearance {
    public static func titleGradientColors(for traitCollection: UITraitCollection) -> [CGColor] {
        let colors: [UIColor]
        if traitCollection.userInterfaceStyle == .dark {
            colors = [
                UIColor(hex: "#6DADE6"),
                UIColor(hex: "#5EB6D4"),
                UIColor(hex: "#C48CEE"),
            ]
        } else {
            colors = [
                UIColor(hex: "#005DAF"),
                UIColor(hex: "#007BA5"),
                UIColor(hex: "#7D2EBA"),
            ]
        }
        return colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    }

    public static func backgroundBaseColor(for traitCollection: UITraitCollection) -> CGColor {
        let color = if traitCollection.userInterfaceStyle == .dark {
            UIColor.black.withAlphaComponent(0.16)
        } else {
            UIColor(hex: "#E9E9EA").withAlphaComponent(0.16)
        }
        return color.cgColor
    }

    public static func backgroundGradientColors(for traitCollection: UITraitCollection) -> [CGColor] {
        let colors: [UIColor]
        if traitCollection.userInterfaceStyle == .dark {
            colors = [
                UIColor(hex: "#0088FF").withAlphaComponent(0.096),
                UIColor(hex: "#00BEFF").withAlphaComponent(0.144),
                UIColor(hex: "#B656FF").withAlphaComponent(0.096),
            ]
        } else {
            colors = [
                UIColor(hex: "#0088FF").withAlphaComponent(0.048),
                UIColor(hex: "#00BEFF").withAlphaComponent(0.12),
                UIColor(hex: "#B656FF").withAlphaComponent(0.048),
            ]
        }
        return colors.map(\.cgColor)
    }

    public static func sheenGradientColors(for traitCollection: UITraitCollection) -> [CGColor] {
        let color: UIColor = traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#202020") : .white
        return [
            color.withAlphaComponent(0.6).cgColor,
            color.withAlphaComponent(0).cgColor,
        ]
    }

    public static let borderGradientColors = ["#00BEFF", "#00BEFF", "#0088FF", "#B656FF", "#00BEFF"]
        .map { UIColor(hex: $0).withAlphaComponent(0.5).cgColor }

    public static func configureTitleGradient(_ layer: CAGradientLayer, for traitCollection: UITraitCollection) {
        layer.colors = titleGradientColors(for: traitCollection)
        layer.locations = [0, 0.39547, 1]
        layer.endPoint = CGPoint(x: 1.28324, y: 0.5)
    }
}

@MainActor
public final class AgentSuggestionBackgroundView: UIView {
    private let fillLayer = CALayer()
    private let backgroundColorLayer = CALayer()
    private let backgroundGradientLayer = CAGradientLayer()
    private let backgroundSheenLayer = CAGradientLayer()
    private let borderGradientLayer = CAGradientLayer()
    private let borderContainerLayer = CALayer()
    /// Draws the border as its own ring, so it follows the fill's corners whatever their curve
    private let borderMaskLayer = CALayer()
    private static let borderWidth: CGFloat = 0.6
    private let fixedCornerRadius: CGFloat?

    public init(cornerRadius: CGFloat? = nil, cornerCurve: CALayerCornerCurve = .circular) {
        fixedCornerRadius = cornerRadius
        super.init(frame: .zero)

        backgroundColor = .clear
        fillLayer.cornerCurve = cornerCurve
        fillLayer.masksToBounds = true
        layer.addSublayer(fillLayer)

        backgroundGradientLayer.startPoint = .zero
        backgroundGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        backgroundGradientLayer.locations = [0, 0.47636, 1]
        backgroundSheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundSheenLayer.endPoint = CGPoint(x: 0.5, y: 1)
        fillLayer.addSublayer(backgroundColorLayer)
        fillLayer.addSublayer(backgroundGradientLayer)
        fillLayer.addSublayer(backgroundSheenLayer)

        borderGradientLayer.type = .conic
        borderGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        borderGradientLayer.locations = [0, 0.14425, 0.38464, 0.75, 1]
        borderGradientLayer.colors = AgentSuggestionAppearance.borderGradientColors
        borderMaskLayer.borderColor = UIColor.black.cgColor
        borderMaskLayer.borderWidth = Self.borderWidth
        borderMaskLayer.cornerCurve = cornerCurve
        borderContainerLayer.mask = borderMaskLayer
        borderContainerLayer.addSublayer(borderGradientLayer)
        layer.addSublayer(borderContainerLayer)

        let noAnimations: [String: CAAction] = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "colors": NSNull(),
            "borderWidth": NSNull(),
            "endPoint": NSNull(),
            "transform": NSNull(),
            "cornerRadius": NSNull(),
        ]
        fillLayer.actions = noAnimations
        borderContainerLayer.actions = noAnimations
        backgroundColorLayer.actions = noAnimations
        backgroundGradientLayer.actions = noAnimations
        backgroundSheenLayer.actions = noAnimations
        borderGradientLayer.actions = noAnimations
        borderMaskLayer.actions = noAnimations
        updateColors()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = fixedCornerRadius ?? bounds.height / 2
        fillLayer.frame = bounds
        fillLayer.cornerRadius = cornerRadius
        backgroundColorLayer.frame = bounds
        backgroundGradientLayer.frame = bounds
        backgroundSheenLayer.frame = bounds
        // The border lies just outside the fill
        borderContainerLayer.frame = bounds.insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth)
        borderMaskLayer.frame = borderContainerLayer.bounds
        borderMaskLayer.cornerRadius = cornerRadius + Self.borderWidth
        if traitCollection.userInterfaceStyle == .dark {
            backgroundGradientLayer.endPoint = CGPoint(x: 1, y: 1)
            borderGradientLayer.setAffineTransform(.identity)
            borderGradientLayer.frame = borderContainerLayer.bounds
            let angle = 33.4 * CGFloat.pi / 180
            borderGradientLayer.endPoint = CGPoint(
                x: 0.5 + cos(angle), y: 0.5 + sin(angle) * bounds.width / max(bounds.height, 1)
            )
        } else {
            // Figma's gradient transforms map normalized view coordinates into gradient space.
            let width = max(bounds.width, 1)
            let height = max(bounds.height, 1)
            let x: CGFloat = 0.93678725 / width
            let y: CGFloat = 0.06321277 / height
            let lengthSquared = x * x + y * y
            backgroundGradientLayer.endPoint = CGPoint(
                x: x / lengthSquared / width, y: y / lengthSquared / height
            )
            let inverse = CGAffineTransform(
                a: 1.20636392, b: -4.13311195, c: 0.26795182, d: 1.19033635, tx: 0, ty: 0
            ).inverted()
            let size = max(width, height)
            borderGradientLayer.bounds = CGRect(x: 0, y: 0, width: size * 12, height: size * 12)
            borderGradientLayer.position = CGPoint(x: borderContainerLayer.bounds.midX, y: borderContainerLayer.bounds.midY)
            borderGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            borderGradientLayer.setAffineTransform(CGAffineTransform(
                a: inverse.a * width / size, b: inverse.b * height / size,
                c: inverse.c * width / size, d: inverse.d * height / size, tx: 0, ty: 0
            ))
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    private func updateColors() {
        fillLayer.backgroundColor = UIColor.air.background.resolvedColor(with: traitCollection).cgColor
        backgroundColorLayer.backgroundColor = AgentSuggestionAppearance.backgroundBaseColor(
            for: traitCollection
        )
        backgroundGradientLayer.colors = AgentSuggestionAppearance.backgroundGradientColors(
            for: traitCollection
        )
        backgroundSheenLayer.colors = AgentSuggestionAppearance.sheenGradientColors(
            for: traitCollection
        )
        let isDark = traitCollection.userInterfaceStyle == .dark
        borderGradientLayer.locations = isDark
            ? [0, 0.14425, 0.38464, 0.75, 1]
            : [0, 0.13, 0.25, 0.375, 0.5, 0.63, 0.75, 0.88, 1]
        borderGradientLayer.colors = isDark ? AgentSuggestionAppearance.borderGradientColors
            : ["#0088FF", "#00BEFF", "#0088FF", "#00BEFF", "#0088FF", "#00BEFF", "#B656FF", "#00BEFF", "#0088FF"]
                .map { UIColor(hex: $0).withAlphaComponent(0.6).cgColor }
        setNeedsLayout()
    }
}
