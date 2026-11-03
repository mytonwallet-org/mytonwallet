import Perception
import SwiftUI
import UIComponents
import UIUniversalSearch
import WalletContext
import WalletCore

struct ToolbarSettingsSection: View {
    @AppStorage(ToolbarSettings.accountsKey) private var showsAccounts = false
    @AppStorage(ToolbarSettings.scanKey) private var showsScan = true
    @AppStorage(ToolbarSettings.sharedBackgroundKey) private var sharesBackground = true

    private var configuration: HomeToolbarConfiguration {
        .init(showsAccounts: showsAccounts, showsScan: showsScan, sharesBackground: sharesBackground)
    }

    var body: some View {
        WithPerceptionTracking {
            InsetSection(dividersTrailingInset: IOS_26_MODE_ENABLED ? 16 : 0) {
                VStack(spacing: 0) {
                    InsetCell(horizontalPadding: 12, verticalPadding: 0) {
                        ToolbarPreview(configuration: configuration, account: AccountStore.account)
                            .frame(height: 48)
                            .padding(.top, 24)
                            .padding(.bottom, 20)
                            .accessibilityHidden(true)
                    }
                    toggle(lang("Accounts"), isOn: $showsAccounts, id: "appearance.toolbar.accounts")
                }
                toggle(lang("Scan QR"), isOn: $showsScan, id: "appearance.toolbar.scan")
                if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
                    toggle(lang("Shared Background"), isOn: $sharesBackground, id: "appearance.toolbar.sharedBackground")
                }
            } header: {
                Text(lang("Toolbar"))
            }
            .onChange(of: configuration) { _ in
                ToolbarSettings.notifyDidChange()
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        InsetDetailCell(horizontalPadding: 16, verticalPadding: 0) {
            Text(title).frame(minHeight: 44)
        } value: {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .accessibilityIdentifier(id)
        }
    }
}

private struct ToolbarPreview: UIViewRepresentable {
    var configuration: HomeToolbarConfiguration
    var account: MAccount?

    func makeUIView(context: Context) -> UniversalSearchFieldView {
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: lang("Search"), showsMicrophone: false))
        // SwiftUI supplies this view's frame; its internal constraints still need that width.
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        toolbar.setHomeConfiguration(configuration, animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.isUserInteractionEnabled = false
        return toolbar
    }

    func updateUIView(_ toolbar: UniversalSearchFieldView, context: Context) {
        toolbar.accountsButton.configure(account: account)
        toolbar.setHomeConfiguration(configuration, animated: toolbar.window != nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UniversalSearchFieldView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: 48)
    }
}
