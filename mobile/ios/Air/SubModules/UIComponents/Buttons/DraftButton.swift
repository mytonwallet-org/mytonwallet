import SwiftUI
import WalletContext

/// SwiftUI entry point for the same draft-button presentation used by UIKit.
public struct DraftButton: View {
    private let configuration: DraftButtonConfiguration
    private let action: () -> Void

    public init(configuration: DraftButtonConfiguration, action: @escaping () -> Void) {
        self.configuration = configuration
        self.action = action
    }

    public var body: some View {
        DraftButtonView(configuration: configuration, action: action)
            .frame(maxWidth: .infinity)
            .frame(height: IOS_26_MODE_ENABLED ? WButton.glassHeight : WButton.defaultHeight)
    }
}

private struct DraftButtonView: UIViewRepresentable {
    let configuration: DraftButtonConfiguration
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WButton {
        let button = WButton(style: .primary)
        context.coordinator.presenter = DraftButtonPresenter(button: button)
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: WButton, context: Context) {
        let effectiveConfiguration = DraftButtonConfiguration(
            title: configuration.title,
            isEnabled: isEnabled && configuration.isEnabled,
            showLoading: isEnabled && configuration.showLoading
        )
        context.coordinator.action = action
        context.coordinator.isEnabled = effectiveConfiguration.isEnabled
        context.coordinator.presenter?.apply(effectiveConfiguration)
    }

    @MainActor final class Coordinator: NSObject {
        var presenter: DraftButtonPresenter?
        var action: (() -> Void)?
        var isEnabled = false

        @objc func pressed() {
            guard isEnabled else { return }
            action?()
        }
    }
}
