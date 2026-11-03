import UIKit
import UIComponents

/// Telegram's chat list loading placeholder: rows of an avatar circle and short rounded bars where the title, the time
/// and two lines of preview go, with the list's separators between them, swept from top to bottom by a soft highlight
final class AgentThreadListSkeletonView: AgentSkeletonView {
    /// Telegram's bars: 8 pt high, 60 pt for the title and each line's end, 120 pt for the start of the first line, 30 pt
    /// for the time
    private static let barHeight: CGFloat = 8
    private static let shortBarWidth: CGFloat = 60
    private static let longBarWidth: CGFloat = 120
    private static let timeBarWidth: CGFloat = 30
    private static let barSpacing: CGFloat = 10

    /// Telegram's highlight: a 250 pt band that crosses the list from top to bottom in 1.3 s, slowing down as it goes
    private static let shimmerDuration: CFTimeInterval = 1.3
    private static let bandHeight: CGFloat = 250
    /// Telegram's chat list shimmer fades out over 0.3 s as the list fades in
    static let fadeDuration: TimeInterval = 0.3

    private let shapesLayer = CAShapeLayer()
    private let separatorsLayer = CAShapeLayer()
    private let shimmerLayer = CALayer()
    private let bandLayer = CAGradientLayer()
    private let shimmerMask = CAShapeLayer()

    init() {
        super.init(fadeDuration: Self.fadeDuration)
        for layer in [shapesLayer, separatorsLayer, shimmerMask, shimmerLayer, bandLayer] as [CALayer] {
            layer.actions = Self.noImplicitGeometry
        }
        bandLayer.startPoint = CGPoint(x: 0.5, y: 0)
        bandLayer.endPoint = CGPoint(x: 0.5, y: 1)
        bandLayer.locations = [0, 0.5, 1]
        shimmerLayer.mask = shimmerMask
        shimmerLayer.addSublayer(bandLayer)
        layer.addSublayer(shapesLayer)
        layer.addSublayer(shimmerLayer)
        layer.addSublayer(separatorsLayer)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shapes = UIBezierPath()
        let separators = UIBezierPath()
        let rowHeight = AgentThreadRowMetrics.height
        var rowTop: CGFloat = 0
        while rowTop < bounds.height {
            appendRow(at: rowTop, shapes: shapes, separators: separators)
            rowTop += rowHeight
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [shapesLayer, separatorsLayer, shimmerMask, shimmerLayer] as [CALayer] {
            layer.frame = bounds
        }
        shapesLayer.path = shapes.cgPath
        shimmerMask.path = shapes.cgPath
        separatorsLayer.path = separators.cgPath
        bandLayer.frame = CGRect(x: 0, y: -Self.bandHeight, width: bounds.width, height: Self.bandHeight)
        CATransaction.commit()
        startShimmer(isRestarting: true)
    }

    /// A row laid out like `AgentThreadCell`: the bars sit on the middle of the lines they stand for
    private func appendRow(at top: CGFloat, shapes: UIBezierPath, separators: UIBezierPath) {
        let metrics = AgentThreadRowMetrics.self
        let width = bounds.width
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ rect: CGRect) -> CGRect {
            isRightToLeft ? CGRect(x: width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        func appendBar(x: CGFloat, lineTop: CGFloat, lineHeight: CGFloat, width: CGFloat) {
            let y = (top + lineTop + (lineHeight - Self.barHeight) / 2).rounded()
            let rect = place(CGRect(x: x, y: y, width: width, height: Self.barHeight))
            shapes.append(UIBezierPath(roundedRect: rect, cornerRadius: Self.barHeight / 2))
        }
        let avatar = CGRect(x: metrics.horizontalInset, y: top + metrics.avatarTop, width: metrics.avatarSize, height: metrics.avatarSize)
        shapes.append(UIBezierPath(ovalIn: place(avatar)))
        let leading = metrics.textLeading
        appendBar(x: leading, lineTop: metrics.titleTop, lineHeight: metrics.titleLineHeight, width: Self.shortBarWidth)
        appendBar(
            x: width - metrics.horizontalInset - Self.timeBarWidth,
            lineTop: metrics.titleTop,
            lineHeight: metrics.titleLineHeight,
            width: Self.timeBarWidth
        )
        appendBar(x: leading, lineTop: metrics.previewTop, lineHeight: metrics.previewLineHeight, width: Self.longBarWidth)
        appendBar(
            x: leading + Self.longBarWidth + Self.barSpacing,
            lineTop: metrics.previewTop,
            lineHeight: metrics.previewLineHeight,
            width: Self.shortBarWidth
        )
        appendBar(
            x: leading,
            lineTop: metrics.previewTop + metrics.previewLineHeight,
            lineHeight: metrics.previewLineHeight,
            width: Self.shortBarWidth
        )
        let thickness = AgentThreadRowMetrics.getSeparatorThickness(displayScale: traitCollection.displayScale)
        let separator = CGRect(
            x: leading,
            y: top + metrics.height - thickness,
            width: max(0, width - leading - metrics.horizontalInset),
            height: thickness
        )
        separators.append(UIBezierPath(rect: place(separator)))
    }

    override func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapesLayer.fillColor = UIColor.air.agentBubbleFill.resolvedColor(with: traitCollection).cgColor
        separatorsLayer.fillColor = AgentThreadRowMetrics.separatorColor.resolvedColor(with: traitCollection).cgColor
        let peak = UIColor.white.withAlphaComponent(isDark ? 0.14 : 0.7)
        bandLayer.colors = [peak.withAlphaComponent(0).cgColor, peak.cgColor, peak.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }

    override func startShimmer(isRestarting: Bool = false) {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled, bounds.height > 0 else { return }
        startSweep(
            of: bandLayer,
            along: "position.y",
            travel: bounds.height + Self.bandHeight,
            duration: Self.shimmerDuration,
            isRestarting: isRestarting
        )
    }

    override func stopShimmer() {
        bandLayer.removeAnimation(forKey: Self.shimmerKey)
    }
}
