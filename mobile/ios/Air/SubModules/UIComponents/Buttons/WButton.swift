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
    case compactCapsule
    case thickCapsule
    case thickDestructiveCapsule
}

public class WButton: WBaseButton {

    public static let defaultHeight: CGFloat = 50
    public static let compactHeight: CGFloat = 42
    static let borderRadius: CGFloat = 12
    public static let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    public static let capsuleFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    public static let compactFont = UIFont.systemFont(ofSize: 15, weight: .medium)

    public static func font(for style: WButtonStyle) -> UIFont {
        switch style {
        case .compactCapsule:
            compactFont
        case .thickCapsule, .thickDestructiveCapsule:
            capsuleFont
        default:
            font
        }
    }

    public private(set) var style = WButtonStyle.primary

    private var hasCustomDisabledAttributedTitle = false

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

            case .compactCapsule:
                setupCompactGlassCapsule()
                
            case .thickCapsule:
                setupThickGlassCapsule(enabledForeground: nil)

            case .thickDestructiveCapsule:
                setupThickGlassCapsule(enabledForeground: destructiveColor)
            }
            
        } else {
            // disable default styling of iOS 15+ to prevent tint/font set conflict issues
            // setting configuration to .none on interface builder makes text disappear
            switch style {
            case .compactCapsule:
                setupCompactCapsule()

            case .thickCapsule:
                setupThickCapsule(enabledForeground: .tintColor)

            case .thickDestructiveCapsule:
                setupThickCapsule(enabledForeground: destructiveColor, disabledForeground: .air.secondaryLabel)
                
            default:
                configuration = .none
                layer.cornerRadius = Self.borderRadius
            }
        }

        let heightConstraint = heightAnchor.constraint(equalToConstant: Self.height(for: style))
        heightConstraint.priority = UILayoutPriority(800)
        heightConstraint.isActive = true

        titleLabel?.font = Self.font(for: style)
        updateTheme()
    }

    public static func height(for style: WButtonStyle) -> CGFloat {
        switch style {
        case .compactCapsule:
            compactHeight
        default:
            defaultHeight
        }
    }
    
    private var primaryButtonTint: UIColor {
        if accentColor == .label {
            return .air.background
        } else {
            return UIColor.white
        }
    }

    private var enabledTitleColor: UIColor {
        switch style {
        case .primary:
            primaryButtonTint
        case .destructive:
            .white
        case .secondary, .clearBackground:
            .tintColor
        case .compactCapsule:
            .label
        case .thickCapsule:
            .tintColor
        case .thickDestructiveCapsule:
            destructiveColor
        }
    }

    private var disabledTitleColor: UIColor {
        switch style {
        case .primary:
            primaryButtonTint
        case .destructive:
            .white.withAlphaComponent(0.5)
        case .secondary, .clearBackground:
            accentColor.withAlphaComponent(0.5)
        case .compactCapsule:
            .air.secondaryLabel
        case .thickCapsule:
            .tintColor
        case .thickDestructiveCapsule:
            .air.secondaryLabel
        }
    }
    
    private var destructiveColor: UIColor { .air.error }

    private var usesGlassButtonStyling: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            return true
        }
        return false
    }

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

    private func applyCompactCapsuleAppearance(to config: inout UIButton.Configuration) {
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WButton.font(for: self.style)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
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

    @available(iOS 26, *)
    private func setupCompactGlassCapsule() {
        var config = UIButton.Configuration.glass()
        applyCompactCapsuleAppearance(to: &config)
        configuration = config
        configurationUpdateHandler = { button in
            guard var updated = button.configuration else { return }
            updated.baseForegroundColor = button.isEnabled ? .label : .air.secondaryLabel
            button.configuration = updated
        }
        setNeedsUpdateConfiguration()
    }

    private func setupCapsuleShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.12
        layer.masksToBounds = false
    }

    private func setupCompactCapsule() {
        var config = UIButton.Configuration.filled()
        applyCompactCapsuleAppearance(to: &config)
        configuration = config
        configurationUpdateHandler = { button in
            guard var updated = button.configuration else { return }
            if button.isHighlighted {
                updated.background.backgroundColor = .air.highlight
            } else {
                let color = UIColor.air.secondaryFill
                updated.background.backgroundColor = button.isEnabled ? color : color.withAlphaComponent(0.9)
            }
            updated.baseForegroundColor = button.isEnabled ? .label : .air.secondaryLabel
            button.configuration = updated
        }
        setNeedsUpdateConfiguration()
        setupCapsuleShadow()
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
        setupCapsuleShadow()
    }

    private func updateTheme() {
        if usesGlassButtonStyling {
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

            case .compactCapsule, .thickCapsule, .thickDestructiveCapsule:
                setNeedsUpdateConfiguration()

            case .clearBackground:
                backgroundColor = .clear
                tintColor = isEnabled ? .tintColor : accentColor.withAlphaComponent(0.5)
            }
            updateTitleColors()
        }
    }

    private func updateTitleColors() {
        setTitleColor(enabledTitleColor, for: .normal)
        setTitleColor(disabledTitleColor, for: .disabled)
        updateAttributedTitleColors()
    }

    private func updateAttributedTitleColors() {
        if let normalTitle = attributedTitle(for: .normal) {
            super.setAttributedTitle(normalTitle.withForegroundColor(enabledTitleColor), for: .normal)
            if hasCustomDisabledAttributedTitle, let disabledTitle = attributedTitle(for: .disabled) {
                super.setAttributedTitle(disabledTitle.withForegroundColor(disabledTitleColor), for: .disabled)
            } else {
                super.setAttributedTitle(normalTitle.withForegroundColor(disabledTitleColor), for: .disabled)
            }
        } else if hasCustomDisabledAttributedTitle, let disabledTitle = attributedTitle(for: .disabled) {
            super.setAttributedTitle(disabledTitle.withForegroundColor(disabledTitleColor), for: .disabled)
        } else {
            super.setAttributedTitle(nil, for: .disabled)
        }
    }

    public override func setAttributedTitle(_ title: NSAttributedString?, for state: UIControl.State) {
        if state == .disabled {
            hasCustomDisabledAttributedTitle = title != nil
        }
        super.setAttributedTitle(title, for: state)
        if !usesGlassButtonStyling {
            updateAttributedTitleColors()
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
            if style == .compactCapsule || style == .thickCapsule || style == .thickDestructiveCapsule {
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
        case .compactCapsule:
            .label
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

private extension NSAttributedString {
    func withForegroundColor(_ color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: self)
        if result.length > 0 {
            result.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}
