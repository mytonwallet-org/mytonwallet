import UIKit
import WalletContext
import WalletCore

public final class NativeTradeContinueButton: UIView {
    public let button = WButton(style: .primary)
    private let titleView = NativeTradeButtonTitleView()
    private lazy var presenter = DraftButtonPresenter(button: button)
    private var lastConfiguration: DraftButtonConfiguration?
    private var lastTint: UIColor?
    private var onPress: () -> Void

    public init(action: @escaping () -> Void) {
        onPress = action
        super.init(frame: .zero)
        button.customTitleFont = WButton.capsuleFont
        button.accessibilityIdentifier = "tokenTrade.continue"
        addSubview(button)
        button.setCustomContentView(titleView)
        button.addAction(UIAction { [weak self] _ in
            guard let self, lastConfiguration?.isEnabled == true else { return }
            onPress()
        }, for: .touchUpInside)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        TradeMotion.place(button, in: bounds)
    }

    public func update(configuration: DraftButtonConfiguration, tintColor: UIColor,
                onRender: ((DraftButtonConfiguration, WButton, String?) -> Void)? = nil, animated: Bool) {
        guard configuration != lastConfiguration || lastTint != tintColor else { return }
        let changesEnabled = lastConfiguration?.isEnabled != configuration.isEnabled
        lastConfiguration = configuration
        lastTint = tintColor
        button.areLoadingAnimationsEnabled = animated && TradeMotion.enabled
        var foreground: UIColor = .white
        let updateAppearance = {
            // Keep UIKit's configured title empty while glass rebuilds its internal content.
            self.presenter.apply(.init(title: .text(""), isEnabled: configuration.isEnabled,
                showLoading: configuration.showLoading, resetsLoadingAppearance: configuration.resetsLoadingAppearance))
            let appearsEnabled = self.button.isEnabled
            self.button.customTintColor = appearsEnabled ? tintColor : nil
            foreground = self.button.titleColor(for: self.button.state) ?? self.button.tintColor ?? .white
            if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
                var appearance: UIButton.Configuration = appearsEnabled ? .prominentGlass() : .glass()
                appearance.baseBackgroundColor = appearsEnabled ? tintColor : nil
                appearance.baseForegroundColor = appearsEnabled ? .white : .air.secondaryLabel
                foreground = appearsEnabled ? .white : .air.secondaryLabel
                self.button.configuration = appearance
            }
        }
        if animated && changesEnabled && TradeMotion.enabled {
            UIView.transition(with: button, duration: 0.24,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                              animations: updateAppearance)
        } else { updateAppearance() }
        titleView.update(title: configuration.title, foreground: foreground, animated: animated && TradeMotion.enabled)
        button.invalidateIntrinsicContentSize()
        button.setNeedsLayout()
        button.accessibilityLabel = titleView.text
        onRender?(configuration, button, titleView.text)
    }
}

/// A text surface independent of UIButton's glass configuration.
public final class NativeTradeButtonTitleView: UILabel {
    private var title: DraftButtonConfiguration.Title?

    public init() {
        super.init(frame: .zero)
        font = WButton.capsuleFont
        textAlignment = .center
        numberOfLines = 1
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.8
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(title: DraftButtonConfiguration.Title, foreground: UIColor, animated: Bool) {
        if !animated {
            layer.removeAnimation(forKey: "titleOpacity")
            layer.removeAnimation(forKey: "titleScale")
        }
        let replacesTitle = self.title != nil && self.title != title
        self.title = title
        if replacesTitle && animated && !bounds.isEmpty {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.28
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "titleOpacity")

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.94
            scale.toValue = 1
            scale.duration = fade.duration
            scale.timingFunction = fade.timingFunction
            layer.add(scale, forKey: "titleScale")
        }
        switch title {
        case .text(let text):
            self.attributedText = nil
            self.text = text
        case .attributed(let text, _):
            self.attributedText = text
        }
        textColor = foreground
    }
}
