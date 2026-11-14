import UIKit
import UIComponents

@MainActor
final class AgentChatTitleView: UIView {
    private let textLabel: UILabel = {
        let label = NavigationHeader2.makeTitleLabel("")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        return label
    }()
    /// The thread emoji is larger than the title, as in the design
    private let iconLabel: UILabel = {
        let label = NavigationHeader2.makeTitleLabel("")
        label.font = .systemFont(ofSize: 22)
        return label
    }()
    /// What the chat is in under its title, as support while support has the chat
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private var currentText: String?
    private var currentIcon: String?
    private(set) var subtitle: String?
    private var outgoingView: UIImageView?
    private var animationStartedAt: CFTimeInterval = 0
    private var iconAnimationStartedAt: CFTimeInterval?
    private var iconOffsetAtStart: CGFloat = 0
    private var iconHorizontalOffset: CGFloat = 0
    private var displayLinkSubscriptionID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .header
        textLabel.isAccessibilityElement = false
        iconLabel.isAccessibilityElement = false
        iconLabel.isHidden = true
        subtitleLabel.isAccessibilityElement = false
        subtitleLabel.isHidden = true
        addSubview(textLabel)
        addSubview(iconLabel)
        addSubview(subtitleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let id = displayLinkSubscriptionID {
            DispatchQueue.main.async {
                AgentDisplayLinkDriver.shared.remove(id)
            }
        }
    }

    var onFittingWidthChange: (() -> Void)?

    /// The width the title needs, icon included
    var fittingWidth: CGFloat {
        let iconWidth = currentIcon == nil ? 0 : ceil(iconLabel.intrinsicContentSize.width)
        let spacing: CGFloat = currentIcon == nil ? 0 : 6
        let titleWidth = iconWidth + spacing + ceil(textLabel.intrinsicContentSize.width)
        return subtitle == nil ? titleWidth : max(titleWidth, ceil(subtitleLabel.intrinsicContentSize.width))
    }

    /// Shows `subtitle` under the title, or the title alone with `nil`
    func setSubtitle(_ subtitle: String?) {
        guard subtitle != self.subtitle else { return }
        self.subtitle = subtitle
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        accessibilityValue = subtitle
        setNeedsLayout()
        onFittingWidthChange?()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The coordinates start at the middle: as the pill grows or shrinks around its middle on its spring, the title
        // stays where it is instead of riding on the pill's leading edge
        let centredOrigin = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2)
        if bounds.origin != centredOrigin {
            bounds.origin = centredOrigin
        }
        let iconSize = iconLabel.intrinsicContentSize
        let textSize = textLabel.intrinsicContentSize
        let iconWidth = currentIcon == nil ? 0 : min(bounds.width, ceil(iconSize.width))
        let spacing = currentIcon == nil ? 0 : min(6, max(0, bounds.width - iconWidth))
        let textWidth = min(max(0, bounds.width - iconWidth - spacing), ceil(textSize.width))
        let width = iconWidth + spacing + textWidth
        var centerX = bounds.midX
        var ancestor = superview
        while let view = ancestor {
            if let navigationBar = view as? UINavigationBar {
                let navigationCenter = CGPoint(x: navigationBar.bounds.inset(by: navigationBar.safeAreaInsets).midX, y: 0)
                centerX = navigationBar.convert(navigationCenter, to: self).x
                break
            }
            ancestor = view.superview
        }
        let subtitleSize = subtitleLabel.intrinsicContentSize
        let subtitleWidth = subtitle == nil ? 0 : min(bounds.width, ceil(subtitleSize.width))
        let rowWidth = max(width, subtitleWidth)
        centerX = min(max(centerX, bounds.minX + rowWidth / 2), bounds.maxX - rowWidth / 2)
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leadingX = centerX - width / 2
        // With a subtitle the two lines share the bar's height, centred together
        let subtitleHeight = subtitle == nil ? 0 : ceil(subtitleSize.height)
        let titleMidY = bounds.midY - subtitleHeight / 2
        textLabel.bounds = CGRect(x: 0, y: 0, width: textWidth, height: ceil(textSize.height))
        textLabel.center = CGPoint(
            x: isRTL ? leadingX + textWidth / 2 : leadingX + iconWidth + spacing + textWidth / 2,
            y: titleMidY
        )
        iconLabel.bounds = CGRect(x: 0, y: 0, width: iconWidth, height: ceil(iconSize.height))
        iconLabel.center = CGPoint(
            x: (isRTL ? leadingX + textWidth + spacing + iconWidth / 2 : leadingX + iconWidth / 2) + iconHorizontalOffset,
            y: titleMidY
        )
        subtitleLabel.bounds = CGRect(x: 0, y: 0, width: subtitleWidth, height: subtitleHeight)
        subtitleLabel.center = CGPoint(x: centerX, y: titleMidY + ceil(textSize.height) / 2 + subtitleHeight / 2)
    }

    /// Copies of the title's labels where they show, for a transition that draws the pill's glass itself. Drawn as
    /// views of their own, they take their colors from where the transition places them, as the title does.
    func makeTransitionCopy() -> UIView {
        layoutIfNeeded()
        let copy = UIView(frame: CGRect(origin: .zero, size: bounds.size))
        copy.bounds = bounds
        copy.isUserInteractionEnabled = false
        copy.clipsToBounds = clipsToBounds
        for label in [textLabel, iconLabel, subtitleLabel] where !label.isHidden {
            let labelCopy = UILabel()
            labelCopy.text = label.text
            labelCopy.font = label.font
            labelCopy.textColor = label.textColor
            labelCopy.textAlignment = label.textAlignment
            labelCopy.lineBreakMode = label.lineBreakMode
            labelCopy.numberOfLines = label.numberOfLines
            labelCopy.adjustsFontSizeToFitWidth = label.adjustsFontSizeToFitWidth
            labelCopy.minimumScaleFactor = label.minimumScaleFactor
            labelCopy.bounds = label.bounds
            labelCopy.center = label.center
            labelCopy.transform = label.transform
            labelCopy.alpha = label.alpha
            copy.addSubview(labelCopy)
        }
        return copy
    }

    static func shouldAnimateChange(previousTitle: String?, title: String, isVisible: Bool, reduceMotion: Bool) -> Bool {
        previousTitle != nil && previousTitle != title && isVisible && !reduceMotion
    }

    func setTitle(_ text: String, icon: String?, animated: Bool) {
        let fullTitle = icon.map { "\($0) \(text)" } ?? text
        let shouldAnimate = Self.shouldAnimateChange(
            previousTitle: accessibilityLabel,
            title: fullTitle,
            isVisible: animated && window != nil && !bounds.isEmpty && !isHidden && alpha > 0,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        guard currentText != text || currentIcon != icon else {
            if !animated || UIAccessibility.isReduceMotionEnabled { cancelAnimation() }
            return
        }

        let iconChanged = currentIcon != icon
        // Capture all visible text, including an interrupted transition, before replacing it.
        let image = shouldAnimate ? captureTitle(excludingIcon: !iconChanged) : nil
        let previousIconX = iconLabel.center.x
        outgoingView?.removeFromSuperview()
        outgoingView = nil
        if !shouldAnimate { cancelAnimation() }

        currentText = text
        currentIcon = icon
        textLabel.text = text
        iconLabel.text = icon
        iconLabel.isHidden = icon == nil
        accessibilityLabel = fullTitle
        iconHorizontalOffset = 0
        setNeedsLayout()
        layoutIfNeeded()
        onFittingWidthChange?()

        guard let image else { return }
        let outgoing = UIImageView(image: image)
        outgoing.frame = bounds
        outgoing.isAccessibilityElement = false
        outgoing.accessibilityElementsHidden = true
        addSubview(outgoing)
        outgoingView = outgoing
        animationStartedAt = CACurrentMediaTime()
        textLabel.alpha = 0
        textLabel.transform = CGAffineTransform(translationX: 0, y: 7)
        iconOffsetAtStart = 0
        if iconChanged {
            iconAnimationStartedAt = icon == nil ? nil : animationStartedAt + 0.1
            iconLabel.alpha = 0
            iconLabel.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        } else if icon != nil {
            iconOffsetAtStart = previousIconX - iconLabel.center.x
            iconHorizontalOffset = iconOffsetAtStart
            iconLabel.center.x = previousIconX
        }
        if displayLinkSubscriptionID == nil {
            displayLinkSubscriptionID = AgentDisplayLinkDriver.shared.add { [weak self] in
                self?.updateAnimation()
            }
        }
    }

    func cancelAnimation() {
        if let displayLinkSubscriptionID {
            AgentDisplayLinkDriver.shared.remove(displayLinkSubscriptionID)
            self.displayLinkSubscriptionID = nil
        }
        outgoingView?.removeFromSuperview()
        outgoingView = nil
        textLabel.alpha = 1
        textLabel.transform = .identity
        iconLabel.alpha = 1
        iconLabel.transform = .identity
        iconAnimationStartedAt = nil
        iconHorizontalOffset = 0
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelAnimation() }
    }

    private func captureTitle(excludingIcon: Bool) -> UIImage {
        layoutIfNeeded()
        let wasHidden = iconLabel.isHidden
        if excludingIcon { iconLabel.isHidden = true }
        defer { iconLabel.isHidden = wasHidden }
        return UIGraphicsImageRenderer(size: bounds.size).image { context in
            layer.render(in: context.cgContext)
        }
    }

    private func updateAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            cancelAnimation()
            return
        }
        let now = CACurrentMediaTime()
        let elapsed = now - animationStartedAt
        let oldFraction = CGFloat(min(1, max(0, elapsed / 0.15)))
        let outgoingProgress = oldFraction * oldFraction
        outgoingView?.alpha = 1 - outgoingProgress
        outgoingView?.transform = CGAffineTransform(translationX: 0, y: -7 * outgoingProgress)

        let newFraction = CGFloat(min(1, max(0, (elapsed - 0.03) / 0.22)))
        let incomingProgress = 1 - (1 - newFraction) * (1 - newFraction)
        textLabel.alpha = incomingProgress
        textLabel.transform = CGAffineTransform(translationX: 0, y: 7 * (1 - incomingProgress))
        iconHorizontalOffset = iconOffsetAtStart * (1 - incomingProgress)
        setNeedsLayout()
        layoutIfNeeded()

        if let iconAnimationStartedAt {
            let fraction = CGFloat(min(1, max(0, (now - iconAnimationStartedAt) / 0.17)))
            let offset = fraction - 1
            let overshoot = offset * offset * (2.5 * offset + 1.5) + 1
            let scale = 0.6 + 0.4 * overshoot
            iconLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
            iconLabel.alpha = 1 - (1 - fraction) * (1 - fraction)
        }
        if elapsed >= 0.27 { cancelAnimation() }
    }
}
