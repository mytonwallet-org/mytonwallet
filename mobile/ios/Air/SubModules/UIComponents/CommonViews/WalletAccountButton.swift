import UIKit
import WalletContext
import WalletCore

@MainActor
public final class WalletAccountButton: UIControl {
    private let iconView = IconView(size: 36)
    public var avatarFrame: CGRect { iconView.convert(iconView.bounds, to: self) }
    private let activityIndicator = UIView()
    private let activityIndicatorImage = UIImageView(image: .airBundle("AccountActivityIndicator"))
    private var isUpdating = false
    private var showsToolbarContent = true
    private var materialEffect: UIVisualEffect?

    public func setToolbarAppearance(showsBackground: Bool, showsContent: Bool) {
        let contentVisibilityChanged = showsToolbarContent != showsContent
        showsToolbarContent = showsContent
        if showsBackground != (glassView.effect != nil) {
            glassView.effect = showsBackground ? materialEffect : nil
        }
        iconView.alpha = showsContent ? 1 : 0
        activityIndicator.alpha = showsContent && isUpdating ? 1 : 0
        if contentVisibilityChanged {
            if showsContent && isUpdating && window != nil {
                startIndicatorRotation()
            } else {
                activityIndicatorImage.layer.removeAnimation(forKey: "rotation")
            }
        }
    }
    /// Fades and scales the avatar for a host's handoff morph, apart from `setToolbarAppearance`'s visibility
    public func setHandoffContent(alpha: CGFloat, scale: CGFloat) {
        glassView.contentView.alpha = alpha
        let transform = scale == 1 ? CGAffineTransform.identity : CGAffineTransform(scaleX: scale, y: scale)
        iconView.transform = transform
        activityIndicator.transform = transform
    }

    private var visibilityAnimationId = 0
    private let glassView: UIVisualEffectView = {
        let view: UIVisualEffectView
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            view = UIVisualEffectView(effect: effect)
            view.cornerConfiguration = .capsule()
        } else {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            view.layer.cornerRadius = 44 / 2
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
        }
        return view
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        materialEffect = glassView.effect
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "tab_settings_button"

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isAccessibilityElement = false
        addSubview(glassView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        glassView.contentView.addSubview(iconView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.isUserInteractionEnabled = false
        activityIndicator.isAccessibilityElement = false
        activityIndicator.alpha = 0
        activityIndicator.isHidden = true
        glassView.contentView.addSubview(activityIndicator)
        activityIndicatorImage.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.addSubview(activityIndicatorImage)
        NSLayoutConstraint.activate([
            activityIndicatorImage.leadingAnchor.constraint(equalTo: activityIndicator.leadingAnchor),
            activityIndicatorImage.trailingAnchor.constraint(equalTo: activityIndicator.trailingAnchor),
            activityIndicatorImage.topAnchor.constraint(equalTo: activityIndicator.topAnchor),
            activityIndicatorImage.bottomAnchor.constraint(equalTo: activityIndicator.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: glassView.contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            activityIndicator.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            activityIndicator.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])

        if #available(iOS 26, iOSApplicationExtension 26, *) {
            glassView.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(glassTapped))
            )
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var account: MAccount?

    /// A copy of the avatar, for a transition that draws the button's glass itself
    public func makeContentCopy() -> UIView {
        let view = IconView(size: 36)
        view.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        view.config(with: account)
        return view
    }

    public func configure(account: MAccount?) {
        self.account = account
        iconView.config(with: account)
        accessibilityLabel = lang("Settings")
    }

    public func setUpdateStatus(_ state: WalletUpdateStatus, animated: Bool) {
        switch state {
        case .waitingForNetwork:
            accessibilityValue = lang("Waiting for network…")
        case .updating:
            accessibilityValue = lang("Updating…")
        case .updated:
            accessibilityValue = nil
        }

        let isUpdating = state != .updated
        guard self.isUpdating != isUpdating else { return }
        self.isUpdating = isUpdating
        visibilityAnimationId += 1
        let animationId = visibilityAnimationId
        if isUpdating {
            activityIndicator.isHidden = false
            if showsToolbarContent { startIndicatorRotation() }
        }

        let opacity = activityIndicator.layer.presentation()?.opacity ?? activityIndicator.layer.opacity
        let targetOpacity: Float = isUpdating && showsToolbarContent ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.visibilityAnimationId == animationId, !self.isUpdating else { return }
            self.activityIndicator.isHidden = true
            self.activityIndicatorImage.layer.removeAnimation(forKey: "rotation")
        }
        activityIndicator.layer.opacity = targetOpacity
        if animated && !UIAccessibility.isReduceMotionEnabled {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = targetOpacity
            fade.duration = 0.3
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            activityIndicator.layer.add(fade, forKey: "opacity")
        } else {
            activityIndicator.layer.removeAnimation(forKey: "opacity")
        }
        CATransaction.commit()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isUpdating, showsToolbarContent {
            startIndicatorRotation()
        } else if window == nil {
            activityIndicatorImage.layer.removeAnimation(forKey: "rotation")
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if #unavailable(iOS 26) {
            glassView.layer.cornerRadius = bounds.height / 2
        }
    }

    private func startIndicatorRotation() {
        guard activityIndicatorImage.layer.animation(forKey: "rotation") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation")
        animation.fromValue = 0
        animation.beginTime = activityIndicatorImage.layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.toValue = 2 * Double.pi
        animation.duration = 0.625
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        activityIndicatorImage.layer.add(animation, forKey: "rotation")
    }

    @objc private func glassTapped() {
        sendActions(for: .touchUpInside)
    }
}
