import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

/// The home screen's top bar and toolbar as they are, to rearrange by dragging
struct ToolbarSettingsSection: View {
    @State private var configuration = ToolbarSettings.configuration()
    /// Changes when the preview needs another height
    @State private var previewLayout = 0

    private var sharesBackground: Binding<Bool> {
        Binding {
            configuration.sharesBackground
        } set: { sharesBackground in
            var configuration = ToolbarSettings.configuration()
            configuration.sharesBackground = sharesBackground
            ToolbarSettings.setConfiguration(configuration)
        }
    }

    var body: some View {
        WithPerceptionTracking {
            InsetSection(dividersTrailingInset: IOS_26_MODE_ENABLED ? 16 : 0) {
                InsetCell(horizontalPadding: 0, verticalPadding: 0) {
                    ToolbarsPreview(
                        configuration: configuration,
                        account: AccountStore.account,
                        layout: previewLayout
                    ) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                            previewLayout += 1
                        }
                    }
                }
                if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
                    InsetDetailCell(horizontalPadding: 16, verticalPadding: 0) {
                        Text(lang("Shared Background")).frame(minHeight: 44)
                    } value: {
                        Toggle(lang("Shared Background"), isOn: sharesBackground)
                            .labelsHidden()
                            .accessibilityIdentifier("appearance.toolbar.sharedBackground")
                    }
                }
                if configuration != HomeToolbarConfiguration() {
                    InsetButtonCell(horizontalPadding: 16, verticalPadding: 0, action: reset) {
                        Text(lang("Reset"))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("appearance.toolbar.reset")
                }
            } header: {
                Text(lang("Toolbars"))
            } footer: {
                Text(lang("$toolbar_settings_hint"))
            }
            .onReceive(NotificationCenter.default.publisher(for: ToolbarSettings.didChangeNotification)) { _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    configuration = ToolbarSettings.configuration()
                }
            }
        }
    }

    private func reset() {
        ToolbarSettings.setConfiguration(HomeToolbarConfiguration())
    }
}

private struct ToolbarsPreview: UIViewRepresentable {
    var configuration: HomeToolbarConfiguration
    var account: MAccount?
    var layout: Int
    var onHeightChange: () -> Void

    func makeUIView(context: Context) -> ToolbarsPreviewView {
        ToolbarsPreviewView()
    }

    func updateUIView(_ view: ToolbarsPreviewView, context: Context) {
        view.onHeightChange = onHeightChange
        view.configure(account: account)
        view.setConfiguration(configuration, animated: view.window != nil)
    }

    static func dismantleUIView(_ view: ToolbarsPreviewView, coordinator: ()) {
        view.onHeightChange = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ToolbarsPreviewView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: uiView.getPreferredHeight(width: width))
    }
}
