import UIKit
import WalletContext

/// A label painted with a blue, cyan and purple gradient that slowly sweeps along the text, for a status that shows
/// work in progress. A changed text blurs in over the old one, and a glint then crosses it.
public final class AnimatedGradientLabel: UILabel {
    /// The design's gradient spans one text width (blue, cyan at 39.5%, purple); the tile covers two widths and runs
    /// back to blue, so the sweep repeats seamlessly
    private static let colors = ["#0088FF", "#00BEFF", "#B656FF", "#00BEFF", "#0088FF"].map { UIColor(hex: $0).cgColor }
    private static let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 0.1977, 0.5, 0.8023, 1]
    )
    public static let textFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    /// A glint of whitish light passes across the text once each time it changes, as light runs over metal: it starts
    /// `glintDelay` after the change, as the new text comes into focus, and takes `glintDuration`
    static let glintDelay: CFTimeInterval = 0.3
    static let glintDuration: CFTimeInterval = 0.75
    /// Half the glint's width across, in points
    static let glintHalfWidth: CGFloat = 16
    /// The glint's opacity at its middle: a soft light rather than a white streak
    static let glintPeakAlpha: CGFloat = 0.4
    private static let glintGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: glintPeakAlpha), UIColor(white: 1, alpha: 0)]
            .map(\.cgColor) as CFArray,
        locations: [0, 0.5, 1]
    )
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.advance() }
    private var phase: CGFloat = 0
    /// How long the glint has been running, negative while it waits for the new text, or nil once it has passed
    private(set) var glintTime: CFTimeInterval?
    private var lastFrame: CFTimeInterval?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        font = Self.textFont
        textColor = .black
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setText(_ text: String?, animated: Bool) {
        if let text, text != self.text {
            glintTime = -Self.glintDelay
        } else if text == nil {
            glintTime = nil
        }
        changeText(animated: animated) {
            self.attributedText = text.map {
                NSAttributedString(string: $0, attributes: [.font: Self.textFont, .foregroundColor: UIColor.black])
            }
        }
    }

    /// The text a moment ago, leaving while the new one comes in
    private var outgoingTextView: UIView?

    /// Applies new text with `apply`. Animated, the old text blurs away as it drifts up, while the new one comes into
    /// focus from below, the two crossing in a blur.
    public func changeText(animated: Bool, apply: () -> Void) {
        outgoingTextView?.removeFromSuperview()
        outgoingTextView = nil
        BlurTransition.cancel(layer)
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        guard animated, window != nil, let superview, !bounds.isEmpty, (attributedText?.length ?? 0) > 0,
              !UIAccessibility.isReduceMotionEnabled else {
            apply()
            return
        }
        let outgoing = UIImageView(image: makeLayerImage())
        outgoing.frame = frame
        outgoing.isUserInteractionEnabled = false
        outgoing.isAccessibilityElement = false
        superview.insertSubview(outgoing, aboveSubview: self)
        outgoingTextView = outgoing
        apply()

        let drift: CGFloat = 5
        BlurTransition.animateOut(outgoing.layer, duration: 0.25, drift: -drift) { [weak self, weak outgoing] in
            outgoing?.removeFromSuperview()
            if let self, outgoingTextView === outgoing { outgoingTextView = nil }
        }
        BlurTransition.animateIn(layer, duration: 0.35, delay: 0.05, drift: drift)
    }

    public override func drawText(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let gradient = Self.gradient else {
            super.drawText(in: rect)
            return
        }
        // The text is drawn as a shape and the gradient fills only that shape
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        super.drawText(in: rect)
        context.setBlendMode(.sourceIn)
        let width = max(1, bounds.width)
        let offset = Self.getSweepOffset(
            phase: phase,
            width: width,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        for start in [offset, offset + width * 2] {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: start, y: 0),
                end: CGPoint(x: start + width * 2, y: 0),
                options: []
            )
        }
        // The glint lights only the text, over its gradient, slanted as light on a polished surface
        if let glintTime, let centre = Self.getGlintCentre(
            time: glintTime,
            width: width,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        ), let glint = Self.glintGradient {
            context.setBlendMode(.sourceAtop)
            let slant = bounds.height * 0.35
            context.drawLinearGradient(
                glint,
                start: CGPoint(x: centre - Self.glintHalfWidth - slant, y: bounds.maxY),
                end: CGPoint(x: centre + Self.glintHalfWidth + slant, y: bounds.minY),
                options: []
            )
        }
        context.endTransparencyLayer()
    }

    /// Where the glint's middle crosses the text `time` seconds into the glint, or nil before or after it. It runs in
    /// the reading direction, from just before the text to just past it.
    static func getGlintCentre(time: CFTimeInterval, width: CGFloat, isRightToLeft: Bool) -> CGFloat? {
        let progress = time / glintDuration
        guard progress >= 0, progress <= 1 else { return nil }
        // Eased, so the light speeds up across the middle and lingers at the ends
        let eased = CGFloat(progress * progress * (3 - 2 * progress))
        let travel = width + 4 * glintHalfWidth
        let distance = -2 * glintHalfWidth + eased * travel
        return isRightToLeft ? width - distance : distance
    }

    /// Where the first of the two gradient tiles starts at `phase`. The sweep runs in the reading direction: rightward
    /// in left-to-right layouts, leftward in right-to-left ones. Either way the tiles cover the label.
    static func getSweepOffset(phase: CGFloat, width: CGFloat, isRightToLeft: Bool) -> CGFloat {
        isRightToLeft ? -phase * width * 2 : (phase - 1) * width * 2
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !UIAccessibility.isReduceMotionEnabled, !clock.isRunning {
            clock.start()
        } else if window == nil, clock.isRunning {
            clock.stop()
            lastFrame = nil
        }
    }

    private func advance() {
        let now = CACurrentMediaTime()
        let dt = lastFrame.map { min(0.05, now - $0) } ?? 0
        lastFrame = now
        step(by: dt)
    }

    /// Moves the sweep and the glint on by `dt` seconds
    func step(by dt: CFTimeInterval) {
        // One sweep every two seconds, so the text reads as alive without flickering
        phase = (phase + CGFloat(dt) / 2).truncatingRemainder(dividingBy: 1)
        if let glintTime {
            let time = glintTime + dt
            self.glintTime = time > Self.glintDuration ? nil : time
        }
        setNeedsDisplay()
    }
}
