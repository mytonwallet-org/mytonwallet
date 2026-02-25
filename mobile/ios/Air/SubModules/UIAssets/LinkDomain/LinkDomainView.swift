import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception
import Dependencies

struct LinkDomainView: View {
    let viewModel: LinkDomainViewModel

    @Dependency(\.tokenStore) private var tokenStore

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            InsetList(topPadding: 16, spacing: 24) {
                if let nft = viewModel.nft {
                    InsetSection {
                        NftPreviewRow(nft: nft, verticalPadding: 12)
                    }
                }
                InsetSection {
                    LinkDomainAddressInput(viewModel: viewModel)
                } header: {
                    Text(viewModel.addressLabel)
                } footer: {
                    if let fee = viewModel.fee, let chain = viewModel.nft?.chain {
                        FeeView(
                            token: tokenStore.getNativeToken(chain: chain),
                            nativeToken: tokenStore.getNativeToken(chain: chain),
                            fee: fee,
                            explainedTransferFee: nil,
                            includeLabel: true
                        )
                        .transition(.opacity.animation(.default))
                    }
                }
                if let error = viewModel.errorMessage {
                    WarningView(text: error, kind: .error)
                        .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .task(id: viewModel.nft?.id) {
                await viewModel.loadDraft()
            }
        }
    }

    private var bottomBar: some View {
        Button(action: { viewModel.onLink?() }) {
            Text(viewModel.linkButtonTitle)
        }
        .buttonStyle(.airPrimary)
        .disabled(!viewModel.canLink)
        .environment(\.isLoading, viewModel.isButtonLoading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(WTheme.sheetBackground))
    }
}

struct LinkDomainNavigationHeader: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(viewModel.title)
            }
        }
    }
}

private struct LinkDomainAddressInput: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            InsetCell {
                @Perception.Bindable var viewModel = viewModel
                HStack {
                    AddressTextField(
                        value: $viewModel.walletAddress,
                        isFocused: $viewModel.isAddressFocused,
                        onNext: { viewModel.isAddressFocused = false }
                    )
                    .offset(y: 1)
                    .background(alignment: .leading) {
                        if viewModel.walletAddress.isEmpty {
                            Text(lang("Wallet address or domain"))
                                .foregroundStyle(Color(UIColor.placeholderText))
                        }
                    }
                    .opacity(!viewModel.walletAddress.isEmpty && !viewModel.isAddressFocused ? 0 : 1)
                    .overlay(alignment: .leading) {
                        if !viewModel.walletAddress.isEmpty && !viewModel.isAddressFocused {
                            LinkDomainResolvedAddressView(viewModel: viewModel)
                        }
                    }
                    
                    if viewModel.walletAddress.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: onPaste) {
                                Text(lang("Paste"))
                            }
                            Button(action: onScan) {
                                Image.airBundle("ScanIcon")
                            }
                        }
                        .offset(x: 4)
                        .padding(.vertical, -1)
                    } else {
                        Button(action: onClear) {
                            Image(systemName: "xmark.circle.fill")
                                .tint(Color(WTheme.secondaryLabel))
                                .imageScale(.small)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func onPaste() {
        if let pastedAddress = UIPasteboard.general.string, !pastedAddress.isEmpty {
            viewModel.walletAddress = pastedAddress
            endEditing()
        } else {
            AppActions.showToast(message: lang("Clipboard empty"))
        }
    }

    private func onScan() {
        Task {
            endEditing()
            if let result = await AppActions.scanQR() {
                endEditing()
                viewModel.applyScanResult(result)
            }
        }
    }

    private func onClear() {
        viewModel.walletAddress = ""
        viewModel.walletAddressName = nil
        viewModel.resolvedWalletAddress = nil
    }
}

private struct LinkDomainResolvedAddressView: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            let display = viewModel.displayComponents()
            HStack(spacing: 4) {
                if let primary = display.primary {
                    Text(primary)
                        .foregroundStyle(Color.air.primaryLabel)
                        .truncationMode(.middle)
                }
                if let secondary = display.secondary {
                    Text("·")
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(secondary)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
            }
            .animation(.default, value: display.primary)
            .animation(.default, value: display.secondary)
        }
    }
}
