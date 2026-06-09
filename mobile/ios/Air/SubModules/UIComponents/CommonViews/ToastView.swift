import UIKit
import WalletCore

public class ToastView: UIView {
    private var blurView: WBlurView!
    private var dismiss: (() -> ())?
    private var contentView: ToastContentView?
    private var heightConstraint: NSLayoutConstraint!

    init(style: ToastStyle, icon: ToastIcon? = nil, message: String, actionTitle: String?, action: (() -> ())? = nil, dismiss: (() -> ())? = nil) {
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

        setContent(style: style, icon: icon, message: message, actionTitle: actionTitle, action: action, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    func update(style: ToastStyle, icon: ToastIcon?, message: String, actionTitle: String?, action: (() -> ())?) {
        setContent(style: style, icon: icon, message: message, actionTitle: actionTitle, action: action, animated: true)
    }

    func replayIcon() {
        contentView?.replayIcon()
    }

    private func setContent(style: ToastStyle, icon: ToastIcon?, message: String, actionTitle: String?,
                            action: (() -> ())?, animated: Bool) {
        let cornerRadius: CGFloat = style == .large ? 25 : 16

        let oldContent = contentView
        let newContent = ToastContentView(style: style, icon: icon, message: message, actionTitle: actionTitle,
                                          action: action, dismiss: dismiss)
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

    init(style: ToastStyle, icon: ToastIcon?, message: String, actionTitle: String?,
         action: (() -> ())?, dismiss: (() -> ())?) {
        self.action = action
        self.dismiss = dismiss
        super.init(frame: .zero)
        backgroundColor = .clear
        build(style: style, icon: icon, message: message, actionTitle: actionTitle)
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
