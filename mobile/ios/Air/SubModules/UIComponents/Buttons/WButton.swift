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
}

public class WButton: WBaseButton {

    public static let defaultHeight: CGFloat = 50
    static let borderRadius: CGFloat = 12
    public static let font = UIFont.systemFont(ofSize: 17, weight: .semibold)

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
                var config = UIButton.Configuration.glass()
                config.cornerStyle = .capsule
                config.titleLineBreakMode = .byTruncatingTail
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = UIFont.systemFont(ofSize: 17, weight: .medium)
                    return outgoing
                }
                config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                configuration = config
                configurationUpdateHandler = { button in
                    guard var updated = button.configuration else { return }
                    updated.baseBackgroundColor = button.isEnabled ? nil : .air.secondaryFill
                    button.configuration = updated
                }
                setNeedsUpdateConfiguration()
            }
            
        } else {
            // disable default styling of iOS 15+ to prevent tint/font set conflict issues
            // setting configuration to .none on interface builder makes text disappear
            switch style {
            case .thickCapsule:
                var config = UIButton.Configuration.filled()
                config.cornerStyle = .capsule
                config.titleLineBreakMode = .byTruncatingTail
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = UIFont.systemFont(ofSize: 17, weight: .medium)
                    return outgoing
                }
                config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                configuration = config
                
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

            case .thickCapsule:
                backgroundColor = .air.secondaryFill
                tintColor = .tintColor

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
            if style == .thickCapsule {
                layer.cornerRadius = min(bounds.height, bounds.width) / 2
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
        indicator.tintColor = (style == .secondary || style == .thickCapsule) ? .tintColor : .white
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
