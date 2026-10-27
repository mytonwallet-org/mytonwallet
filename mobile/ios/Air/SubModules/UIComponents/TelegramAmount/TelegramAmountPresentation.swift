import UIKit

/// A visual layer over a native amount editor. Editing and accessibility stay with UITextField.
public final class TelegramAmountPresentation: UIView {
    public struct TextRun {
        public enum Part: Equatable { case number, prefix, suffix }
        let text: NSAttributedString
        let origin: CGPoint
        let part: Part

        public init(text: NSAttributedString, origin: CGPoint, part: Part = .number) {
            self.text = text
            self.origin = origin
            self.part = part
        }
    }

    private let canvas = TelegramAmountCanvas()
    private let caretView = UIView()
    private let motion = TelegramAmountMotion(liquid: true)
    private var displayLink: CADisplayLink?
    private var frameDuration = 1.0 / 120.0
    private var previousWidth: CGFloat?
    private var wasPlaceholder = true
    private var caretFrom = CGRect.zero
    private var caretTo = CGRect.zero
    private var active = false
    private var animated = true
    private var caretEnabled = false
    private let blinkKey = "telegramAmountCaretBlink"
    public var onPresentationChanged: ((Bool) -> Void)?
    public private(set) var isPresentingText = false
    public var showsCaret: Bool { !caretView.isHidden }
    public var caretFrame: CGRect { caretView.frame }
    public var isAnimating: Bool { displayLink != nil }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = false
        canvas.isHidden = true
        addSubview(canvas)
        if #available(iOS 17.4, *) {
            let cursor = UIStandardTextCursorView()
            cursor.tintColor = .white
            cursor.clipsToBounds = true
            caretView.mask = cursor
        }
        caretView.isHidden = true
        addSubview(caretView)
        canvas.onRenderFailure = { [weak self] in self?.finishMotion() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { displayLink?.invalidate() }

    public func configure(active: Bool, animated: Bool) {
        guard self.active != active || self.animated != animated else { return }
        self.active = active
        self.animated = animated
        if !active || !animated { finishMotion() }
        updateCaret()
    }

    public func update(runs: [TextRun], decimalSeparator: String, caret: CGRect?,
                       caretColor: UIColor, placeholder: Bool, animated: Bool,
                       switchesUnit: Bool = false, increasesValue: Bool = true, replacesValue: Bool = false) {
        let now = CACurrentMediaTime()
        let glyphs = runs.flatMap { run -> [TelegramAmountGlyph] in
            let group: TelegramAmountGlyph.Group
            switch run.part {
            case .number: group = .integer
            case .prefix: group = .prefix
            case .suffix: group = .suffix
            }
            var glyphs = resolvedGlyphs(text: run.text, origin: run.origin, group: group)
            if run.part == .number {
                let fraction = (run.text.string as NSString).range(of: decimalSeparator).location
                var offset = 0
                for i in glyphs.indices {
                    if fraction != NSNotFound && offset >= fraction { glyphs[i].group = .fraction }
                    offset += glyphs[i].text.utf16.count
                }
            }
            return glyphs
        }
        canvas.prepareGlyphs(glyphs)
        let widthChanged = previousWidth != nil && previousWidth != bounds.width
        let canAnimate = animated && self.animated && active && window != nil && canvas.isAvailable
            && previousWidth != nil && !widthChanged
        if glyphs != motion.target {
            caretFrom = caretView.isHidden ? (caret ?? .zero) : caretView.frame
            caretTo = caret ?? .zero
            let timing = canAnimate ? TelegramAmountMotionTiming(spin: switchesUnit, up: increasesValue,
                                                                 start: now, replacesValue: replacesValue) : nil
            motion.update(glyphs, width: bounds.width, timing: timing, at: now,
                frameDuration: frameDuration, fromPlaceholder: wasPlaceholder && !placeholder)
        } else if !motion.isAnimating(at: now) || (caret ?? .zero) != caretTo {
            if (caret ?? .zero) != caretTo { finishMotion() }
            caretFrom = caret ?? .zero
            caretTo = caret ?? .zero
        }
        previousWidth = bounds.width
        wasPlaceholder = placeholder
        caretEnabled = caret != nil
        caretView.backgroundColor = caretColor
        if widthChanged || !active || !self.animated { finishMotion() }
        if motion.isAnimating(at: now) {
            renderFrame(at: now)
            if isPresentingText { startDisplayLink() }
        } else {
            finishMotion()
        }
        updateCaret()
    }

    func resolvedGlyphs(text: NSAttributedString, origin: CGPoint, group: TelegramAmountGlyph.Group) -> [TelegramAmountGlyph] {
        // Metal has no UIKit drawing context in which to resolve dynamic colors.
        let resolved = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { color, range, _ in
            if let color = color as? UIColor {
                resolved.addAttribute(.foregroundColor, value: color.resolvedColor(with: traitCollection), range: range)
            }
        }
        return TelegramAmountGlyph.text(resolved, origin: origin, group: group)
    }

    public func cancelInteraction() {
        caretEnabled = false
        finishMotion()
        updateCaret()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            previousWidth = nil
            cancelInteraction()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            let maximum = Float(window?.screen.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maximum, preferred: maximum)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @MainActor private final class DisplayLinkTarget {
        weak var view: TelegramAmountPresentation?
        init(_ view: TelegramAmountPresentation) { self.view = view }
        @objc func tick(_ link: CADisplayLink) {
            guard let view else { link.invalidate(); return }
            let duration = link.targetTimestamp - link.timestamp
            view.frameDuration += (duration - view.frameDuration) * 0.3
            view.renderFrame(at: CACurrentMediaTime())
        }
    }

    private func renderFrame(at now: Double) {
        guard active, animated, window != nil, motion.isAnimating(at: now) else {
            finishMotion()
            return
        }
        canvas.frame = CGRect(x: -32, y: -32, width: ceil(bounds.width / 64) * 64 + 64, height: bounds.height + 64)
        canvas.frameDuration = frameDuration
        let sprites = motion.frame(at: now, frameDuration: frameDuration).map { sprite in
            var sprite = sprite
            sprite.glyph.position.x += 32
            sprite.glyph.position.y += 32
            return sprite
        }
        canvas.isHidden = false
        canvas.update(sprites: sprites, isAnimating: true)
        guard canvas.hasFrame else {
            finishMotion()
            return
        }
        setPresentingText(true)
        let p = motion.timing?.layoutProgress(at: now) ?? 1
        var caret = telegramAmountMotionRect(caretFrom, caretTo, p)
        caret.origin.x = motion.caretPosition(at: now, fromX: caretFrom.midX, toX: caretTo.midX) - caret.width / 2
        updateCaretFrame(caret)
    }

    private func finishMotion() {
        displayLink?.invalidate()
        displayLink = nil
        motion.finish()
        canvas.finishMotion()
        canvas.isHidden = true
        setPresentingText(false)
        updateCaretFrame(caretTo)
    }

    private func updateCaretFrame(_ frame: CGRect) {
        caretView.frame = frame
        caretView.layer.cornerRadius = frame.width / 2
        guard let mask = caretView.mask, frame.width > 0, frame.height > 0 else { return }
        // UIKit fixes its stroke width. Stretch its center strip as an alpha mask
        // so only the system blink, not its geometry, affects our caret.
        mask.bounds = CGRect(x: 0, y: 0, width: 1, height: frame.height)
        mask.center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        mask.transform = CGAffineTransform(scaleX: frame.width, y: 1)
    }

    private func setPresentingText(_ value: Bool) {
        guard isPresentingText != value else { return }
        isPresentingText = value
        onPresentationChanged?(value)
    }

    private func updateCaret() {
        let visible = caretEnabled && active && window != nil && caretTo.height > 0
        caretView.isHidden = !visible
        if #available(iOS 17.4, *), let cursor = caretView.mask as? UIStandardTextCursorView {
            cursor.isBlinking = visible && animated
            return
        }
        guard visible, animated else {
            caretView.layer.removeAnimation(forKey: blinkKey)
            caretView.alpha = 1
            return
        }
        guard caretView.layer.animation(forKey: blinkKey) == nil else { return }
        // Match UIKit's one-second stepped blink on older iOS versions.
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0.75, 0.5, 0.25, 0, 0, 0.25, 0.5, 0.75, 1]
        animation.keyTimes = [0, 0.5, 0.5375, 0.575, 0.6125, 0.65, 0.85, 0.8875, 0.925, 0.9625, 1]
            .map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = 1
        animation.repeatCount = .infinity
        caretView.layer.add(animation, forKey: blinkKey)
    }

    public func resetCaretBlink() {
        if #available(iOS 17.4, *), let cursor = caretView.mask as? UIStandardTextCursorView {
            cursor.resetBlinkAnimation()
        } else {
            caretView.layer.removeAnimation(forKey: blinkKey)
        }
    }
}
