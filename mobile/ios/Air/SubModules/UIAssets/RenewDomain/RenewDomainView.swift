import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception
import Dependencies

struct RenewDomainView: View {
    
    let viewModel: RenewDomainViewModel

    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            InsetList(topPadding: 16, spacing: 24) {
                InsetSection {
                    ForEach(viewModel.nfts, id: \.id) { nft in
                        NftPreviewRow(nft: nft, verticalPadding: 12)
                    }
                } footer: {
                    if let fee = viewModel.fee, let chain = viewModel.nfts.first?.chain {
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
            .task(id: viewModel.nfts.count) {
                await viewModel.loadDraft()
            }
        }
    }

    private var bottomBar: some View {
        Button(action: { viewModel.onRenew?() }) {
            Text(viewModel.renewButtonTitle)
        }
        .buttonStyle(.airPrimary)
        .disabled(!viewModel.canRenew)
        .environment(\.isLoading, viewModel.isButtonLoading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(WTheme.sheetBackground))
    }
}

struct RenewDomainNavigationHeader: View {
    var viewModel: RenewDomainViewModel
    
    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(viewModel.title)
            } subtitle: {
                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                }
            }
        }
    }
}
