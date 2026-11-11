import UIKit
import UIComponents

/// A tapped suggestion turns into its question's bubble: the pill's frame, corners and glassy fill become the bubble's
/// frame, corners and colour, and its title moves onto the bubble's text, scaling with it from the title's size to the
/// text's, as the one fades into the other. The title keeps the pill's line breaks and the text has the bubble's, so
/// each goes out of focus as it fades: the two never show sharp together, wherever their lines break. The morph follows
/// the bubble wherever the chat shows it meanwhile, in place or coming up as the chat scrolls. Once it has the bubble's
/// fill, the bubble's tail grows out of its corner, ending with the frame and the corners. At its end it is the bubble,
/// tail, fill and text, opaque, and the real bubble takes its place at once. The real bubble stays out of sight until
/// then.
/// From the chat list's field, the question's text takes the title's place: the bubble's fill grows around it from
/// where it stood, with no pill, as the text moves onto the bubble's.
@MainActor
final class AgentSuggestionMorph {
    static let duration: CFTimeInterval = 0.45
    /// The part of the morph over which the title gives way to the bubble's text, and the pill's fill to the bubble's
    private static let crossfade: ClosedRange<CGFloat> = 0.15...0.6
    /// The part of the morph over which the bubble's tail grows out of its corner, after the fill has become the bubble's
    private static let tailGrowth: ClosedRange<CGFloat> = 0.6...1
    /// The blur of the title as it fades out, and of the text before it fades in
    static let crossfadeBlurRadius: CGFloat = AgentBlurTransition.radius / 2

    /// The question's cell as it shows now, or nil while the chat has none on screen
    private let getCell: () -> AgentMessageCell?
    private let container: UIView
    /// Where the morph starts, in the container: the pill, or the field's text
    let startFrame: CGRect
    private let startTitleOffset: CGPoint
    private let titleFontSize: CGFloat
    private let isRightToLeft: Bool
    /// The morph starts from the field's text rather than a suggestion's pill
    private let isFromText: Bool
    private let duration: CFTimeInterval
    /// When the morph's time starts: its first frame on screen, so a busy main thread as the question goes in doesn't
    /// take its start away
    private(set) var startTime = CACurrentMediaTime()
    private var hasShownFrame = false
    private let curve = AgentComposerMetrics.makeTelegramCurve()
    let morphView = UIView()
    /// The pill's and the bubble's background, rounded, under the texts, which it doesn't clip as their lines break
    /// differently
    private let backgroundView = UIView()
    private let pillView = AgentSuggestionBackgroundView(
        cornerRadius: AgentSuggestionButton.height / 2,
        cornerCurve: .continuous
    )
    private let fillView = UIView()
    /// The bubble's tail, which hangs out of the background
    let tailLayer = CAShapeLayer()
    /// How far the tail has grown out of its corner, from `collapsedScale` to 1
    private(set) var tailScale = AgentBubbleBackgroundView.TailMorph.collapsedScale
    let titleView: UIImageView
    let textView = UIImageView()
    private weak var hiddenBubble: UIView?
    private(set) var isFinished = false
    private(set) var titleBlurRadius: CGFloat = 0
    private(set) var textBlurRadius: CGFloat = 0
    /// Where the bubble was last seen, which the morph keeps going toward while the chat has no cell for it
    private var lastTarget: Target?
    /// The bubble the morph is going to: its body's frame, its text's offset in the body, size and font size, and its
    /// tail
    private struct Target {
        let frame: CGRect
        let textOffset: CGPoint
        let textSize: CGSize
        let fontSize: CGFloat
        let tail: Tail?
    }
    /// The bubble's tail, placed from the body's bottom edge and from the side it hangs on
    private struct Tail {
        let path: CGPath
        let fill: CGColor?
        let size: CGSize
        let isOnMinX: Bool
        /// From the body's edge on the tail's side to the tail's edge on that side
        let sideOffset: CGFloat
        /// From the body's bottom to the tail's top
        let bottomOffset: CGFloat
    }
    /// The bubble's body the morph is going to, in the container, once the chat has shown it
    var targetFrame: CGRect? { lastTarget?.frame }
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] time in self?.showFrame(at: time) }

    /// Starts the morph of the suggestion or text picture of `source` into the bubble of the cell `getCell` finds, in
    /// `container`, which holds the source's frame, over `duration`. Nil for a source of another kind, or with Reduce
    /// Motion.
    static func start(
        from source: AgentSentMessageSource,
        in container: UIView,
        duration: CFTimeInterval = AgentSuggestionMorph.duration,
        getCell: @escaping () -> AgentMessageCell?
    ) -> AgentSuggestionMorph? {
        // The container may be the window itself
        guard !UIAccessibility.isReduceMotionEnabled, container is UIWindow || container.window != nil else { return nil }
        let morph: AgentSuggestionMorph
        switch source.kind {
        case .suggestion(let title, let titleFrame, let titleFontSize):
            morph = AgentSuggestionMorph(
                frame: source.frame,
                title: title,
                titleFrame: titleFrame,
                titleFontSize: titleFontSize,
                isFromText: false,
                duration: duration,
                container: container,
                getCell: getCell
            )
        case .textPicture(let picture, let fontSize):
            morph = AgentSuggestionMorph(
                frame: source.frame,
                title: picture,
                titleFrame: source.frame,
                titleFontSize: fontSize,
                isFromText: true,
                duration: duration,
                container: container,
                getCell: getCell
            )
        case .text:
            return nil
        }
        morph.step(at: morph.startTime)
        morph.clock.start()
        return morph
    }

    private init(
        frame: CGRect,
        title: UIImage,
        titleFrame: CGRect,
        titleFontSize: CGFloat,
        isFromText: Bool,
        duration: CFTimeInterval,
        container: UIView,
        getCell: @escaping () -> AgentMessageCell?
    ) {
        self.container = container
        self.getCell = getCell
        self.isFromText = isFromText
        self.duration = duration
        startFrame = frame
        isRightToLeft = container.effectiveUserInterfaceLayoutDirection == .rightToLeft
        startTitleOffset = CGPoint(
            x: isRightToLeft ? frame.maxX - titleFrame.maxX : titleFrame.minX - frame.minX,
            y: titleFrame.minY - frame.minY
        )
        self.titleFontSize = titleFontSize
        titleView = UIImageView(image: title)
        morphView.isUserInteractionEnabled = false
        morphView.isAccessibilityElement = false
        backgroundView.clipsToBounds = true
        // The bubble's corners are circular arcs, which the morph's end matches exactly
        backgroundView.layer.cornerCurve = .circular
        backgroundView.layer.cornerRadius = AgentSuggestionButton.height / 2
        fillView.alpha = 0
        textView.alpha = 0
        tailLayer.isHidden = true
        pillView.isHidden = isFromText
        backgroundView.addSubview(pillView)
        backgroundView.addSubview(fillView)
        for view in [backgroundView, titleView, textView] {
            morphView.addSubview(view)
        }
        morphView.layer.insertSublayer(tailLayer, above: backgroundView.layer)
        for view in [titleView, textView] {
            if let blur = WBlurredContentView.makeGaussianBlurFilter() {
                view.layer.filters = [blur]
            }
        }
        container.addSubview(morphView)
    }

    /// Ends the morph where it stands: the bubble shows and the morph goes
    func cancel() {
        finish()
    }

    private func showFrame(at time: CFTimeInterval) {
        if !hasShownFrame {
            hasShownFrame = true
            startTime = time
        }
        step(at: time)
    }

    /// Shows the morph as it stands at `time`, on the media clock
    func step(at time: CFTimeInterval) {
        guard !isFinished else { return }
        let isEnd = time >= startTime + duration
        let fraction = isEnd ? 1 : min(1, max(0, CGFloat((time - startTime) / duration)))
        let progress = AgentLayerAnimationSampler.getEasedFraction(curve, at: fraction)
        let cell = getCell()
        if let cell {
            updateTarget(from: cell)
            hideBubble(of: cell)
        }
        // Until the chat shows the bubble, the pill stays where it was tapped
        let target = lastTarget ?? Target(
            frame: startFrame,
            textOffset: startTitleOffset,
            textSize: titleView.image?.size ?? .zero,
            fontSize: titleFontSize,
            tail: nil
        )

        let frame = Self.interpolate(startFrame, target.frame, progress)
        morphView.bounds = CGRect(origin: .zero, size: frame.size)
        morphView.center = CGPoint(x: frame.midX, y: frame.midY)
        backgroundView.frame = morphView.bounds
        pillView.frame = backgroundView.bounds
        fillView.frame = backgroundView.bounds
        let endRadius = cell?.bubbleBackgroundView.bodyCornerRadius ?? AgentBubbleBackgroundView.CornerRadii.standAlone.topLeft
        backgroundView.layer.cornerRadius = min(
            AgentSuggestionButton.height / 2 + (endRadius - AgentSuggestionButton.height / 2) * progress,
            frame.height / 2
        )
        if let fill = cell?.bubbleBackgroundView.bodyFill {
            fillView.backgroundColor = fill
        }

        // The title and the text stand on one point, scaled alike, so the one fades into the other in place
        let shift = Self.getShare(of: progress, in: Self.crossfade)
        let offset = CGPoint(
            x: startTitleOffset.x + (target.textOffset.x - startTitleOffset.x) * progress,
            y: startTitleOffset.y + (target.textOffset.y - startTitleOffset.y) * progress
        )
        let textScale = target.fontSize / titleFontSize
        let titleScale = 1 + (textScale - 1) * progress
        place(titleView, size: titleView.image?.size ?? .zero, scale: titleScale, offset: offset, in: frame.size)
        place(textView, size: target.textSize, scale: titleScale / textScale, offset: offset, in: frame.size)
        pillView.alpha = 1 - shift
        // Around the field's text, the bubble's fill comes in as it grows, by the morph's middle
        fillView.alpha = isFromText ? Self.getShare(of: progress, in: 0...0.5) : shift
        titleView.alpha = 1 - shift
        textView.alpha = shift
        // Halfway through, both are as much out of focus, and by its end the text is sharp
        titleBlurRadius = Self.crossfadeBlurRadius * shift
        textBlurRadius = Self.crossfadeBlurRadius * (1 - shift)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleView.layer.setValue(titleBlurRadius, forKeyPath: Self.blurRadiusKeyPath)
        textView.layer.setValue(textBlurRadius, forKeyPath: Self.blurRadiusKeyPath)
        placeTail(target.tail, growth: Self.getShare(of: progress, in: Self.tailGrowth), in: frame.size)
        CATransaction.commit()

        // The real bubble takes over at the end, at once: two translucent bubbles would show lighter than either
        if isEnd {
            finish()
        }
    }

    private func updateTarget(from cell: AgentMessageCell) {
        let bubble = cell.bubbleBackgroundView
        let body = bubble.convertAsShown(bubble.bodyFrame, to: container)
        guard !body.isEmpty else { return }
        let text = cell.sentTextView
        guard !text.bounds.isEmpty else { return }
        let textFrame = text.convertAsShown(text.bounds, to: container)
        if textView.image == nil || textView.image?.size != text.bounds.size {
            textView.image = text.makeLayerImage()
        }
        let tail = bubble.restingTail.map { tail in
            let frame = bubble.convertAsShown(tail.frame, to: container)
            let isOnMinX = abs(frame.minX - body.minX) < abs(frame.maxX - body.maxX)
            return Tail(
                path: tail.path,
                fill: tail.fill,
                size: tail.frame.size,
                isOnMinX: isOnMinX,
                sideOffset: isOnMinX ? frame.minX - body.minX : frame.maxX - body.maxX,
                bottomOffset: frame.minY - body.maxY
            )
        }
        lastTarget = Target(
            frame: body,
            textOffset: CGPoint(
                x: isRightToLeft ? body.maxX - textFrame.maxX : textFrame.minX - body.minX,
                y: textFrame.minY - body.minY
            ),
            textSize: text.bounds.size,
            fontSize: (text as? UITextView)?.font?.pointSize ?? AgentMessageTextRenderer.baseFont.pointSize,
            tail: tail
        )
    }

    /// Places the bubble's `tail`, grown out of its corner by `growth`, from 0 to 1, on a frame of `frameSize`
    private func placeTail(_ tail: Tail?, growth: CGFloat, in frameSize: CGSize) {
        guard let tail, growth > 0 else {
            tailLayer.isHidden = true
            tailScale = AgentBubbleBackgroundView.TailMorph.collapsedScale
            return
        }
        tailLayer.isHidden = false
        tailLayer.path = tail.path
        tailLayer.fillColor = tail.fill ?? fillView.backgroundColor?.cgColor
        tailLayer.transform = CATransform3DIdentity
        tailLayer.bounds = CGRect(origin: .zero, size: tail.size)
        let minX = tail.isOnMinX ? tail.sideOffset : frameSize.width + tail.sideOffset - tail.size.width
        let minY = frameSize.height + tail.bottomOffset
        tailLayer.position = CGPoint(x: minX + tail.size.width / 2, y: minY + tail.size.height / 2)
        let collapsedScale = AgentBubbleBackgroundView.TailMorph.collapsedScale
        tailScale = collapsedScale + (1 - collapsedScale) * growth
        tailLayer.transform = CATransform3DMakeAffineTransform(AgentBubbleBackgroundView.makeTailTransform(scale: tailScale))
    }

    private func hideBubble(of cell: AgentMessageCell) {
        let bubble = cell.sentAppearanceView
        guard hiddenBubble !== bubble else { return }
        hiddenBubble?.alpha = 1
        hiddenBubble = bubble
        bubble.layer.removeAllAnimations()
        bubble.transform = .identity
        bubble.alpha = 0
    }

    /// Places `view` of `size`, scaled by `scale` about its leading top corner, at `offset` from the leading top corner
    /// of a frame of `frameSize`
    private func place(_ view: UIView, size: CGSize, scale: CGFloat, offset: CGPoint, in frameSize: CGSize) {
        view.transform = .identity
        view.bounds = CGRect(origin: .zero, size: size)
        let width = size.width * scale
        let height = size.height * scale
        let minX = isRightToLeft ? frameSize.width - offset.x - width : offset.x
        view.center = CGPoint(x: minX + width / 2, y: offset.y + height / 2)
        view.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        clock.stop()
        hiddenBubble?.alpha = 1
        hiddenBubble = nil
        morphView.removeFromSuperview()
    }

    private static func interpolate(_ from: CGRect, _ to: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    private static let blurRadiusKeyPath = "filters.gaussianBlur.inputRadius"

    /// The suggestion buttons under `view`
    static func findSuggestionButtons(in view: UIView) -> [AgentSuggestionButton] {
        view.subviews.flatMap { subview -> [AgentSuggestionButton] in
            (subview as? AgentSuggestionButton).map { [$0] } ?? findSuggestionButtons(in: subview)
        }
    }

    /// How the suggestions beside a tapped one leave as it starts turning into its bubble
    enum Ripple {
        static let duration: CFTimeInterval = 0.2
        /// Each one leaves this much after the one nearer the tapped suggestion
        static let stagger: CFTimeInterval = 0.03
        static let endScale: CGFloat = 0.95
        static let blurRadius: CGFloat = AgentBlurTransition.radius / 2
    }

    /// The suggestions beside the tapped one leave as a ripple away from the finger, starting with the nearest: each
    /// fades out with a slight blur, shrinking a little toward its own centre. Pictures of them leave in `container`, in
    /// their places, while they themselves go out of sight at once, so the list closes up under the pictures as it
    /// would. With Reduce Motion they fade out together. Returns the pictures, which go once they have faded; a
    /// suggestion still there then, as when the question didn't go, shows again.
    @discardableResult
    static func rippleAway(_ suggestions: [UIView], from tapped: UIView, in container: UIView) -> [UIView] {
        let tappedCenter = tapped.convert(CGPoint(x: tapped.bounds.midX, y: tapped.bounds.midY), to: container)
        func distance(_ view: UIView) -> CGFloat {
            let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: container)
            return hypot(center.x - tappedCenter.x, center.y - tappedCenter.y)
        }
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        let shown = suggestions.filter { $0 !== tapped && $0.window != nil && !$0.isHidden && $0.alpha > 0.01 }
        var pictures: [UIView] = []
        for (rank, suggestion) in shown.sorted(by: { distance($0) < distance($1) }).enumerated() {
            guard let picture = suggestion.snapshotView(afterScreenUpdates: false) else { continue }
            picture.frame = suggestion.convert(suggestion.bounds, to: container)
            picture.isUserInteractionEnabled = false
            picture.isAccessibilityElement = false
            container.addSubview(picture)
            suggestion.alpha = 0
            pictures.append(picture)

            let layer = picture.layer
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            var animations: [CAAnimation] = [fade]
            if !isMotionReduced {
                let shrink = CABasicAnimation(keyPath: "transform.scale")
                shrink.fromValue = 1
                shrink.toValue = Ripple.endScale
                animations.append(shrink)
                if let blur = WBlurredContentView.makeGaussianBlurFilter() {
                    layer.filters = [blur]
                    layer.setValue(Ripple.blurRadius, forKeyPath: blurRadiusKeyPath)
                    let blurring = CABasicAnimation(keyPath: blurRadiusKeyPath)
                    blurring.fromValue = 0
                    blurring.toValue = Ripple.blurRadius
                    animations.append(blurring)
                }
            }
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = Ripple.duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
                + (isMotionReduced ? 0 : Ripple.stagger * Double(rank))
            group.fillMode = .backwards
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak picture, weak suggestion] in
                picture?.removeFromSuperview()
                suggestion?.alpha = 1
            }
            layer.opacity = 0
            if !isMotionReduced {
                layer.transform = CATransform3DMakeScale(Ripple.endScale, Ripple.endScale, 1)
            }
            layer.add(group, forKey: "ripple")
            CATransaction.commit()
        }
        return pictures
    }

    /// How far `value` is through `range`, from 0 before it to 1 after it
    static func getShare(of value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
}
