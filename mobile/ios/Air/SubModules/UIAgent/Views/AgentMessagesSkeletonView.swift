import UIKit
import UIComponents

/// Telegram's chat loading placeholder: a column of bubbles from the bottom, the Agent's and the user's in turn, each
/// with its tail, swept by a soft highlight with a brighter glint along their outlines. The news feed shows its cards
/// the same way.
final class AgentMessagesSkeletonView: AgentSkeletonView {
    struct Placeholder {
        let frame: CGRect
        let isOutgoing: Bool
    }
    private var placeholders: [Placeholder] = []

    func placeholdersInWindow() -> [Placeholder] {
        layoutIfNeeded()
        return placeholders.map { Placeholder(frame: convert($0.frame, to: nil), isOutgoing: $0.isOutgoing) }
    }
    enum Style {
        case messages
        case newsCards
        case suggestion
    }

    private struct Bubble {
        let widthFraction: CGFloat
        let height: CGFloat
    }

    /// The lowest bubble is the Agent's last answer; above it the user's question, and so on
    private static func isOutgoing(at index: Int) -> Bool {
        !index.isMultiple(of: 2)
    }

    /// Agent answers are usually longer than chat messages; reserve several paragraphs rather than a few lines.
    private static let shortBubbleHeight: CGFloat = 120
    private static let tallBubbleHeight: CGFloat = 184
    /// Telegram's sequence from the bottom, with widths as fractions of the screen width
    private static let bubbles: [Bubble] = [
        Bubble(widthFraction: 0.86, height: tallBubbleHeight),
        Bubble(widthFraction: 0.70, height: shortBubbleHeight),
        Bubble(widthFraction: 0.92, height: tallBubbleHeight),
        Bubble(widthFraction: 0.64, height: shortBubbleHeight),
        Bubble(widthFraction: 0.80, height: tallBubbleHeight),
        Bubble(widthFraction: 0.72, height: shortBubbleHeight),
        Bubble(widthFraction: 0.86, height: tallBubbleHeight),
        Bubble(widthFraction: 0.64, height: shortBubbleHeight),
    ]
    /// The chat's spacing between messages, so a tail never reaches the bubble below it
    private static let bubbleSpacing = AgentVCLayout.rowSpacing
    /// The chat's insets of a bubble: at its own side, and the most it leaves at the other
    private static let bubbleSideInset = AgentMessageCellMetrics.horizontalInset
    private static let incomingOppositeInset = AgentMessageCellMetrics.incomingTrailingInset
    private static let outgoingOppositeInset = AgentMessageCellMetrics.outgoingOppositeInset
    private static let minimumBubbleWidth: CGFloat = 44

    /// Cards with and without a picture, from the bottom, with the feed's insets and spacing: the cards' rows are a
    /// chat's rows apart, and each card's tail hangs into its row's end
    private static let newsCardHeights: [CGFloat] = [380, 204]
    private static let newsCardSpacing = AgentVCLayout.rowSpacing + AgentBubbleBackgroundView.tailBottomOverflow
    private static let newsCardHorizontalInset: CGFloat = 16
    private static let newsCardCornerRadius: CGFloat = 20

    private static let shimmerDuration: CFTimeInterval = 1.6
    private static let fillBandWidth: CGFloat = 280
    private static let outlineBandWidth: CGFloat = 320

    /// Space kept free below the lowest placeholder
    var bottomInset: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    private let style: Style
    private var bubbleViews: [AgentBubbleBackgroundView] = []
    private let cardsLayer = CAShapeLayer()
    private let fillShimmerLayer = CALayer()
    private let fillBandLayer = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let outlineShimmerLayer = CALayer()
    private let outlineBandLayer = CAGradientLayer()
    private let outlineMask = CAShapeLayer()

    init(style: Style = .messages) {
        self.style = style
        // Telegram's loading placeholder fades out over 0.15 s as the messages fade in
        super.init(fadeDuration: 0.15)
        switch style {
        case .messages:
            for index in Self.bubbles.indices {
                let view = AgentBubbleBackgroundView()
                // Placed by frame: without constraints of its own, Auto Layout would collapse the body to the tail
                view.translatesAutoresizingMaskIntoConstraints = true
                // Telegram's placeholders share one colour on both sides
                view.configure(
                    direction: Self.isOutgoing(at: index) ? .outgoing : .incoming,
                    fillColor: .air.agentBubbleFill,
                    showsTail: true
                )
                addSubview(view)
                bubbleViews.append(view)
            }
        case .newsCards, .suggestion:
            layer.addSublayer(cardsLayer)
        }
        for (container, band, mask) in [
            (fillShimmerLayer, fillBandLayer, fillMask),
            (outlineShimmerLayer, outlineBandLayer, outlineMask),
        ] {
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            band.locations = [0, 0.25, 0.5, 0.75, 1]
            band.actions = Self.noImplicitGeometry
            mask.actions = Self.noImplicitGeometry
            container.actions = Self.noImplicitGeometry
            container.mask = mask
            container.addSublayer(band)
            layer.addSublayer(container)
        }
        cardsLayer.actions = Self.noImplicitGeometry
        outlineMask.fillColor = nil
        outlineMask.strokeColor = UIColor.black.cgColor
        outlineMask.lineWidth = 1
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholders.removeAll()
        let path = UIBezierPath()
        switch style {
        case .messages:
            layoutBubbles(into: path)
        case .newsCards:
            layoutCards(into: path)
        case .suggestion:
            path.append(UIBezierPath(roundedRect: bounds, cornerRadius: 18))
        }
        // One contour without the edges where a tail overlaps its bubble, so the glint follows only the outline
        let shape = path.cgPath.normalized()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardsLayer.frame = bounds
        cardsLayer.path = shape
        for (container, band, mask, bandWidth) in [
            (fillShimmerLayer, fillBandLayer, fillMask, Self.fillBandWidth),
            (outlineShimmerLayer, outlineBandLayer, outlineMask, Self.outlineBandWidth),
        ] {
            container.frame = bounds
            mask.frame = bounds
            mask.path = shape
            band.frame = CGRect(x: -bandWidth, y: 0, width: bandWidth, height: bounds.height)
        }
        CATransaction.commit()
        startShimmer(isRestarting: true)
    }

    private func layoutBubbles(into path: UIBezierPath) {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var maxY = bounds.maxY - bottomInset
        for (index, (view, bubble)) in zip(bubbleViews, Self.bubbles).enumerated() {
            let isOutgoing = Self.isOutgoing(at: index)
            let oppositeInset = isOutgoing ? Self.outgoingOppositeInset : Self.incomingOppositeInset
            let maximumWidth = bounds.width - Self.bubbleSideInset - oppositeInset
            let width = min(maximumWidth, max(Self.minimumBubbleWidth, (bounds.width * bubble.widthFraction).rounded()))
            let height = bubble.height + AgentBubbleBackgroundView.tailBottomOverflow
            let isAtTrailingEdge = isOutgoing != isRightToLeft
            let frame = CGRect(
                x: isAtTrailingEdge ? bounds.maxX - Self.bubbleSideInset - width : bounds.minX + Self.bubbleSideInset,
                y: maxY - height,
                width: width,
                height: height
            )
            maxY = frame.minY - Self.bubbleSpacing
            view.isHidden = frame.maxY < bounds.minY || width <= 0
            guard !view.isHidden else { continue }
            placeholders.append(Placeholder(frame: frame, isOutgoing: isOutgoing))
            view.frame = frame
            view.layoutIfNeeded()
            let bubblePath = view.previewPath()
            bubblePath.apply(CGAffineTransform(translationX: frame.minX, y: frame.minY))
            path.append(bubblePath)
        }
    }

    private func layoutCards(into path: UIBezierPath) {
        let width = bounds.width - 2 * Self.newsCardHorizontalInset
        guard width > 0 else { return }
        var maxY = bounds.maxY - bottomInset
        var index = 0
        while maxY > bounds.minY {
            let height = Self.newsCardHeights[index % Self.newsCardHeights.count]
            let frame = CGRect(x: bounds.minX + Self.newsCardHorizontalInset, y: maxY - height, width: width, height: height)
            placeholders.append(Placeholder(frame: frame, isOutgoing: false))
            path.append(UIBezierPath(roundedRect: frame, cornerRadius: Self.newsCardCornerRadius))
            maxY = frame.minY - Self.newsCardSpacing
            index += 1
        }
    }

    /// Telegram's highlight: a white band over the bubbles and a brighter one along their outlines. Light bubbles sit on a
    /// white background, so the band is stronger there to stay visible.
    override func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardsLayer.fillColor = UIColor.air.agentBubbleFill.resolvedColor(with: traitCollection).cgColor
        fillBandLayer.colors = Self.makeBandColors(peakAlpha: isDark ? 0.14 : 0.7)
        outlineBandLayer.colors = Self.makeBandColors(peakAlpha: isDark ? 0.35 : 0.6)
        CATransaction.commit()
    }

    private static func makeBandColors(peakAlpha: CGFloat) -> [CGColor] {
        [0, 0.35, 1, 0.35, 0].map { UIColor.white.withAlphaComponent(peakAlpha * $0).cgColor }
    }

    override func startShimmer(isRestarting: Bool = false) {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled, bounds.width > 0 else { return }
        for (band, bandWidth) in [(fillBandLayer, Self.fillBandWidth), (outlineBandLayer, Self.outlineBandWidth)] {
            // The band enters past the leading edge and leaves past the trailing one
            startSweep(
                of: band,
                along: "position.x",
                travel: bounds.width + bandWidth,
                duration: Self.shimmerDuration,
                isRestarting: isRestarting
            )
        }
    }

    override func stopShimmer() {
        fillBandLayer.removeAnimation(forKey: Self.shimmerKey)
        outlineBandLayer.removeAnimation(forKey: Self.shimmerKey)
    }
}
