import UIKit
import UIComponents
import WalletContext
import WalletCore

final class TokenTradeContinueButton: UIView {
    let button = WButton(style: .primary)
    private let titleView = TokenTradeButtonTitleView()
    private lazy var presenter = DraftButtonPresenter(button: button)
    private var lastConfiguration: DraftButtonConfiguration?
    private var lastTint: UIColor?
    private var onPress: () -> Void

    init(action: @escaping () -> Void) {
        onPress = action
        super.init(frame: .zero)
        button.customTitleFont = WButton.capsuleFont
        button.accessibilityIdentifier = "tokenTrade.continue"
        addSubview(button)
        titleView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleView)
        NSLayoutConstraint.activate([
            titleView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 40),
            titleView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -40),
            titleView.topAnchor.constraint(equalTo: button.topAnchor),
            titleView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.addAction(UIAction { [weak self] _ in
            guard let self, lastConfiguration?.isEnabled == true else { return }
            onPress()
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        TokenTradeMotion.place(button, in: bounds)
    }

    func update(configuration: DraftButtonConfiguration, tintColor: UIColor,
                diagnostics: SwapQuoteDiagnostics?, animated: Bool) {
        guard configuration != lastConfiguration || lastTint != tintColor else { return }
        let changesEnabled = lastConfiguration?.isEnabled != configuration.isEnabled
        lastConfiguration = configuration
        lastTint = tintColor
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
            // WButton creates its spinner lazily. Resolve its trailing constraints
            // before the button's appearance or presence animation can capture them.
            UIView.performWithoutAnimation { self.button.layoutIfNeeded() }
        }
        if animated && changesEnabled && TokenTradeMotion.enabled {
            UIView.transition(with: button, duration: 0.24,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                              animations: updateAppearance)
        } else { updateAppearance() }
        titleView.update(title: configuration.title, foreground: foreground, animated: animated && TokenTradeMotion.enabled)
        button.accessibilityLabel = titleView.text
        diagnostics?.rendered(configuration, button: button, renderedTitle: titleView.text)
    }
}

/// A fixed text surface keeps both sides of a replacement centered, independently
/// of UIButton's glass configuration and its internal title layout.
final class TokenTradeButtonTitleView: UILabel {
    private var title: DraftButtonConfiguration.Title?

    init() {
        super.init(frame: .zero)
        font = WButton.capsuleFont
        textAlignment = .center
        numberOfLines = 1
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.8
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: DraftButtonConfiguration.Title, foreground: UIColor, animated: Bool) {
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
