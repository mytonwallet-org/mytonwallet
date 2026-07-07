import Kingfisher
import UIKit
import WalletCore

@MainActor
public final class ToastController {

    private weak var containerView: UIView?

    private var toastView: ToastView?
    private var toastHider: DispatchWorkItem?
    private var currentToastIdentity: ToastIdentity?

    /// Note this does not include action handler, because it is not equatable.
    /// In practice this should be fine - things like this are not going to be updated.
    private struct ToastIdentity: Equatable {
        let style: ToastStyle
        let icon: ToastIcon?
        let message: String
        let actionTitle: String?
    }

    public init(containerView: UIView) {
        self.containerView = containerView
    }

    public func showToast(_ config: ToastConfig) {
        guard let containerView else { return }

        let identity = ToastIdentity(style: config.style, icon: config.icon, message: config.message, actionTitle: config.actionTitle)

        if let toastView {
            if currentToastIdentity != identity {
                currentToastIdentity = identity
                toastView.update(config: config)
            } else {
                toastView.replayIcon()
            }
            rescheduleToastHider(duration: config.duration)
            return
        }

        currentToastIdentity = identity

        let toastView = ToastView(config: config) { [weak self] in
            self?.toastHider?.perform()
        }
        self.toastView = toastView

        toastView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(toastView)
        NSLayoutConstraint.activate([
            toastView.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor, constant: -12),
            toastView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12).withPriority(.defaultHigh),
            toastView.leftAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.leftAnchor, constant: 24),
            toastView.rightAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.rightAnchor, constant: -24),
        ])

        containerView.layoutIfNeeded()

        switch config.transition {
        case .fadeIn:
            UIView.animate(withDuration: 0.3) {
                self.toastView?.alpha = 1
                containerView.layoutIfNeeded()
            }
        case .floatUp:
            let hiddenOffset = max(70, toastView.bounds.height + 12 + containerView.safeAreaInsets.bottom)
            let duration = min(0.8, 0.5 * hiddenOffset / 70)
            toastView.transform = CGAffineTransform(translationX: 0, y: hiddenOffset).scaledBy(x: 0.9, y: 0.9)
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.5,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                toastView.alpha = 1
                toastView.transform = .identity
            }
        }

        rescheduleToastHider(duration: config.duration)
    }

    private func rescheduleToastHider(duration: Double) {
        toastHider?.cancel()
        let toastHider = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hideToastView()
        }
        self.toastHider = toastHider
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: toastHider)
    }

    private func hideToastView() {
        currentToastIdentity = nil
        guard let toastView else {
            return
        }
        UIView.animate(withDuration: 0.3) {
            toastView.alpha = 0
        } completion: { _ in
            toastView.removeFromSuperview()
        }
        self.toastView = nil
    }
}

public class ToastView: UIView {
    private var blurView: WBlurView!
    private var dismiss: (() -> ())?
    private var contentView: ToastContentView?
    private var heightConstraint: NSLayoutConstraint!

    init(config: ToastConfig, dismiss: (() -> ())? = nil) {
        self.dismiss = dismiss
        super.init(frame: .zero)
        alpha = 0
        backgroundColor = .clear

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 1)

        blurView = WBlurView.attach(to: self, background: .air.toastBackground)
        blurView.layer.masksToBounds = true

        heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        heightConstraint = heightAnchor.constraint(equalToConstant: 50)

        setContent(config: config, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    func update(config: ToastConfig) {
        setContent(config: config, animated: true)
    }

    func replayIcon() {
        contentView?.replayIcon()
    }

    private func setContent(config: ToastConfig, animated: Bool) {
        let cornerRadius: CGFloat = config.style == .large ? 25 : 16

        let oldContent = contentView
        let newContent = ToastContentView(config: config, dismiss: dismiss)
        newContent.translatesAutoresizingMaskIntoConstraints = false
        if let oldContent {
            insertSubview(newContent, belowSubview: oldContent)
        } else {
            addSubview(newContent)
        }
        NSLayoutConstraint.activate([
            newContent.topAnchor.constraint(equalTo: topAnchor),
            newContent.bottomAnchor.constraint(equalTo: bottomAnchor),
            newContent.leadingAnchor.constraint(equalTo: leadingAnchor),
            newContent.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        contentView = newContent

        let applyStyle = {
            self.blurView.layer.cornerRadius = cornerRadius
            self.layer.cornerRadius = cornerRadius
            self.layer.shadowRadius = cornerRadius
        }

        guard animated, let oldContent, let superview else {
            applyStyle()
            oldContent?.removeFromSuperview()
            return
        }

        let oldHeight = bounds.height
        let fitting = newContent.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let targetHeight = max(50, fitting.height)

        heightConstraint.constant = oldHeight
        heightConstraint.isActive = true
        UIView.performWithoutAnimation {
            applyStyle()
            superview.layoutIfNeeded()
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.heightConstraint.constant = targetHeight
            oldContent.alpha = 0
            superview.layoutIfNeeded()
        } completion: { _ in
            oldContent.removeFromSuperview()
        }
    }
}

private final class ToastContentView: UIView {
    private let action: (() -> ())?
    private let dismiss: (() -> ())?
    private weak var iconSticker: WAnimatedSticker?

    init(config: ToastConfig, dismiss: (() -> ())?) {
        self.action = config.action
        self.dismiss = dismiss
        super.init(frame: .zero)
        backgroundColor = .clear
        build(style: config.style, icon: config.icon, message: config.message, actionTitle: config.actionTitle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(style: ToastStyle, icon: ToastIcon?, message: String, actionTitle: String?) {
        let font: UIFont
        let actionFont: UIFont
        let symbolConfiguration: UIImage.SymbolConfiguration
        let iconSize: CGFloat
        var leftContentInsets = 12.0
        var standAloneLabelInsets: CGFloat = 0
        let labelVerticalPadding: CGFloat = 16
        switch style {
        case .standard:
            font = .systemFont(ofSize: 13)
            actionFont = .systemFont(ofSize: 13)
            symbolConfiguration = .init(pointSize: 15)
            iconSize = 35
        case .large:
            font = .systemFont(ofSize: 14, weight: .semibold)
            actionFont = .systemFont(ofSize: 16)
            symbolConfiguration = .init(pointSize: 22)
            iconSize = 40
            standAloneLabelInsets = 12
        }

        var constraints: [NSLayoutConstraint] = []

        let contentLayoutGuide = UILayoutGuide()
        addLayoutGuide(contentLayoutGuide)
        constraints += [
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        if let icon {
            let iconView = UIView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)

            constraints += [
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            leftContentInsets += iconSize

            switch icon {
            case .animatedCopy:
                let animatedSticker = WAnimatedSticker()
                animatedSticker.animationName = "Copy"
                animatedSticker.setup(width: Int(iconSize), height: Int(iconSize), playbackMode: .once)
                animatedSticker.translatesAutoresizingMaskIntoConstraints = false
                iconView.addSubview(animatedSticker)
                iconSticker = animatedSticker
                constraints += [
                    animatedSticker.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                    animatedSticker.leftAnchor.constraint(equalTo: iconView.leftAnchor),
                    animatedSticker.widthAnchor.constraint(equalToConstant: iconSize),
                    animatedSticker.heightAnchor.constraint(equalToConstant: iconSize),
                ]

            case .symbolImage(let name):
                let image = UIImage(systemName: name)
                let imageView = UIImageView(image: image)
                imageView.tintColor = .white
                imageView.contentMode = .center
                imageView.preferredSymbolConfiguration = symbolConfiguration
                imageView.translatesAutoresizingMaskIntoConstraints = false
                iconView.addSubview(imageView)
                constraints += [
                    imageView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: iconSize),
                    imageView.heightAnchor.constraint(equalToConstant: iconSize),
                ]

            case .networkImage(let url):
                let imageImageSize = iconSize - 8
                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.layer.cornerRadius = 8
                imageView.layer.cornerCurve = .continuous
                imageView.translatesAutoresizingMaskIntoConstraints = false
                iconView.addSubview(imageView)
                constraints += [
                    imageView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: imageImageSize),
                    imageView.heightAnchor.constraint(equalToConstant: imageImageSize),
                ]
                imageView.kf.setImage(with: url, options: [
                    .transition(.fade(0.15)),
                    .alsoPrefetchToMemory,
                    .cacheOriginalImage,
                ])
                leftContentInsets += 8
            }
        } else {
            leftContentInsets += standAloneLabelInsets
        }
        
        constraints += [
            contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leftContentInsets),
        ]

        if let actionTitle {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = .air.toastAction
            config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
            var titleAttr = AttributedString(actionTitle)
            titleAttr.font = actionFont
            config.attributedTitle = titleAttr
            config.titleLineBreakMode = .byTruncatingTail

            let actionButton = UIButton(configuration: config)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            actionButton.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(actionButton)

            constraints += [
                actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                contentLayoutGuide.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -4),
            ]

            actionButton.addTarget(self, action: #selector(onActionTap), for: .touchUpInside)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onDismissTap)))
        } else {
            constraints += [
                contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
            ]
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onActionTap)))
        }

        let lbl = UILabel()
        lbl.font = font
        lbl.textColor = .white
        lbl.text = message
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(lbl)

        let labelBottom = lbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -labelVerticalPadding)
        labelBottom.priority = .init(999)
        constraints += [
            lbl.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: labelVerticalPadding),
            labelBottom,
            lbl.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            lbl.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ]

        NSLayoutConstraint.activate(constraints)
    }

    func replayIcon() {
        iconSticker?.playOnceFromStart()
    }

    @objc private func onDismissTap() {
        dismiss?()
    }

    @objc private func onActionTap() {
        action?()
        dismiss?()
    }
}
