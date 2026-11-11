import UIKit

final class AgentBubbleBackgroundView: UIView {

    private enum Metrics {
        static let tailSize = CGSize(width: 22.153, height: 26.9084)
        static let tailAttachmentHeight: CGFloat = 20
        static let tailBottomOverflow = tailSize.height - tailAttachmentHeight
    }

    enum Direction {
        case incoming
        case outgoing
    }

    struct CornerRadii {
        let topLeft: CGFloat
        let topRight: CGFloat
        let bottomRight: CGFloat
        let bottomLeft: CGFloat

        static func uniform(_ radius: CGFloat) -> CornerRadii {
            CornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        }
        
        static let standAlone = CornerRadii.uniform(20)

        static let bottomAction = CornerRadii(
                topLeft: 8,
                topRight: 8,
                bottomRight: 16,
                bottomLeft: 16
            )
        
        static let topActioned = CornerRadii(
                topLeft: 20,
                topRight: 20,
                bottomRight: 8,
                bottomLeft: 8
            )
    }

    let contentView = UIView()
    nonisolated static let tailBottomOverflow = Metrics.tailBottomOverflow

    private let bodyView = UIView()
    private let bodyMaskLayer = CAShapeLayer()
    private let tailView = UIView()
    private let tailLayer = CAShapeLayer()

    private lazy var incomingTailLeadingConstraint = tailView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor)
    private lazy var outgoingTailTrailingConstraint = tailView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor)
    private lazy var tailTopConstraint = tailView.topAnchor.constraint(equalTo: bodyView.bottomAnchor, constant: -Metrics.tailAttachmentHeight)
    private lazy var bodyBottomConstraint = bodyView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.tailBottomOverflow)
    private lazy var tailHeightConstraint = tailView.heightAnchor.constraint(equalToConstant: Metrics.tailSize.height)

    private var direction: Direction = .incoming
    private var fillColor: UIColor = .clear
    private var usesTintColor = false
    private var cornerRadii = CornerRadii.standAlone
    private(set) var showsTail = true
    /// The tail as it was, going into its corner while the real one is already gone
    private var tailGhostLayer: CAShapeLayer?
    /// The tail is growing out of its corner, in the growth of this generation
    private var isTailGrowing = false
    private var tailGrowthGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(
        direction: Direction,
        fillColor: UIColor,
        usesTintColor: Bool = false,
        showsTail: Bool = true,
        cornerRadii: CornerRadii = .standAlone,
        shouldAnimateTail: Bool = false
    ) {
        let isTailChanging = showsTail != self.showsTail
        let morphsTail = isTailChanging && shouldAnimateTail && window != nil
        // The tail leaves from where it stands now
        if morphsTail, !showsTail {
            morphTailAway()
        }
        self.direction = direction
        self.fillColor = fillColor
        self.usesTintColor = usesTintColor
        self.showsTail = showsTail
        self.cornerRadii = cornerRadii

        applyCurrentFillColor()

        if direction == .incoming {
            outgoingTailTrailingConstraint.isActive = false
            incomingTailLeadingConstraint.isActive = true
        } else {
            incomingTailLeadingConstraint.isActive = false
            outgoingTailTrailingConstraint.isActive = true
        }
        tailView.isHidden = !showsTail
        bodyBottomConstraint.constant = showsTail ? -Metrics.tailBottomOverflow : 0
        tailTopConstraint.constant = showsTail ? -Metrics.tailAttachmentHeight : 0
        tailHeightConstraint.constant = showsTail ? Metrics.tailSize.height : 0

        setNeedsLayout()
        if morphsTail, showsTail {
            morphTailBack()
        } else if isTailChanging, !morphsTail {
            endTailMorph()
        }
    }

    /// How the tail goes into its corner and comes back out of it. It goes as the suggestions that take its place come
    /// in, with their timing and curve, and comes back on the spring the tail has on every platform as they go.
    @MainActor
    enum TailMorph {
        static let awayDuration = AgentFollowupView.revealDuration
        static let backDuration: TimeInterval = 0.4
        static let backDelay: TimeInterval = 0.05
        static let backDamping: CGFloat = 0.75
        /// The tail at its smallest: a point in the corner
        static let collapsedScale: CGFloat = 0.01
    }

    /// The point the tail shrinks into and grows out of, in the bubble: the middle of where it joins the body, inside
    /// the body's rounded corner, so the tail stays on the bubble all the way
    var tailCornerAnchor: CGPoint {
        let body = bodyView.frame
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let isOnLeft = (direction == .incoming) != isRightToLeft
        let minX = isOnLeft ? body.minX : body.maxX - Metrics.tailSize.width
        return CGPoint(x: minX + Metrics.tailSize.width / 2, y: body.maxY - Metrics.tailAttachmentHeight / 2)
    }

    /// Whether the tail is on its way into its corner or out of it
    var isTailMorphing: Bool {
        tailGhostLayer != nil || isTailGrowing
    }

    /// The tail shrunk into `tailCornerAnchor`, as a transform about its centre
    private static var collapsedTailTransform: CGAffineTransform {
        makeTailTransform(scale: TailMorph.collapsedScale)
    }

    /// The tail at `scale` about `tailCornerAnchor`, as a transform about its centre
    static func makeTailTransform(scale: CGFloat) -> CGAffineTransform {
        let anchor = CGPoint(x: Metrics.tailSize.width / 2, y: Metrics.tailAttachmentHeight / 2)
        let center = CGPoint(x: Metrics.tailSize.width / 2, y: Metrics.tailSize.height / 2)
        return CGAffineTransform(translationX: (1 - scale) * (anchor.x - center.x), y: (1 - scale) * (anchor.y - center.y))
            .scaledBy(x: scale, y: scale)
    }

    /// The tail shrinks into its corner, uncovering the body's rounded corner under it. A copy of it goes, as the bubble
    /// already has its tailless size. With Reduce Motion it fades instead.
    private func morphTailAway() {
        removeTailGhost()
        tailGrowthGeneration += 1
        isTailGrowing = false
        guard !tailView.bounds.isEmpty, let path = tailLayer.path else { return }
        let presentedTransform = tailView.layer.presentation()?.transform ?? CATransform3DMakeAffineTransform(tailView.transform)
        let presentedOpacity = tailView.layer.presentation()?.opacity ?? Float(tailView.alpha)
        tailView.layer.removeAllAnimations()
        tailView.transform = .identity
        tailView.alpha = 1

        let ghost = CAShapeLayer()
        ghost.bounds = tailView.bounds
        ghost.position = tailView.center
        ghost.path = path
        ghost.fillColor = tailLayer.fillColor
        ghost.actions = ["transform": NSNull(), "opacity": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer.insertSublayer(ghost, above: tailView.layer)
        tailGhostLayer = ghost

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak ghost] in
            guard let self, let ghost, self.tailGhostLayer === ghost else { return }
            self.removeTailGhost()
        }
        let animation: CABasicAnimation
        if UIAccessibility.isReduceMotionEnabled {
            ghost.opacity = 0
            animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = presentedOpacity
            animation.toValue = 0
        } else {
            let collapsed = CATransform3DMakeAffineTransform(Self.collapsedTailTransform)
            ghost.transform = collapsed
            ghost.opacity = presentedOpacity
            animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = presentedTransform
            animation.toValue = collapsed
        }
        animation.duration = TailMorph.awayDuration
        animation.timingFunction = AgentFollowupView.makeRevealTimingFunction()
        ghost.add(animation, forKey: "tailMorph")
        CATransaction.commit()
    }

    /// The tail grows back out of its corner, covering the body's rounded corner again. With Reduce Motion it fades in.
    /// The animations are the layer's own, so they run also when the bubble's row is configured inside an update that
    /// runs without UIKit's animations, as the chat's update of its rows does.
    private func morphTailBack(delay: TimeInterval = TailMorph.backDelay) {
        removeTailGhost()
        tailView.layer.removeAllAnimations()
        tailView.alpha = 1
        tailView.transform = .identity
        let layer = tailView.layer
        let beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        let animation: CAAnimation
        if UIAccessibility.isReduceMotionEnabled {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = TailMorph.awayDuration
            fade.timingFunction = AgentFollowupView.makeRevealTimingFunction()
            animation = fade
        } else {
            let growth = CAKeyframeAnimation(keyPath: "transform")
            let frameCount = 40
            growth.values = (0...frameCount).map { index in
                let scale = Self.getSpringScale(at: TailMorph.backDuration * Double(index) / Double(frameCount))
                return NSValue(caTransform3D: CATransform3DMakeAffineTransform(Self.makeTailTransform(scale: scale)))
            }
            growth.keyTimes = (0...frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
            growth.duration = TailMorph.backDuration
            animation = growth
        }
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        isTailGrowing = true
        tailGrowthGeneration += 1
        let generation = tailGrowthGeneration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // A later growth replaced this one
            guard let self, self.tailGrowthGeneration == generation else { return }
            self.isTailGrowing = false
        }
        layer.add(animation, forKey: "tailMorph")
        CATransaction.commit()
    }

    /// The tail's scale `time` into its growth: a spring of `TailMorph.backDamping` from `collapsedScale` that settles
    /// within `backDuration`, as UIKit's spring of that damping does
    private static func getSpringScale(at time: TimeInterval) -> CGFloat {
        let damping = Double(TailMorph.backDamping)
        // The envelope falls to a thousandth by the end
        let frequency = 6.9 / (damping * TailMorph.backDuration)
        let dampedFrequency = frequency * (1 - damping * damping).squareRoot()
        let envelope = exp(-damping * frequency * time)
        let progress = 1 - envelope * (cos(dampedFrequency * time)
            + damping * frequency / dampedFrequency * sin(dampedFrequency * time))
        let start = TailMorph.collapsedScale
        return start + (1 - start) * CGFloat(time >= TailMorph.backDuration ? 1 : progress)
    }

    /// The tail as its state has it, without a morph
    private func endTailMorph() {
        removeTailGhost()
        tailGrowthGeneration += 1
        isTailGrowing = false
        tailView.layer.removeAllAnimations()
        tailView.alpha = 1
        tailView.transform = .identity
    }

    private func removeTailGhost() {
        tailGhostLayer?.removeFromSuperlayer()
        tailGhostLayer = nil
    }

    /// The bubble without its tail, its fill and its corners' radius, which a tapped suggestion turns into
    var bodyFrame: CGRect { bodyView.frame }
    var bodyFill: UIColor? { bodyView.backgroundColor }
    /// The body's layer, whose opacity a test checks as the bubble takes a morph's place
    var bodyLayer: CALayer { bodyView.layer }
    var bodyCornerRadius: CGFloat { cornerRadii.topLeft }
    /// The tail at rest, which a tapped suggestion grows as it turns into the bubble: its frame in the bubble, its shape
    /// in that frame and its fill
    struct RestingTail {
        let frame: CGRect
        let path: CGPath
        let fill: CGColor?
    }

    /// Nil while the bubble has no tail
    var restingTail: RestingTail? {
        guard showsTail, let path = tailLayer.path, !tailView.bounds.isEmpty else { return nil }
        let size = tailView.bounds.size
        let frame = CGRect(
            x: tailView.center.x - size.width / 2,
            y: tailView.center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return RestingTail(frame: frame, path: path, fill: tailLayer.fillColor)
    }

    /// `previewPath` moved into `rect`, for a menu that masks the bubble's attachment with it
    func makePreviewPath(in rect: CGRect) -> CGPath {
        let path = previewPath()
        path.apply(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path.cgPath
    }

    func previewPath() -> UIBezierPath {
        layoutIfNeeded()

        let path = UIBezierPath()
        path.append(Self.roundedPath(in: bodyView.frame, radii: cornerRadii))

        guard showsTail else { return path }

        let tailPath = Self.previewTailPath(in: tailView.bounds, mirrored: tailPathIsMirrored)
        tailPath.apply(
            CGAffineTransform(
                translationX: tailView.frame.minX,
                y: tailView.frame.minY
            )
        )
        path.append(tailPath)

        return path
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        performWithoutImplicitAnimations {
            bodyMaskLayer.frame = bodyView.bounds
            bodyMaskLayer.path = Self.roundedPath(in: bodyView.bounds, radii: cornerRadii).cgPath
            tailLayer.frame = tailView.bounds
            tailLayer.path = showsTail ? Self.tailPath(in: tailView.bounds, mirrored: tailPathIsMirrored) : nil
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyCurrentFillColor()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyCurrentFillColor()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        tintAdjustmentMode = .normal
        clipsToBounds = false
        layer.masksToBounds = false

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        let noImplicitGeometry: [String: CAAction] = [
            "path": NSNull(),
            "frame": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
        ]
        bodyMaskLayer.actions = noImplicitGeometry
        bodyView.layer.mask = bodyMaskLayer
        addSubview(bodyView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(contentView)

        tailView.translatesAutoresizingMaskIntoConstraints = false
        tailView.backgroundColor = .clear
        tailView.isUserInteractionEnabled = false
        tailView.clipsToBounds = false
        tailLayer.actions = noImplicitGeometry
        tailView.layer.addSublayer(tailLayer)
        addSubview(tailView)

        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyBottomConstraint,

            contentView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),

            tailTopConstraint,
            tailView.widthAnchor.constraint(equalToConstant: Metrics.tailSize.width),
            tailHeightConstraint,
            tailView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configure(direction: .incoming, fillColor: .clear)
    }

    private func applyCurrentFillColor() {
        let resolvedFillColor = fillColor.resolvedColor(with: traitCollection)
        let appliedFillColor = usesTintColor
            ? tintColor.withAlphaComponent(resolvedFillColor.cgColor.alpha)
            : resolvedFillColor
        performWithoutImplicitAnimations {
            bodyView.backgroundColor = appliedFillColor
            tailLayer.fillColor = appliedFillColor.cgColor
        }
    }

    func revealFill(from color: UIColor, duration: TimeInterval) {
        let source = color.resolvedColor(with: traitCollection).cgColor
        for (layer, key, target) in [
            (bodyView.layer, "backgroundColor", bodyView.layer.backgroundColor),
            (tailLayer, "fillColor", tailLayer.fillColor),
        ] {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = source
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "agentSkeletonReveal.fill")
        }
    }

    private var tailPathIsMirrored: Bool {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        switch direction {
        case .incoming:
            return !isRightToLeft
        case .outgoing:
            return isRightToLeft
        }
    }

    private func performWithoutImplicitAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private static func roundedPath(in bounds: CGRect, radii: CornerRadii) -> UIBezierPath {
        let width = max(bounds.width, 0)
        let height = max(bounds.height, 0)

        let topLeft = min(radii.topLeft, min(width, height) / 2)
        let topRight = min(radii.topRight, min(width, height) / 2)
        let bottomRight = min(radii.bottomRight, min(width, height) / 2)
        let bottomLeft = min(radii.bottomLeft, min(width, height) / 2)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: topLeft, y: 0))
        path.addLine(to: CGPoint(x: width - topRight, y: 0))

        if topRight > 0 {
            path.addArc(
                withCenter: CGPoint(x: width - topRight, y: topRight),
                radius: topRight,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: width, y: height - bottomRight))
        if bottomRight > 0 {
            path.addArc(
                withCenter: CGPoint(x: width - bottomRight, y: height - bottomRight),
                radius: bottomRight,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: bottomLeft, y: height))
        if bottomLeft > 0 {
            path.addArc(
                withCenter: CGPoint(x: bottomLeft, y: height - bottomLeft),
                radius: bottomLeft,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: 0, y: topLeft))
        if topLeft > 0 {
            path.addArc(
                withCenter: CGPoint(x: topLeft, y: topLeft),
                radius: topLeft,
                startAngle: .pi,
                endAngle: -.pi / 2,
                clockwise: true
            )
        }

        path.close()
        return path
    }

    private static func tailPath(in bounds: CGRect, mirrored: Bool) -> CGPath {
        let path = outgoingTailPath(in: bounds)
        guard mirrored else { return path.cgPath }

        var transform = CGAffineTransform(translationX: bounds.width, y: 0).scaledBy(x: -1, y: 1)
        return path.cgPath.copy(using: &transform) ?? path.cgPath
    }

    private static func outgoingTailPath(in bounds: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let scaleX = bounds.width / Metrics.tailSize.width
        let scaleY = bounds.height / Metrics.tailSize.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        path.move(to: point(22.153, 0))
        path.addCurve(
            to: point(14.153, 16),
            controlPoint1: point(22.153, 6.5424),
            controlPoint2: point(19.010, 12.3511)
        )
        path.addCurve(
            to: point(13.455, 25.3561),
            controlPoint1: point(10.423, 18.8554),
            controlPoint2: point(11.317, 22.4828)
        )
        path.addCurve(
            to: point(12.974, 26.9084),
            controlPoint1: point(13.862, 25.9040),
            controlPoint2: point(13.630, 26.7207)
        )
        path.addCurve(
            to: point(12.348, 26.8634),
            controlPoint1: point(12.767, 26.9676),
            controlPoint2: point(12.544, 26.9520)
        )
        path.addCurve(
            to: point(2.505, 20.8690),
            controlPoint1: point(8.458, 25.1080),
            controlPoint2: point(5.684, 23.3351)
        )
        path.addCurve(
            to: point(0, 20),
            controlPoint1: point(1.788, 20.3123),
            controlPoint2: point(0.908, 20)
        )
        path.close()

        return path
    }

    private static func previewTailPath(in bounds: CGRect, mirrored: Bool) -> UIBezierPath {
        let path = outgoingTailPath(in: bounds)
        guard mirrored else { return path }

        path.apply(CGAffineTransform(translationX: bounds.width, y: 0).scaledBy(x: -1, y: 1))
        return path.reversing()
    }
}
