
import SwiftUI
import Perception

struct ActionsWithBackground: View {
    
    var viewModel: NftDetailsViewModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            NftDetailsActionsRow(viewModel: viewModel)
                .frame(maxWidth: .infinity)
                .offset(y: viewModel.isFullscreenPreviewOpen ? 100 : 0)
                .opacity(viewModel.shouldShowControls ? 1 : 0)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", nft: .sampleMtwCard, listContext: .none)
    @Previewable @Namespace var ns
    ZStack {
        Color.blue.opacity(0.2)
            .ignoresSafeArea()
        ActionsWithBackground(viewModel: viewModel)
            .aspectRatio(contentMode: .fit)
    }
}
#endif
