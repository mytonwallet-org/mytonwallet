import UIKit
import UIComponents
import WalletContext

/// The glass "scroll to latest" button, built like Telegram's chat navigation button: the button as a whole fades and
/// scales between 0.2 and 1 on Telegram's spring as it appears and disappears, while its interactive glass inside
/// stretches under the finger on its own. Glass ignores alpha, so it materializes and dematerializes with the fade.
final class AgentScrollToBottomButton: UIControl {
    /// As large as the composer's microphone circle, with the design's 40 pt button scaled up to it
    nonisolated static let size: CGFloat = AgentComposerMetrics.microphoneSize
    /// The chevron is drawn at 80% of the design's chevron scaled with the button
    private static let scale: CGFloat = size / 40 * 0.8
    /// The design's 18 × 9 pt chevron with its 2 pt stroke, scaled
    static let chevronImageSize = CGSize(width: 20 * scale, height: 11 * scale)
    /// The chevron sits 2 pt below the button's center in the design, scaled with it
    static let chevronOffset: CGFloat = 2 * scale

    private static let chevronColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(hex: "#1A1A1A")
    }
    static let hiddenScale: CGFloat = 0.2
    /// Telegram's `.animated(duration: 0.3, curve: .spring)`: a critically damped spring
    static let animationDuration: TimeInterval = 0.3
    /// The glass is gone by the time the shrinking button gets small
    private static let dematerializeDuration: TimeInterval = 0.15

    /// Scaled as the button appears and disappears, so the glass's own stretch under the finger keeps its transform
    private let containerView = UIView()
    private let glassView: WGlassView?
    private let plainBackgroundView: UIView?
    let chevronView = UIImageView(image: AgentScrollToBottomButton.chevronImage)
    private var visibilityGeneration = 0
    private(set) var isButtonVisible = false

    override init(frame: CGRect) {
        glassView = Self.makeGlassView()
        plainBackgroundView = glassView == nil ? UIView() : nil
        super.init(frame: frame)
        setupViews()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.size, height: Self.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let transform = containerView.transform
        containerView.transform = .identity
        containerView.frame = bounds
        containerView.transform = transform
        glassView?.frame = containerView.bounds
        plainBackgroundView?.frame = containerView.bounds
        plainBackgroundView?.layer.cornerRadius = containerView.bounds.height / 2
        let chevronSize = Self.chevronImageSize
        chevronView.bounds = CGRect(origin: .zero, size: chevronSize)
        chevronView.center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY + Self.chevronOffset)
    }

    func applyTheme() {
        chevronView.tintColor = Self.chevronColor
        if let plainBackgroundView {
            Self.stylePlainBackground(plainBackgroundView)
        }
    }

    /// The glass of the chat's floating buttons, this one and the floating microphone: Liquid Glass, or nil before it,
    /// where they are a plain circle
    static func makeGlassView() -> WGlassView? {
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            return WGlassView(cornerRadius: nil)
        }
        return nil
    }

    /// The plain circle of the chat's floating buttons without Liquid Glass, with a soft shadow
    static func stylePlainBackground(_ view: UIView) {
        view.backgroundColor = .air.groupedItem
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    func setButtonVisible(_ isVisible: Bool, animated: Bool) {
        guard isVisible != isButtonVisible else { return }
        isButtonVisible = isVisible
        isUserInteractionEnabled = isVisible
        accessibilityElementsHidden = !isVisible
        visibilityGeneration += 1
        let generation = visibilityGeneration

        let targetScale = isVisible ? 1 : Self.hiddenScale
        let applyGlass = {
            if let glassView = self.glassView {
                glassView.setMaterialized(isVisible)
            } else {
                self.containerView.alpha = isVisible ? 1 : 0
            }
        }
        let apply = {
            self.containerView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
            self.chevronView.alpha = isVisible ? 1 : 0
            if isVisible { applyGlass() }
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled, window != nil else {
            UIView.performWithoutAnimation {
                apply()
                applyGlass()
            }
            isHidden = !isVisible
            return
        }
        isHidden = false
        if !isVisible {
            // Glass doesn't fade with an alpha: it dematerializes, which takes longer than the shrink. Left to the
            // shrink's spring, a small dark drop of it would stay behind until the button hides.
            UIView.animate(
                withDuration: Self.dematerializeDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: applyGlass
            )
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, generation == self.visibilityGeneration, !self.isButtonVisible else { return }
            self.isHidden = true
        }
        if #available(iOS 17.0, *) {
            UIView.animate(
                springDuration: Self.animationDuration,
                bounce: 0,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply,
                completion: completion
            )
        } else {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply,
                completion: completion
            )
        }
    }

    private func setupViews() {
        isHidden = true
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = lang("Scroll To Bottom")

        containerView.isUserInteractionEnabled = true
        addSubview(containerView)
        let contentHost: UIView
        if let glassView {
            containerView.addSubview(glassView)
            contentHost = glassView.contentView
        } else if let plainBackgroundView {
            containerView.addSubview(plainBackgroundView)
            contentHost = containerView
        } else {
            contentHost = containerView
        }
        chevronView.contentMode = .center
        chevronView.isUserInteractionEnabled = false
        contentHost.addSubview(chevronView)

        // The tap goes to the glass itself, which stretches under the finger as Telegram's does
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let tapTarget: UIView = glassView ?? containerView
        tapTarget.addGestureRecognizer(tap)

        UIView.performWithoutAnimation {
            containerView.transform = CGAffineTransform(scaleX: Self.hiddenScale, y: Self.hiddenScale)
            chevronView.alpha = 0
            glassView?.setMaterialized(false)
            if glassView == nil { containerView.alpha = 0 }
        }
    }

    @objc private func handleTap() {
        guard isButtonVisible else { return }
        sendActions(for: .touchUpInside)
    }

    private static let chevronImage = AgentGlyph.makeImage(size: chevronImageSize, lineWidth: 2 * scale, strokes: [
        [CGPoint(x: 1 * scale, y: 1 * scale), CGPoint(x: 10 * scale, y: 10 * scale), CGPoint(x: 19 * scale, y: 1 * scale)],
    ])
}
