import SwiftUI
import UIKit
import WalletContext

public struct TradeContinueButton: UIViewRepresentable {
    let configuration: DraftButtonConfiguration
    let tintColor: UIColor
    var onRender: ((DraftButtonConfiguration, WButton, String?) -> Void)?
    let accessibilityIdentifier: String
    let animationsEnabled: Bool
    let action: () -> Void
    public init(configuration: DraftButtonConfiguration, tintColor: UIColor, accessibilityIdentifier: String = "tokenTrade.continue", animationsEnabled: Bool = true,
                onRender: ((DraftButtonConfiguration, WButton, String?) -> Void)? = nil, action: @escaping () -> Void) {
        self.configuration = configuration; self.tintColor = tintColor; self.accessibilityIdentifier = accessibilityIdentifier
        self.onRender = onRender; self.action = action; self.animationsEnabled = animationsEnabled
    }
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> WButton {
        let button = WButton(style: .primary)
        button.customTitleFont = WButton.capsuleFont
        button.accessibilityIdentifier = accessibilityIdentifier
        context.coordinator.presenter = DraftButtonPresenter(button: button)
        let titleView = context.coordinator.titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleView)
        NSLayoutConstraint.activate([
            titleView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 40),
            titleView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -40),
            titleView.topAnchor.constraint(equalTo: button.topAnchor),
            titleView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: WButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 52)
    }

    public func updateUIView(_ button: WButton, context: Context) {
        let effectiveConfiguration = DraftButtonConfiguration(
            title: configuration.title,
            isEnabled: isEnabled && configuration.isEnabled,
            showLoading: isEnabled && configuration.showLoading,
            resetsLoadingAppearance: configuration.resetsLoadingAppearance
        )
        context.coordinator.action = action
        context.coordinator.isEnabled = effectiveConfiguration.isEnabled
        // Keep UIKit's configured title empty: switching glass styles can rebuild
        // its label before it has a centered frame.
        context.coordinator.presenter?.apply(.init(
            title: .text(""),
            isEnabled: effectiveConfiguration.isEnabled,
            showLoading: effectiveConfiguration.showLoading,
            resetsLoadingAppearance: effectiveConfiguration.resetsLoadingAppearance
        ))
        let appearsEnabled = button.isEnabled
        button.customTintColor = appearsEnabled ? tintColor : nil
        var foreground = button.titleColor(for: button.state) ?? button.tintColor ?? .white
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            var configuration: UIButton.Configuration = appearsEnabled ? .prominentGlass() : .glass()
            configuration.baseBackgroundColor = appearsEnabled ? tintColor : nil
            configuration.baseForegroundColor = appearsEnabled ? .white : .air.secondaryLabel
            foreground = appearsEnabled ? .white : .air.secondaryLabel
            button.configuration = configuration
        }
        context.coordinator.titleView.update(
            title: configuration.title,
            foreground: foreground,
            animated: button.window != nil && !reduceMotion && animationsEnabled
        )
        button.isAccessibilityElement = true
        button.accessibilityTraits.insert(.button)
        button.accessibilityLabel = context.coordinator.titleView.text
        onRender?(effectiveConfiguration, button, context.coordinator.titleView.text)
    }

    @MainActor public final class Coordinator: NSObject {
        let titleView = TradeButtonTitleView()
        var presenter: DraftButtonPresenter?
        var action: (() -> Void)?
        var isEnabled = false

        @objc func pressed() {
            guard isEnabled else { return }
            action?()
        }
    }
}

/// A fixed text surface keeps both sides of a replacement centered, independently
/// of UIButton's glass configuration and its internal title layout.
public final class TradeButtonTitleView: UILabel {
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
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "titleOpacity")

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.96
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
