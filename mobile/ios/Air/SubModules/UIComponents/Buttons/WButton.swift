//
//  WButton.swift
//  UIComponents
//
//  Created by Sina on 3/30/23.
//

import UIKit
import WalletContext

public enum WButtonStyle {
    case primary
    case secondary
    case clearBackground
    case destructive
    case thickCapsule
    case thickDestructiveCapsule
}

public class WButton: WBaseButton {

    public static let defaultHeight: CGFloat = 50
    static let borderRadius: CGFloat = 12
    public static let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    public static let capsuleFont = UIFont.systemFont(ofSize: 17, weight: .medium)

    public static func font(for style: WButtonStyle) -> UIFont {
        switch style {
        case .thickCapsule, .thickDestructiveCapsule:
            capsuleFont
        default:
            font
        }
    }

    public private(set) var style = WButtonStyle.primary

    private var accentColor: UIColor {
        window?.tintColor ?? AirTintColor
    }

    public convenience init(style: WButtonStyle = .primary) {
        self.init(type: .system)
        self.style = style
        self.setup()
    }
    
    private func setup() {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            switch style {
            case .clearBackground, .secondary:
                configuration = .glass()
                
            case .primary:
                configuration = .prominentGlass()
                
            case .destructive:
                var config = UIButton.Configuration.prominentGlass()
                config.baseBackgroundColor = destructiveColor
                config.baseForegroundColor = .white
                configuration = config
                
            case .thickCapsule:
                setupThickGlassCapsule(enabledForeground: nil)

            case .thickDestructiveCapsule:
                setupThickGlassCapsule(enabledForeground: destructiveColor)
            }
            
        } else {
            // disable default styling of iOS 15+ to prevent tint/font set conflict issues
            // setting configuration to .none on interface builder makes text disappear
            switch style {
            case .thickCapsule:
                setupThickCapsule(enabledForeground: .tintColor)

            case .thickDestructiveCapsule:
                setupThickCapsule(enabledForeground: destructiveColor, disabledForeground: .air.secondaryLabel)
                
            default:
                configuration = .none
                layer.cornerRadius = Self.borderRadius
            }
        }

        let heightConstraint = heightAnchor.constraint(equalToConstant: Self.defaultHeight)
        heightConstraint.priority = UILayoutPriority(800)
        heightConstraint.isActive = true

        titleLabel?.font = Self.font
        updateTheme()
    }
    
    private var primaryButtonTint: UIColor {
        if accentColor == .label {
            return .air.background
        } else {
            return UIColor.white
        }
    }
    
    private var destructiveColor: UIColor { .air.error }

    private func applyThickCapsuleAppearance(to config: inout UIButton.Configuration) {
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WButton.font(for: self.style)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    }

    @available(iOS 26, *)
    private func setupThickGlassCapsule(enabledForeground: UIColor?) {
        var config = UIButton.Configuration.glass()
        applyThickCapsuleAppearance(to: &config)
        configuration = config
        configurationUpdateHandler = { button in
            guard var updated = button.configuration else { return }
            updated.baseForegroundColor = button.isEnabled ? enabledForeground : nil
            button.configuration = updated
        }
        setNeedsUpdateConfiguration()
    }

    private func setupThickCapsule(enabledForeground: UIColor, disabledForeground: UIColor = .tintColor) {
        var config = UIButton.Configuration.filled()
        applyThickCapsuleAppearance(to: &config)
        configuration = config
        configurationUpdateHandler = { button in
            guard var updated = button.configuration else { return }
            if button.isHighlighted {
                updated.background.backgroundColor = .air.highlight
            } else {
                let color = UIColor.air.secondaryFill
                updated.background.backgroundColor = button.isEnabled ? color : color.withAlphaComponent(0.9)
            }
            updated.baseForegroundColor = button.isEnabled ? enabledForeground : disabledForeground
            button.configuration = updated
        }
        setNeedsUpdateConfiguration()

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.12
        layer.masksToBounds = false
    }

    private func updateTheme() {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            tintColor = .tintColor
        } else {
            switch style {
            case .primary:
                backgroundColor = isEnabled ? accentColor : accentColor.withAlphaComponent(0.5)
                tintColor = isEnabled ? primaryButtonTint : UIColor.white

            case .destructive:
                backgroundColor = isEnabled ? destructiveColor : destructiveColor.withAlphaComponent(0.5)
                tintColor = isEnabled ? .white : .white.withAlphaComponent(0.5)

            case .secondary:
                backgroundColor = isEnabled ? accentColor.withAlphaComponent(0.15) : .clear
                tintColor = isEnabled ? .tintColor : accentColor.withAlphaComponent(0.5)

            case .thickCapsule, .thickDestructiveCapsule:
                setNeedsUpdateConfiguration()

            case .clearBackground:
                backgroundColor = .clear
                tintColor = isEnabled ? .tintColor : accentColor.withAlphaComponent(0.5)
            }
        }
    }

    public override var isEnabled: Bool {
        didSet {
            updateTheme()
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            //
        } else {
            if style == .thickCapsule || style == .thickDestructiveCapsule {
                layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
            }
        }
    }
    
    // MARK: - Loading View

    private var loadingView: WActivityIndicator?

    public var showLoading: Bool = false {
        didSet {
            if showLoading {
                let indicator = loadingView ?? createLoadingView()
                indicator.startAnimating(animated: true)
            } else {
                loadingView?.stopAnimating(animated: true)
            }
        }
    }

    private func createLoadingView() -> WActivityIndicator {
        let indicator = WActivityIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.tintColor = switch style {
        case .secondary, .thickCapsule:
            .tintColor
        case .thickDestructiveCapsule:
            isEnabled ? .air.error : .air.secondaryLabel
        default:
            .white
        }
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        loadingView = indicator
        return indicator
    }
    
    public func apply(config: WButtonConfig) {
        self.setTitle(config.title, for: .normal)
        self.isEnabled = config.isEnabled
    }
}
