
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

struct ConnectDappViewOrPlaceholder: View {

    let viewModel: ConnectViewModel
    var onHeightChange: (CGFloat) -> ()

    var body: some View {
        WithPerceptionTracking {
            let isLoading = viewModel.update == nil
            let dapp = viewModel.update?.dapp ?? ApiDapp.loadingStub

            ConnectDappView(viewModel: viewModel, isLoading: isLoading, dapp: dapp)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    onHeightChange(height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ConnectDappView: View {
    let viewModel: ConnectViewModel
    let isLoading: Bool
    let dapp: ApiDapp

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                HeaderView(dapp: dapp)
                    .padding(.top, 40)
                    .skeletonContainer(isActive: isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 24) {
                VStack(spacing: 24) {
                    Text(lang("$connect_dapp_description"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    SelectSection(viewModel: viewModel, isLoading: isLoading)

                    if !isLoading, let disabledReason = viewModel.disabledReason {
                        WarningView(text: disabledReason)
                            .padding(.horizontal, 20)
                            .padding(.top, -8)
                    }

                    ConnectButton(viewModel: viewModel)
                        .padding(.bottom, viewModel.extraBottomPadding)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

private struct HeaderView: View {

    var dapp: ApiDapp

    var body: some View {
        VStack(spacing: 16) {
            HeaderDappIcon(dapp: dapp)
                .skeletonPlaceholder(surface: .dark, cornerRadius: HeaderDappIcon.cornerRadius)
            VStack(spacing: 4) {
                Text(lang("$connect_dapp_title", arg1: dapp.name))
                    .airFont24h32(weight: .semibold)
                    .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
                HStack {
                    if dapp.shouldShowUrlTrustStatusWarning {
                        DappOriginWarning(urlTrustStatus: dapp.resolvedUrlTrustStatus)
                            .offset(y: 1)
                    }
                    Text(dapp.displayUrl)
                        .foregroundStyle(.tint)
                }
                .skeletonPlaceholder(surface: .dark)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

private struct SelectSection: View {

    let viewModel: ConnectViewModel
    let isLoading: Bool

    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: viewModel.onSelectWallet) {
                    HStack {
                        AccountListCell(accountContext: viewModel.accountContext, isReordering: false, showCurrentAccountHighlight: false)
                        InsetListChevron()
                    }
                }
                .allowsHitTesting(!isLoading)
            } header: {
                Text(lang("Selected Wallet"))
                    .padding(.top, 6)
                    .padding(.bottom, 5)
            }
        }
    }
}

private struct ConnectButton: View {

    let viewModel: ConnectViewModel

    var body: some View {
        WithPerceptionTracking {
            Button(action: viewModel.onConnectWallet) {
                Text(lang(isDangerous ? "Connect Anyway" : "Connect Wallet"))
            }
            .disabled(viewModel.isDisabled)
            .buttonStyle(isDangerous ? WUIButtonStyle(style: .destructive) : .airPrimary)
            .padding(.horizontal, 30)
        }
    }

    var isDangerous: Bool {
        viewModel.update?.dapp.resolvedUrlTrustStatus == .dangerous
    }
}

#if DEBUG
private struct ConnectDappViewOrPlaceholderPreview: View {
    let viewModel: ConnectViewModel

    var body: some View {
        ScrollView {
            ConnectDappViewOrPlaceholder(viewModel: viewModel, onHeightChange: { _ in })
        }
        .background(Color.air.sheetBackground)
    }
}

@available(iOS 18, *)
#Preview("Loading") {
    @Previewable @AccountContext(source: .current) var account: MAccount
    ConnectDappViewOrPlaceholderPreview(
        viewModel: ConnectViewModel(accountId: account.id, update: nil, onCancel: nil)
    )
}

@available(iOS 18, *)
#Preview("Connect") {
    ConnectDappViewOrPlaceholderPreview(
        viewModel: ConnectViewModel(
            accountId: ApiUpdate.DappConnect.sample.accountId,
            update: .sample,
            onCancel: {}
        )
    )
}
#endif
