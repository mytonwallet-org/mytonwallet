import UIKit
import WalletCore

public class ToastView: UIView {
    private var action: (() -> ())?
    private var dismiss: (() -> ())?
    private let icon: ToastIcon?
    private let actionTitle: String?
    private let message: String
    private let style: ToastStyle
    
    init(style: ToastStyle, icon: ToastIcon? = nil, message: String, actionTitle: String?, action: (() -> ())? = nil, dismiss: (() -> ())? = nil) {
        self.icon = icon
        self.message = message
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
        self.dismiss = dismiss
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        
        let font: UIFont
        let actionFont: UIFont
        let symbolConfiguration: UIImage.SymbolConfiguration
        let cornerRadius: CGFloat
        let iconSize: CGFloat
        
        switch style {
        case .standard:
            font = .systemFont(ofSize: 13)
            actionFont = .systemFont(ofSize: 13)
            symbolConfiguration = .init(pointSize: 15)
            cornerRadius = 16
            iconSize = 35
        case .large:
            font = .systemFont(ofSize: 14, weight: .semibold)
            actionFont = .systemFont(ofSize: 16)
            symbolConfiguration = .init(pointSize: 22)
            cornerRadius = 25
            iconSize = 40
        }
        
        let blurView = WBlurView.attach(to: self, background: .air.toastBackground)
        blurView.layer.cornerRadius = cornerRadius
        blurView.layer.masksToBounds = true
        
        alpha = 0
        layer.cornerRadius = cornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = cornerRadius
        backgroundColor = .clear
                
        let contentLayoutGuide = UILayoutGuide()
        addLayoutGuide(contentLayoutGuide)
        let leadingContentConstraint = contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        let trailingContentConstraint = contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingContentConstraint,
            leadingContentConstraint,
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        
        if let icon {
            let iconView = UIView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
                        
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            leadingContentConstraint.constant += iconSize
            
            switch icon {
            case .animatedCopy:
                let animationName = "Copy"
                let animatedSticker: WAnimatedSticker
                animatedSticker = WAnimatedSticker()
                animatedSticker.animationName = animationName
                animatedSticker.setup(width: Int(iconSize), height: Int(iconSize), playbackMode: .once)
                animatedSticker.translatesAutoresizingMaskIntoConstraints = false
                iconView.addSubview(animatedSticker)
                NSLayoutConstraint.activate([
                    animatedSticker.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                    animatedSticker.leftAnchor.constraint(equalTo: iconView.leftAnchor),
                    animatedSticker.widthAnchor.constraint(equalToConstant: iconSize),
                    animatedSticker.heightAnchor.constraint(equalToConstant: iconSize),
                ])
                
            case .symbolImage(let name):
                let image = UIImage(systemName: name)
                let imageView = UIImageView(image: image)
                imageView.tintColor = .white
                imageView.contentMode = .center
                imageView.preferredSymbolConfiguration = symbolConfiguration
                imageView.translatesAutoresizingMaskIntoConstraints = false
                iconView.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: iconSize),
                    imageView.heightAnchor.constraint(equalToConstant: iconSize),
                ])
            }
        }
        
        if let actionTitle {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = .air.toastAction
            config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
            var titleAttr = AttributedString(actionTitle)
            titleAttr.font = actionFont
            config.attributedTitle = titleAttr
            
            let actionButton = UIButton(configuration: config)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(actionButton)
            
            trailingContentConstraint.isActive = false
            NSLayoutConstraint.activate([
                actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                contentLayoutGuide.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -4)
            ])
            
            actionButton.addTarget(self, action: #selector(onActionTap), for: .touchUpInside)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onDismissTap)))

        } else {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onActionTap)))
        }

        let lbl = UILabel()
        lbl.font = font
        lbl.textColor = .white
        lbl.text = message
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lbl)
        
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 12),
            lbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            lbl.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            lbl.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
    }
    
    @objc private func onDismissTap() {
        dismiss?()
    }
    
    @objc private func onActionTap() {
        action?()
        dismiss?()
    }
}
