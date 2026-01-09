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
}

public class WButton: WBaseButton, WThemedView {

    public static let defaultHeight: CGFloat = 50
    static let borderRadius: CGFloat = 12
    public static let font = UIFont.systemFont(ofSize: 17, weight: .semibold)

    public private(set) var style = WButtonStyle.primary

    public convenience init(style: WButtonStyle = .primary) {
        self.init(type: .system)
        self.style = style
        self.setup()
    }
    
    private func setup() {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            configuration = style == .primary ? .prominentGlass() : .glass()
        } else {
            // disable default styling of iOS 15+ to prevent tint/font set conflict issues
            // setting configuration to .none on interface builder makes text disappear
            configuration = .none
            layer.cornerRadius = Self.borderRadius
        }

        let heightConstraint = heightAnchor.constraint(equalToConstant: Self.defaultHeight)
        heightConstraint.priority = UILayoutPriority(800)
        heightConstraint.isActive = true

        titleLabel?.font = Self.font
        updateTheme()
    }
    
    private var primaryButtonTint: UIColor {
        if WTheme.primaryButton.background == .label {
            return WTheme.background
        } else {
            return WTheme.primaryButton.tint
        }
    }
    
    public func updateTheme() {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            tintColor = WTheme.tint
        } else {
            switch style {
            case .primary:
                backgroundColor = isEnabled ? WTheme.primaryButton.background : WTheme.primaryButton.disabledBackground
                tintColor = isEnabled ? primaryButtonTint : WTheme.primaryButton.disabledTint

            case .secondary:
                backgroundColor = isEnabled ? WTheme.tint.withAlphaComponent(0.15) : .clear
                tintColor = isEnabled ? WTheme.tint : WTheme.tint.withAlphaComponent(0.5)

            case .clearBackground:
                backgroundColor = .clear
                tintColor = isEnabled ? WTheme.tint : WTheme.tint.withAlphaComponent(0.5)
            }
        }
    }

    public override var isEnabled: Bool {
        didSet {
            updateTheme()
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
        indicator.tintColor = style == .secondary ? WTheme.primaryButton.background : .white
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

