
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher
import Perception

let mirrorStretchFactor: CGFloat = 2
let maxBlurRadius: CGFloat = 20
let blurHeight: CGFloat = 176
let mirrorHeight: CGFloat = 92
let collapsedImageSize: CGFloat = 144

struct NftDetailsHeaderView: View {
    
    var viewModel: NftDetailsViewModel
    var ns: Namespace.ID
    
    var nft: ApiNft { viewModel.nft }
    var isExpanded: Bool { viewModel.isExpanded }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            let layout = isExpanded ? AnyLayout(ZStackLayout(alignment: .bottom)) : AnyLayout(VStackLayout(spacing: 8))
            
            layout {
                image
                    .zIndex(-1)
                labels
                    .zIndex(1)
                    .padding(.bottom, viewModel.isExpanded ? mirrorHeight : 0)
                    .offset(y: viewModel.isFullscreenPreviewOpen ? 100 : 0)
                ActionsWithBackground(viewModel: viewModel)
            }
        }
    }
    
    @ViewBuilder
    var image: some View {
        Image(viewModel: viewModel, ns: ns)
    }

    var labels: some View {
        Labels(viewModel: viewModel)
    }
}

fileprivate struct Image: View {
    
    var viewModel: NftDetailsViewModel
    var ns: Namespace.ID
    
    var nft: ApiNft { viewModel.nft }
    var isExpanded: Bool { viewModel.isExpanded }
    
    @State private var isTouching: Bool = false
    
    var body: some View {
        NftDetailsImage(viewModel: viewModel)
    }
}

fileprivate struct Labels: View {
    
    var viewModel: NftDetailsViewModel
    
    var nft: ApiNft { viewModel.nft }
    var isExpanded: Bool { viewModel.isExpanded }
    
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("cf_animateTitleChange") var animateTitleChange: Bool = false
        
    var body: some View {
        WithPerceptionTracking {
            VStackLayout(alignment: isExpanded ? .leading : .center, spacing: 1) {
                Text(nft.displayName)
                    .font(.system(size: viewModel.isExpanded ? 22 : 29, weight: .medium))
                if let collection = nft.collection {
                    NftCollectionButton(name: collection.name, onTap: {
                        AppActions.showAssets(accountSource: .accountId(viewModel.accountId), selectedTab: 1, collectionsFilter: .collection(collection))
                    })
                } else {
                    Text(lang("Standalone NFT"))
                        .font(.system(size: 16))
                        .frame(height: 24)
                }
            }
            .padding(.horizontal, 16)
            .drawingGroup()
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .environment(\.colorScheme, isExpanded ? .dark : colorScheme)
            .opacity(viewModel.shouldShowControls ? 1 : 0)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 350)
            .transition(.opacity)
            //        .id(animateTitleChange ? "titleLabels" : nft.id)
        }
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", isExpanded: true, isFullscreenPreviewOpen: true, nft: .sampleMtwCard, listContext: .none, navigationBarInset: 0)
    @Previewable @Namespace var ns
    NftDetailsHeaderView(viewModel: viewModel, ns: ns)
        .background(Color.blue.opacity(0.2))
        .aspectRatio(contentMode: .fit)
}
#endif
