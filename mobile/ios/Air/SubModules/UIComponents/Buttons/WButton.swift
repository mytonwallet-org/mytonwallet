//
//  WButton.swift
//  UIComponents
//
//  Created by Sina on 3/30/23.
//

import UIKit
import WalletContext

public enum WButtonStyle: Hashable {
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
    public static let glassHeight: CGFloat = 52
    public static let compactHeight: CGFloat = 42
    static let borderRadius: CGFloat = 12
    public static var font: UIFont {
        WTypography.uiFont(.button)
    }

    public static var capsuleFont: UIFont {
        WTypography.uiFont(.capsuleButton)
    }

    public static var compactFont: UIFont {
        WTypography.uiFont(.compactButton)
    }

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

    public var customTintColor: UIColor? {
        didSet {
            updateTheme()
        }
    }

    public var customTitleFont: UIFont? {
        didSet {
            updateTitleAppearance()
        }
    }

    private var hasCustomDisabledAttributedTitle = false

    private var accentColor: UIColor {
        customTintColor ?? window?.tintColor ?? AirTintColor
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

        titleLabel?.font = resolvedTitleFont
        titleLabel?.textAlignment = .center
        updateTheme()
    }

    public static func height(for style: WButtonStyle) -> CGFloat {
        switch style {
        case .compactCapsule:
            compactHeight
        default:
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                glassHeight
            } else {
                defaultHeight
            }
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

    var contentForegroundColor: UIColor {
        if usesGlassButtonStyling && !isEnabled {
            return .air.secondaryLabel
        }
        return isEnabled ? enabledTitleColor : disabledTitleColor
    }

    private var destructiveColor: UIColor { .air.error }

    var usesGlassButtonStyling: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            return true
        }
        return false
    }

    private var resolvedTitleFont: UIFont {
        customTitleFont ?? Self.font(for: style)
    }

    private var configuredTitleForegroundColor: UIColor? {
        if style == .destructive || (customTintColor != nil && style == .primary) {
            .white
        } else {
            nil
        }
    }

    private func applyTitleAppearance(to config: inout UIButton.Configuration) {
        config.titleAlignment = .center
        let font = resolvedTitleFont
        let foregroundColor = configuredTitleForegroundColor
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            if let foregroundColor {
                outgoing.foregroundColor = foregroundColor
            }
            return outgoing
        }
    }

    private func updateTitleAppearance() {
        titleLabel?.font = resolvedTitleFont
        guard var config = configuration else { return }
        applyTitleAppearance(to: &config)
        configuration = config
    }

    private func applyThickCapsuleAppearance(to config: inout UIButton.Configuration) {
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail
        applyTitleAppearance(to: &config)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    }

    private func applyCompactCapsuleAppearance(to config: inout UIButton.Configuration) {
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            font: WTypography.uiFont(.calloutEmphasized, content: .technical)
        )
        applyTitleAppearance(to: &config)
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
            tintColor = customTintColor ?? .tintColor
            if var config = configuration {
                switch style {
                case .primary:
                    config.baseBackgroundColor = customTintColor
                    config.baseForegroundColor = customTintColor == nil ? nil : .white
                case .destructive:
                    config.baseBackgroundColor = customTintColor ?? destructiveColor
                    config.baseForegroundColor = .white
                default:
                    break
                }
                applyTitleAppearance(to: &config)
                configuration = config
            }
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
        loadingView?.tintColor = loadingIndicatorColor
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        loadingView?.tintColor = loadingIndicatorColor
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            loadingView?.tintColor = loadingIndicatorColor
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

        if let customContentView {
            let size = customContentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            // A stable viewport lets SwiftUI animate label changes within the button
            UIView.performWithoutAnimation {
                customContentView.bounds = CGRect(origin: .zero, size: CGSize(
                    width: max(0, bounds.width - 32),
                    height: min(size.height, bounds.height)
                ))
                customContentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            }
        }
        updateLoadingPresentation()

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
    private var loadingContainer: UIView?
    private var customContentView: UIView?
    private var loadingPresentation: LoadingPresentation = .hidden
    var areLoadingAnimationsEnabled = true

    private enum LoadingPresentation {
        case hidden
        case trailing
        case replacingContent
    }

    /// Custom labels share the button's loading layout and transition.
    public func setCustomContentView(_ view: UIView) {
        customContentView?.removeFromSuperview()
        customContentView = view
        view.isUserInteractionEnabled = false
        addSubview(view)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    public override var intrinsicContentSize: CGSize {
        guard let customContentView else { return super.intrinsicContentSize }
        let size = customContentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: size.width + 36, height: Self.height(for: style))
    }

    public var showLoading: Bool = false {
        didSet {
            guard showLoading != oldValue else { return }
            if showLoading && loadingView == nil {
                createLoadingView()
            }
            setNeedsLayout()
        }
    }

    private func createLoadingView() {
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.isAccessibilityElement = false
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        addSubview(container)
        let indicator = WActivityIndicator()
        indicator.tintColor = loadingIndicatorColor
        indicator.isAccessibilityElement = false
        container.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        loadingContainer = container
        loadingView = indicator
    }

    private func updateLoadingPresentation() {
        guard loadingView != nil else { return }
        let contentViews = customContentView.map { [$0] } ?? [titleLabel, imageView].compactMap { $0 }
        let isRtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let indicatorSize: CGFloat = 24
        let indicatorInset: CGFloat = 16
        let spacing: CGFloat = 8
        let indicatorX = isRtl ? indicatorInset : bounds.width - indicatorInset - indicatorSize
        let hasRoomForIndicator = contentViews.allSatisfy { view in
            guard !view.isHidden, let parent = view.superview else { return true }
            let fittingSize = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            // Measure the unscaled content, including text clipped by UIKit.
            let width = view === customContentView ? fittingSize.width : max(view.bounds.width, fittingSize.width)
            let rect = parent.convert(CGRect(
                x: view.center.x - width / 2,
                y: view.center.y - view.bounds.height / 2,
                width: width,
                height: view.bounds.height
            ), to: self)
            return isRtl ? rect.minX >= indicatorX + indicatorSize + spacing : rect.maxX <= indicatorX - spacing
        }
        let presentation: LoadingPresentation = !showLoading ? .hidden
            : hasRoomForIndicator ? .trailing : .replacingContent
        let changed = presentation != loadingPresentation
        loadingPresentation = presentation

        if let loadingContainer {
            UIView.performWithoutAnimation {
                loadingContainer.bounds = CGRect(x: 0, y: 0, width: indicatorSize, height: indicatorSize)
                loadingContainer.center = CGPoint(
                    x: showLoading
                        ? (presentation == .replacingContent ? bounds.midX : indicatorX + indicatorSize / 2)
                        : loadingContainer.center.x,
                    y: bounds.midY
                )
                loadingContainer.layoutIfNeeded()
            }
            bringSubviewToFront(loadingContainer)
        }
        if showLoading {
            loadingView?.startAnimating(animated: false)
        }
        let updates = {
            for view in contentViews {
                view.alpha = presentation == .replacingContent ? 0 : 1
                view.transform = presentation == .replacingContent
                    ? CGAffineTransform(scaleX: 0.8, y: 0.8) : .identity
            }
            self.loadingContainer?.alpha = self.showLoading ? 1 : 0
            self.loadingContainer?.transform = self.showLoading ? .identity : CGAffineTransform(scaleX: 0.8, y: 0.8)
        }
        let completion: (Bool) -> Void = { [weak self] finished in
            guard finished, presentation == .hidden, let self, !self.showLoading else { return }
            self.loadingView?.stopAnimating(animated: false)
        }
        if changed && window != nil && areLoadingAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.25, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                           animations: updates, completion: completion)
        } else {
            updates()
            if changed { completion(true) }
        }
    }

    private var loadingIndicatorColor: UIColor {
        switch style {
        case .primary:
            if usesGlassButtonStyling && !isEnabled {
                .air.secondaryLabel
            } else {
                (usesGlassButtonStyling ? tintColor.resolvedColor(with: traitCollection) : accentColor)
                    .foregroundForTintedBackground
            }
        case .secondary, .clearBackground, .thickCapsule:
            .tintColor
        case .compactCapsule:
            .label
        case .thickDestructiveCapsule:
            isEnabled ? .air.error : .air.secondaryLabel
        default:
            .white
        }
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
