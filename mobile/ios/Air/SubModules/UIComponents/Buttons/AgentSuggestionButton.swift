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

    private let capsuleView = AgentSuggestionBackgroundView(cornerRadius: AgentSuggestionButton.height / 2)
    private let labelMask = UILabel()
    private let titleGradient = CAGradientLayer()
    private let arrowView = UIImageView()
    private var suggestionTitle = ""
    private var showsArrow = false

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
        super.init(frame: .zero)
        capsuleView.isUserInteractionEnabled = false
        addSubview(capsuleView)
        labelMask.textColor = .black
        labelMask.lineBreakMode = .byTruncatingTail
        titleGradient.startPoint = CGPoint(x: 0, y: 0.5)
        titleGradient.mask = labelMask.layer
        titleGradient.actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull()]
        capsuleView.layer.addSublayer(titleGradient)
        arrowView.image = UIImage(named: "AgentFollowupArrow", in: AirBundle, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
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

    public func configure(title: String, showsArrow: Bool = false) {
        suggestionTitle = title
        self.showsArrow = showsArrow
        labelMask.attributedText = NSAttributedString(string: title, attributes: Self.textAttributes)
        labelMask.layer.setNeedsDisplay()
        arrowView.isHidden = !showsArrow
        accessibilityLabel = title
        invalidateIntrinsicContentSize()
        setNeedsLayout()
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
        let titleHeight = titleHeight(forWidth: preferredMaxLayoutWidth)
        return CGSize(width: preferredMaxLayoutWidth, height: Self.height - Self.singleLineTitleHeight + titleHeight)
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
        capsuleView.bounds = CGRect(origin: .zero, size: bounds.size)
        capsuleView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let arrowInset = showsArrow ? Self.arrowWidth : 0
        let titleHeight = titleHeight(forWidth: bounds.width)
        titleGradient.frame = CGRect(
            x: Self.horizontalInset + (isRTL ? 0 : arrowInset),
            y: (bounds.height - titleHeight) / 2,
            width: max(0, bounds.width - Self.horizontalInset * 2 - arrowInset),
            height: titleHeight
        )
        labelMask.frame = titleGradient.bounds
        labelMask.layer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        arrowView.frame = CGRect(
            x: isRTL ? bounds.width - Self.horizontalInset - 15 : Self.horizontalInset,
            y: titleGradient.frame.minY,
            width: 15,
            height: Self.singleLineTitleHeight
        )
        arrowView.transform = isRTL ? CGAffineTransform(scaleX: -1, y: 1) : .identity
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
    }

    private func updatePressedAppearance() {
        let width = max(bounds.width, 1)
        let pressedScale = max(Self.minimumPressScale, (width - Self.pressScaleInset) / width)
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : Self.pressAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.capsuleView.transform = self.isHighlighted
                ? CGAffineTransform(scaleX: pressedScale, y: pressedScale)
                : .identity
        }
    }

    public func resetPressedAppearance() {
        UIView.performWithoutAnimation {
            isHighlighted = false
            capsuleView.layer.removeAllAnimations()
            capsuleView.transform = .identity
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
    private let borderMaskLayer = CAShapeLayer()
    private let fixedCornerRadius: CGFloat?

    public init(cornerRadius: CGFloat? = nil) {
        fixedCornerRadius = cornerRadius
        super.init(frame: .zero)

        backgroundColor = .clear
        fillLayer.cornerCurve = .circular
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
        borderMaskLayer.fillColor = UIColor.clear.cgColor
        borderMaskLayer.strokeColor = UIColor.black.cgColor
        borderMaskLayer.lineWidth = 0.6
        borderContainerLayer.mask = borderMaskLayer
        borderContainerLayer.addSublayer(borderGradientLayer)
        layer.addSublayer(borderContainerLayer)

        let noAnimations: [String: CAAction] = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "colors": NSNull(),
            "path": NSNull(),
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
        borderContainerLayer.frame = bounds.insetBy(dx: -0.6, dy: -0.6)
        borderMaskLayer.frame = borderContainerLayer.bounds
        borderMaskLayer.path = UIBezierPath(
            roundedRect: borderContainerLayer.bounds.insetBy(dx: 0.3, dy: 0.3),
            cornerRadius: cornerRadius + 0.3
        ).cgPath
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
