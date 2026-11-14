import UIKit
import UIComponents
import WalletContext

/// The feed's daily digests as Telegram's pinned messages: a glass capsule under the header, as Telegram's panels under
/// a chat's header, with a stripe of one bar per digest on its leading edge, the oldest at the top and the shown one
/// lit, the digest's day as the title and its headlines as the text. A tap goes to the digest the bar shows. As the bar
/// shows another digest it moves as the web app's bar does, after Telegram Web's `HeaderPinnedMessage`: the title rolls
/// the characters after the part it keeps and the text slides a whole line, both the same way, and the lit bar slides
/// along the stripe.
@MainActor
final class AgentNewsPinnedDigestBar: UIView {
    static let height: CGFloat = 50
    /// The bar's distance from the column's sides
    static let sideInset: CGFloat = 16
    /// As Telegram's header panels: 4 pt under its 60 pt navigation bar, whose 44 pt controls end 8 pt above its foot, so
    /// 12 pt under the controls. Ours end about 10 pt above the safe area's top.
    static let topSpacing: CGFloat = 2
    /// Telegram's list starts 4 pt under its header panels, and a day's capsule sticks 6 pt under the list's top
    static let bottomSpacing: CGFloat = 4

    struct Content: Equatable {
        var title: String
        var text: String
        /// The digest's place among the stripe's segments, the oldest first
        var index: Int
        var count: Int
    }

    /// The way the text moves as the bar shows another digest: in from below for a newer one, from above for an older one
    enum Transition {
        case newer
        case older
    }

    // Telegram's pinned message panel: the stripe 18 pt in, the text 10 pt after it and 14 pt short of the end, the
    // title 6 pt and the text 23 pt from the top, both in 15 pt type. The text slides as Telegram Web's
    // `slideVerticalFade`, a whole line over its `--slide-transition`.
    private enum Metrics {
        static let stripeInset: CGFloat = 18
        static let textSpacing: CGFloat = 10
        static let trailingInset: CGFloat = 14
        static let titleTop: CGFloat = 6
        static let textTop: CGFloat = 23
        static let fontSize: CGFloat = 15
        static let slideDuration: TimeInterval = 0.3
        static let slideCurve = (CGPoint(x: 0.25, y: 1), CGPoint(x: 0.5, y: 1))
        static let highlightDuration: TimeInterval = 0.2
        static let highlightedAlpha: CGFloat = 0.4
    }

    var onTap: (() -> Void)?
    private(set) var content: Content?

    private let glassView = WGlassView(cornerRadius: AgentNewsPinnedDigestBar.height / 2)
    private let contentContainer = UIView()
    private let stripeView = AgentPinnedStripeView()
    private let textContainer = UIView()
    private let titleView = AgentPinnedTitleView()
    /// The text's line, which clips the text as it slides by its own height
    private let textLineView = UIView()
    private let textLabel = UILabel()
    private let tapButton = HighlightButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The blur that stands in for the glass leaves the touches to the button, which then lies above it
        let isBlur = glassView.effect is UIBlurEffect
        if isBlur {
            glassView.isUserInteractionEnabled = false
        }
        addSubview(glassView)
        contentContainer.isUserInteractionEnabled = false
        glassView.contentView.addSubview(contentContainer)
        contentContainer.addSubview(stripeView)
        textContainer.clipsToBounds = true
        contentContainer.addSubview(textContainer)
        titleView.font = .systemFont(ofSize: Metrics.fontSize, weight: .medium)
        textContainer.addSubview(titleView)
        textLabel.font = .systemFont(ofSize: Metrics.fontSize)
        textLabel.numberOfLines = 1
        textLineView.clipsToBounds = true
        textLineView.addSubview(textLabel)
        textContainer.addSubview(textLineView)
        tapButton.isAccessibilityElement = false
        tapButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        tapButton.onHighlight = { [weak self] isHighlighted in self?.setContentHighlighted(isHighlighted) }
        if isBlur {
            addSubview(tapButton)
        } else {
            glassView.contentView.addSubview(tapButton)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "AgentNewsPinnedDigest"
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        contentContainer.frame = bounds
        tapButton.frame = bounds
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textX = Metrics.stripeInset + AgentPinnedStripeView.width + Metrics.textSpacing
        let textWidth = max(0, bounds.width - textX - Metrics.trailingInset)
        stripeView.frame = CGRect(
            x: isRightToLeft ? bounds.width - Metrics.stripeInset - AgentPinnedStripeView.width : Metrics.stripeInset,
            y: (bounds.height - AgentPinnedStripeView.height) / 2,
            width: AgentPinnedStripeView.width,
            height: AgentPinnedStripeView.height
        )
        textContainer.frame = CGRect(x: isRightToLeft ? Metrics.trailingInset : textX, y: 0, width: textWidth, height: bounds.height)
        layoutLabels()
    }

    private func layoutLabels() {
        let width = textContainer.bounds.width
        titleView.frame = CGRect(x: 0, y: Metrics.titleTop, width: width, height: ceil(titleView.font.lineHeight))
        let lineHeight = ceil(textLabel.font.lineHeight)
        textLineView.frame = CGRect(x: 0, y: Metrics.textTop, width: width, height: lineHeight)
        textLabel.bounds = CGRect(x: 0, y: 0, width: width, height: lineHeight)
        textLabel.center = CGPoint(x: width / 2, y: lineHeight / 2)
    }

    /// Shows a digest. A transition rolls the title's changed characters, slides the text and moves the lit bar along
    /// the stripe.
    func setContent(_ content: Content, transition: Transition?) {
        guard content != self.content else { return }
        let isAnimated = transition != nil && self.content != nil && window != nil && !UIAccessibility.isReduceMotionEnabled
        // The old text leaves the way the new one comes from: up for a newer digest, down for an older one
        let direction: CGFloat = transition == .newer ? -1 : 1
        self.content = content
        if isAnimated {
            slideOutText(direction: direction)
        }
        titleView.setText(content.title, isFromBelow: transition == .newer, isAnimated: isAnimated)
        textLabel.text = content.text
        textLabel.textAlignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        accessibilityLabel = "\(content.title), \(content.text)"
        stripeView.update(index: content.index, count: content.count, animated: isAnimated)
        if isAnimated {
            slideInText(direction: direction)
        }
    }

    /// The text that was shown leaves toward `direction` by its line's height, a copy of it fading as it goes
    private func slideOutText(direction: CGFloat) {
        guard let copy = textLabel.snapshotView(afterScreenUpdates: false) else { return }
        copy.frame = textLabel.frame
        textLineView.addSubview(copy)
        let animator = makeSlideAnimator {
            copy.transform = CGAffineTransform(translationX: 0, y: direction * self.textLineView.bounds.height)
            copy.alpha = 0
        }
        animator.addCompletion { _ in copy.removeFromSuperview() }
        animator.startAnimation()
    }

    /// The new text comes in from the side the old one left from
    private func slideInText(direction: CGFloat) {
        textLabel.layer.removeAllAnimations()
        textLabel.transform = CGAffineTransform(translationX: 0, y: -direction * textLineView.bounds.height)
        textLabel.alpha = 0
        makeSlideAnimator {
            self.textLabel.transform = .identity
            self.textLabel.alpha = 1
        }.startAnimation()
    }

    private func makeSlideAnimator(_ animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(
            duration: Metrics.slideDuration,
            controlPoint1: Metrics.slideCurve.0,
            controlPoint2: Metrics.slideCurve.1,
            animations: animations
        )
    }

    // A press dims the content, which comes back as it lets go, as Telegram's panel does
    private func setContentHighlighted(_ isHighlighted: Bool) {
        contentContainer.layer.removeAnimation(forKey: "opacity")
        if isHighlighted {
            contentContainer.alpha = Metrics.highlightedAlpha
        } else {
            UIView.animate(withDuration: Metrics.highlightDuration) { self.contentContainer.alpha = 1 }
        }
    }

    private func updateColors() {
        titleView.textColor = tintColor
        textLabel.textColor = .label
        stripeView.color = tintColor
    }

    @objc private func handleTap() {
        onTap?()
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    private final class HighlightButton: UIControl {
        var onHighlight: ((Bool) -> Void)?

        override var isHighlighted: Bool {
            didSet {
                guard isHighlighted != oldValue else { return }
                onHighlight?(isHighlighted)
            }
        }
    }
}

/// The bar's title, the digest's day, as the web app's bar rolls it with Telegram Web's `AnimatedCounter` roll: the part
/// both titles start with, as "November " of November 9 and November 10, stays, and each character after it rolls in
/// the way the text comes, from below for a newer digest and from above for an older one, as the old ones roll away the
/// other way, all turned in a close perspective, over 0.2 s, eased out. A right-to-left title changes at once.
@MainActor
final class AgentPinnedTitleView: UIView {
    // CSS's `perspective(10px) translateY(±10px) rotateX(±30deg)`
    private enum Metrics {
        static let duration: CFTimeInterval = 0.2
        static let rollDistance: CGFloat = 10
        static let rollAngle: CGFloat = .pi / 6
        static let perspective: CGFloat = 10
        static let keyframeCount = 24
    }

    var font: UIFont = .systemFont(ofSize: 15, weight: .medium) {
        didSet { label.font = font }
    }

    var textColor: UIColor = .label {
        didSet { label.textColor = textColor }
    }

    private(set) var text = ""
    private let label = UILabel()
    /// A label per character while the title rolls
    private var rollingView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = font
        label.textColor = textColor
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    func setText(_ text: String, isFromBelow: Bool, isAnimated: Bool) {
        guard text != self.text else { return }
        let previous = self.text
        self.text = text
        label.text = text
        rollingView?.removeFromSuperview()
        rollingView = nil
        label.isHidden = false
        guard isAnimated, !previous.isEmpty, window != nil, effectiveUserInterfaceLayoutDirection == .leftToRight
        else { return }
        let kept = String(text.commonPrefix(with: previous))
        let rollingView = UIView(frame: bounds)
        rollingView.isUserInteractionEnabled = false
        rollingView.clipsToBounds = true
        let keptWidth = Self.measure(kept, font: font)
        rollingView.addSubview(makeLabel(kept, x: 0, width: keptWidth))
        for (character, x) in Self.layOut(previous.dropFirst(kept.count), from: keptWidth, font: font) {
            let oldLabel = makeLabel(String(character), x: x, width: Self.measure(String(character), font: font))
            rollingView.addSubview(oldLabel)
            roll(oldLabel, isAppearing: false, isOffBelow: !isFromBelow)
        }
        for (character, x) in Self.layOut(text.dropFirst(kept.count), from: keptWidth, font: font) {
            let newLabel = makeLabel(String(character), x: x, width: Self.measure(String(character), font: font))
            rollingView.addSubview(newLabel)
            roll(newLabel, isAppearing: true, isOffBelow: isFromBelow)
        }
        addSubview(rollingView)
        self.rollingView = rollingView
        label.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.duration) { [weak self, weak rollingView] in
            guard let self, let rollingView, self.rollingView === rollingView else { return }
            rollingView.removeFromSuperview()
            self.rollingView = nil
            self.label.isHidden = false
        }
    }

    private func makeLabel(_ text: String, x: CGFloat, width: CGFloat) -> UILabel {
        let label = UILabel(frame: CGRect(x: x, y: 0, width: ceil(width), height: bounds.height))
        label.text = text
        label.font = font
        label.textColor = textColor
        return label
    }

    /// Rolls a character in from below or above, or away there, through CSS's own interpolation of its transform: the
    /// distance, the angle and the perspective's inverse each change evenly, eased out over the roll
    private func roll(_ label: UILabel, isAppearing: Bool, isOffBelow: Bool) {
        let rolledAt: (Double) -> Double = { isAppearing ? 1 - $0 : $0 }
        label.layer.transform = Self.makeRolledTransform(rolledAt(1), isBelow: isOffBelow)
        label.layer.opacity = isAppearing ? 1 : 0
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = (0...Metrics.keyframeCount).map { step in
            let progress = Double(step) / Double(Metrics.keyframeCount)
            return NSValue(caTransform3D: Self.makeRolledTransform(rolledAt(progress), isBelow: isOffBelow))
        }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = isAppearing ? 0 : 1
        opacity.toValue = isAppearing ? 1 : 0
        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = Metrics.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        label.layer.add(group, forKey: "roll")
    }

    /// `perspective(10px) translateY(±10px) rotateX(±30deg)` rolled by `amount` from none to all of it, below or above
    private static func makeRolledTransform(_ amount: Double, isBelow: Bool) -> CATransform3D {
        let amount = CGFloat(amount)
        var perspective = CATransform3DIdentity
        perspective.m34 = -amount / Metrics.perspective
        let rotation = CATransform3DMakeRotation((isBelow ? -1 : 1) * Metrics.rollAngle * amount, 1, 0, 0)
        let translation = CATransform3DMakeTranslation(0, (isBelow ? 1 : -1) * Metrics.rollDistance * amount, 0)
        return CATransform3DConcat(CATransform3DConcat(rotation, translation), perspective)
    }

    /// The characters of a title's rolling part, each with where it starts
    private static func layOut(_ characters: Substring, from x: CGFloat, font: UIFont) -> [(Character, CGFloat)] {
        var x = x
        return characters.map { character in
            defer { x += measure(String(character), font: font) }
            return (character, x)
        }
    }

    private static func measure(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// The stripe of Telegram Web's pinned message panel, its `PinnedMessageNavigation`, as the web app's bar draws it: a
/// bar per digest in a 36 pt window, the shown one lit over the others, which show at a quarter, and from five digests
/// on the bars scroll to keep the lit one in the window. The lit bar and the bars move over 0.25 s, eased in and out.
@MainActor
final class AgentPinnedStripeView: UIView {
    static let width: CGFloat = 2
    static let height: CGFloat = 36

    private enum Metrics {
        static let spacing: CGFloat = 2
        static let radius: CGFloat = 1
        static let trackAlpha: CGFloat = 0.25
        static let duration: CFTimeInterval = 0.25
    }

    var color: UIColor = .tintColor {
        didSet { updateColors() }
    }

    private let trackLayer = CALayer()
    private let barsLayer = CAShapeLayer()
    private let markContainer = CALayer()
    private let markMask = CAShapeLayer()
    private let markLayer = CALayer()
    private var index = 0
    private var count = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(trackLayer)
        trackLayer.addSublayer(barsLayer)
        trackLayer.addSublayer(markContainer)
        markContainer.mask = markMask
        markContainer.addSublayer(markLayer)
        markLayer.cornerRadius = Metrics.radius
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Moves the lit bar to `index`; a stripe of another count of bars takes its place at once
    func update(index: Int, count: Int, animated: Bool) {
        guard index != self.index || count != self.count else { return }
        let isAnimated = animated && count == self.count
        self.index = index
        self.count = count
        CATransaction.begin()
        CATransaction.setDisableActions(!isAnimated)
        CATransaction.setAnimationDuration(Metrics.duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        layoutBars()
        CATransaction.commit()
    }

    // Telegram Web's `calculateMarkup`, whose `reverseIndex` is the digest's place from the oldest
    private func layoutBars() {
        guard count > 1 else {
            let window = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
            trackLayer.frame = window
            barsLayer.path = nil
            markContainer.frame = window
            markMask.path = UIBezierPath(roundedRect: window, cornerRadius: Metrics.radius).cgPath
            markLayer.frame = window
            return
        }
        let barHeight: CGFloat = count == 2 ? 17 : count == 3 ? 11 : 7.5
        let bars: [CGRect] = count == 3
            ? [(0, 11), (12, 12), (25, 11)].map { CGRect(x: 0, y: $0.0, width: Self.width, height: $0.1) }
            : (0..<count).map {
                CGRect(x: 0, y: CGFloat($0) * (barHeight + Metrics.spacing), width: Self.width, height: barHeight)
            }
        let trackHeight = count <= 3 ? Self.height : barHeight * CGFloat(count) + Metrics.spacing * CGFloat(count - 1)
        let trackShift: CGFloat
        if count <= 4 || index <= 1 {
            trackShift = 0
        } else if index >= count - 2 {
            trackShift = trackHeight - Self.height
        } else {
            trackShift = (barHeight + 4) / 2 + CGFloat(index - 2) * (barHeight + Metrics.spacing)
        }
        let path = UIBezierPath()
        bars.forEach { path.append(UIBezierPath(roundedRect: $0, cornerRadius: Metrics.radius)) }
        let trackBounds = CGRect(x: 0, y: 0, width: Self.width, height: trackHeight)
        trackLayer.frame = trackBounds.offsetBy(dx: 0, dy: -trackShift)
        barsLayer.frame = trackBounds
        barsLayer.path = path.cgPath
        markContainer.frame = trackBounds
        markMask.frame = trackBounds
        markMask.path = path.cgPath
        markLayer.frame = bars[min(max(index, 0), count - 1)]
    }

    private func updateColors() {
        barsLayer.fillColor = color.withAlphaComponent(Metrics.trackAlpha).cgColor
        markLayer.backgroundColor = color.cgColor
    }
}
