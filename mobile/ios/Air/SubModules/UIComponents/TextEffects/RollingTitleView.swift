import UIKit

/// A one-line title that rolls to a new one as Telegram Web's `AnimatedCounter` does: the part both titles start with,
/// as "November " of November 9 and November 10, stays, and each character after it rolls in from below or above as the
/// old ones roll away the other way, all turned in a close perspective, over 0.2 s, eased out. A right-to-left title
/// changes at once.
@MainActor
public final class RollingTitleView: UIView {
    // CSS's `perspective(10px) translateY(±10px) rotateX(±30deg)`
    private enum Metrics {
        static let duration: CFTimeInterval = 0.2
        static let rollDistance: CGFloat = 10
        static let rollAngle: CGFloat = .pi / 6
        static let perspective: CGFloat = 10
        static let keyframeCount = 24
    }

    public var font: UIFont = .systemFont(ofSize: 15, weight: .medium) {
        didSet { label.font = font }
    }

    public var textColor: UIColor = .label {
        didSet { label.textColor = textColor }
    }

    public private(set) var text = ""
    private let label = UILabel()
    /// A label per character while the title rolls
    private var rollingView: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = font
        label.textColor = textColor
        addSubview(label)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    public func setText(_ text: String, isFromBelow: Bool, isAnimated: Bool) {
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
        CATransaction.begin()
        // The roll ends with its animations, however fast the layers' time runs
        CATransaction.setCompletionBlock { [weak self, weak rollingView] in
            MainActor.assumeIsolated {
                guard let self, let rollingView, self.rollingView === rollingView else { return }
                rollingView.removeFromSuperview()
                self.rollingView = nil
                self.label.isHidden = false
            }
        }
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
        CATransaction.commit()
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
