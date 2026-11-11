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
        button.setCustomContentView(titleView)
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
        button.areLoadingAnimationsEnabled = !reduceMotion && animationsEnabled
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
        button.invalidateIntrinsicContentSize()
        button.setNeedsLayout()
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

public typealias TradeButtonTitleView = NativeTradeButtonTitleView
