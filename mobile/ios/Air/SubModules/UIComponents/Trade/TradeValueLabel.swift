import Combine
import CoreText
import UIKit
import WalletContext

/// Small amounts use retained character layers; no display link or view rebuilding while animating.
public final class TradeValueLabel: UIView {
    private let content = UIView()
    private var characters: [String: UILabel] = [:]
    private var positions: [String: CGRect] = [:]
    private var naturalSize = CGSize.zero
    public private(set) var text = ""
    private var font: UIFont
    private var color: UIColor
    private var outgoing: [UILabel] = []

    public init(font: UIFont, color: UIColor) {
        self.font = font
        self.color = color
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(content)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override var intrinsicContentSize: CGSize { naturalSize }
    public override func sizeThatFits(_ size: CGSize) -> CGSize { naturalSize }

    public func setText(_ text: String, color: UIColor? = nil, animated: Bool) {
        let color = color ?? self.color
        guard text != self.text || !color.isEqual(self.color) else { return }
        let oldText = self.text
        let oldCharacters = characters
        self.text = text
        self.color = color
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        naturalSize = CGSize(width: ceil(CTLineGetTypographicBounds(line, nil, nil, nil)), height: ceil(font.lineHeight))
        let entries = Array(text)
        let firstNumber = entries.firstIndex(where: \.isWholeNumber)
        let lastNumber = entries.lastIndex(where: \.isWholeNumber)
        let separator = Character(Locale.forNumberFormatters.decimalSeparator ?? ".")
        let decimal = entries.firstIndex(of: separator)
        var offset = 0
        var nextCharacters: [String: UILabel] = [:]
        var nextPositions: [String: CGRect] = [:]
        let animates = animated && TradeMotion.enabled && !oldText.isEmpty && window != nil
        for (index, character) in entries.enumerated() {
            let key: String
            if let firstNumber, let lastNumber, index >= firstNumber && index <= lastNumber {
                if index == decimal { key = "decimal" }
                else if let decimal, index > decimal { key = "fraction.\(index - decimal)" }
                else { key = "integer.\((decimal ?? (lastNumber + 1)) - index)" }
            } else if let lastNumber, index > lastNumber { key = "suffix.\(index - lastNumber)" }
            else { key = "prefix.\(index)" }
            let string = String(character)
            let x = CTLineGetOffsetForStringIndex(line, offset, nil)
            offset += string.utf16.count
            let end = CTLineGetOffsetForStringIndex(line, offset, nil)
            let frame = CGRect(x: x, y: 0, width: max(0, end - x), height: naturalSize.height)
            let label: UILabel
            if let previous = oldCharacters[key], previous.text == string {
                label = previous
            } else {
                label = UILabel()
                label.font = font
                label.text = string
                label.textAlignment = .center
                label.isAccessibilityElement = false
                content.addSubview(label)
                TradeMotion.place(label, in: frame)
                if animates {
                    label.alpha = 0
                    label.transform = CGAffineTransform(translationX: 0, y: font.lineHeight * 0.35).scaledBy(x: 0.9, y: 0.9)
                }
            }
            label.textColor = color
            nextCharacters[key] = label
            nextPositions[key] = frame
        }
        let departing = oldCharacters.filter { nextCharacters[$0.key] !== $0.value }.map(\.value)
        characters = nextCharacters
        positions = nextPositions
        outgoing += departing
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        TradeMotion.animate(animates, changes: {
            for (key, label) in nextCharacters {
                if let frame = nextPositions[key] { TradeMotion.place(label, in: frame) }
                label.alpha = 1
                label.transform = .identity
            }
            for label in departing {
                label.alpha = 0
                label.transform = CGAffineTransform(translationX: 0, y: -self.font.lineHeight * 0.35).scaledBy(x: 0.9, y: 0.9)
            }
        }, completion: { [weak self] _ in
            departing.forEach { $0.removeFromSuperview() }
            self?.outgoing.removeAll { label in departing.contains { $0 === label } }
        })
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(1, bounds.width / max(1, naturalSize.width))
        // Character layers own their motion, just as the hero amount renderer does.
        // The canvas fits its final width without inheriting the form's layout animation.
        UIView.performWithoutAnimation {
            content.bounds = CGRect(origin: .zero, size: naturalSize)
            content.center = CGPoint(x: naturalSize.width * scale / 2, y: bounds.midY)
            content.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            outgoing.forEach { $0.removeFromSuperview() }
            outgoing.removeAll()
            for (key, label) in characters {
                label.layer.removeAllAnimations()
                label.alpha = 1
                label.transform = .identity
                if let frame = positions[key] { TradeMotion.place(label, in: frame) }
            }
        }
    }
}

/// Core Animation drives the pending-quote shine without evaluating the screen each frame.
public final class TradeShineView: UIView {
    public let content: UIView
    private let gradient = CAGradientLayer()
    private var isActive = false
    private let usesAutoLayout: Bool
    private var motionSubscription: AnyCancellable?

    public init(content: UIView, usesAutoLayout: Bool = false) {
        self.content = content
        self.usesAutoLayout = usesAutoLayout
        super.init(frame: .zero)
        addSubview(content)
        if usesAutoLayout {
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.cgColor]
        let environment = CardBackgroundAnimationEnvironment.shared
        motionSubscription = Publishers.CombineLatest4(environment.$applicationActive, environment.$animationsEnabled,
            environment.$lowPowerMode, environment.$reduceMotion).sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.refreshMotionPolicy() }
            }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func setActive(_ active: Bool, animated: Bool) {
        if active != isActive {
            isActive = active
            TradeMotion.animate(animated) { self.content.alpha = active ? 0.55 : 1 }
        }
        updateAnimation()
    }

    public func refreshMotionPolicy() { updateAnimation() }

    private func updateAnimation() {
        guard isActive, TradeMotion.enabled, window != nil else {
            gradient.removeAllAnimations()
            layer.mask = nil
            return
        }
        layer.mask = gradient
        guard gradient.animation(forKey: "shine") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "locations")
        animation.values = [[-0.6, -0.3, 0], [1, 1.3, 1.6], [1, 1.3, 1.6]]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = 2
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "shine")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if !usesAutoLayout { TradeMotion.place(content, in: bounds) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }
}
