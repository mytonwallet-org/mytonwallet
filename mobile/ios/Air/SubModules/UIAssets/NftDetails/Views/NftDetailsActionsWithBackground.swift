
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher

struct ActionsWithBackground: View {
    
    @ObservedObject var viewModel: NftDetailsViewModel
    
    var body: some View {
        NftDetailsActionsRow(viewModel: viewModel)
            .fixedSize(horizontal: IOS_26_MODE_ENABLED, vertical: false)
            .frame(maxWidth: IOS_26_MODE_ENABLED ? .infinity : nil)
            .offset(y: viewModel.isFullscreenPreviewOpen ? 100 : 0)
            .background(alignment: .bottom) {
                darkenAndBlurBackground
            }
            .background(alignment: .top) {
                mirroredImageBackground
            }
            .mask {
                Rectangle().padding(.top, -500)
            }
            .opacity(viewModel.shouldShowControls ? 1 : 0)
    }
    
    @ViewBuilder
    var darkenAndBlurBackground: some View {
        ZStack {
            // TODO: consider removing this
            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.32),
                    
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(viewModel.isExpanded && viewModel.shouldShowControls ? 1 : 0)
            
            BackgroundBlur(radius: 20)
                .frame(height: blurHeight)
                .mask {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0),    location: 0),
                                    .init(color: .black.opacity(0.3),  location: 0.1),
                                    .init(color: .black.opacity(0.6),  location: 0.2),
                                    .init(color: .black.opacity(0.85), location: 0.3),
                                    .init(color: .black.opacity(0.98), location: 0.4),
                                    .init(color: .black.opacity(1),    location: 0.5),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
        }
        .allowsHitTesting(false)
        .mask {
            Rectangle().fill()
                .padding(.top, viewModel.isExpanded && viewModel.shouldShowControls ? 0 : 80)
        }
    }
    
    @ViewBuilder
    var mirroredImageBackground: some View {
        KFImage(URL(string: viewModel.nft.image ?? ""))
            .resizable()
            .loadDiskFileSynchronously(false)
            .aspectRatio(contentMode: .fill)
            .transformEffect(.init(scaleX: 1, y: -mirrorStretchFactor))
            .alignmentGuide(VerticalAlignment.top, computeValue: { dims in -mirrorStretchFactor * dims.height })
            .opacity(viewModel.isExpanded && viewModel.shouldShowControls ? 1 : 0)
            .allowsHitTesting(false)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", nft: .sampleMtwCard, listContext: .none, navigationBarInset: 0)
    @Previewable @Namespace var ns
    ZStack {
        Color.blue.opacity(0.2)
            .ignoresSafeArea()
        ActionsWithBackground(viewModel: viewModel)
            .aspectRatio(contentMode: .fit)
    }
}
#endif
