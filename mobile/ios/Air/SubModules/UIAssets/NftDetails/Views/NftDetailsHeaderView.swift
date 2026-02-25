
import SwiftUI
import WalletContext
import WalletCore
import Perception

let collapsedImageSize: CGFloat = 144

struct NftDetailsHeaderView: View {
    
    var viewModel: NftDetailsViewModel
    var ns: Namespace.ID
    
    var nft: ApiNft { viewModel.nft }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            VStackLayout(spacing: 8) {
                image
                labels
                    .offset(y: viewModel.isFullscreenPreviewOpen ? 100 : 0)
                ActionsWithBackground(viewModel: viewModel)
            }
        }
    }
    
    @ViewBuilder
    var image: some View {
        Image(viewModel: viewModel, ns: ns)
            .padding(.top, 100)
            .clipped()
            .padding(.top, -100)
    }

    var labels: some View {
        Labels(viewModel: viewModel)
    }
}

fileprivate struct Image: View {
    
    var viewModel: NftDetailsViewModel
    var ns: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            NftDetailsImage(viewModel: viewModel)
        }
    }
}

private struct Labels: View {
    
    var viewModel: NftDetailsViewModel
    
    var nft: ApiNft { viewModel.nft }
    
    var body: some View {
        WithPerceptionTracking {
            VStackLayout(alignment: .center, spacing: 1) {
                Text(nft.displayName)
                    .font(.system(size: 29, weight: .medium))
                if let collection = nft.collection {
                    NftCollectionButton(name: collection.name, onTap: {
                        AppActions.showAssets(accountSource: .accountId(viewModel.account.id), selectedTab: 1, collectionsFilter: .collection(collection))
                    })
                } else {
                    Text(lang("Standalone NFT"))
                        .font(.system(size: 16))
                        .frame(height: 24)
                }
            }
            .padding(.horizontal, 16)
            .drawingGroup()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(viewModel.shouldShowControls ? 1 : 0)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 350)
            .transition(.opacity)
        }
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", isExpanded: true, isFullscreenPreviewOpen: true, nft: .sampleMtwCard, listContext: .none)
    @Previewable @Namespace var ns
    NftDetailsHeaderView(viewModel: viewModel, ns: ns)
        .background(Color.blue.opacity(0.2))
        .aspectRatio(contentMode: .fit)
}
#endif
