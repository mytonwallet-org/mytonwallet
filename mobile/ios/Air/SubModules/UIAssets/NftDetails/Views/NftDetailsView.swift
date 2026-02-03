
import SwiftUI
import UIComponents
import Perception

struct NftDetailsView: View {

    var viewModel: NftDetailsViewModel
    
    @Namespace private var ns
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            ZStack(alignment: .top) {

                Color.clear
                VStack(spacing: 0) {
                    listContent
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                            viewModel.contentHeight = height
                        }
                    Spacer(minLength: 0)
                }
                
                
            }
            .overlay(alignment: .top) {
                fullscreenViewerTarget
            }
            .padding(.top, -viewModel.safeAreaInsets.top)
            .ignoresSafeArea(edges: .top)
            .coordinateSpace(name: ns)
        }
    }

    @ViewBuilder
    var listContent: some View {
        headerView
            .fixedSize(horizontal: false, vertical: true)
            
        detailsSection
            .offset(y: viewModel.isFullscreenPreviewOpen ? 500 : 0)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(viewModel.shouldShowControls ? 1 : 0)
    }
    
    @ViewBuilder
    var headerView: some View {
        NftDetailsHeaderView(viewModel: viewModel, ns: ns)
            .matchedGeometryEffect(id: viewModel.isFullscreenPreviewOpen ? "fullScreenTarget" : "", in: ns, properties: .position, anchor: .top, isSource: false)
    }
    
    @ViewBuilder
    var detailsSection: some View {
        NftDetailsDetailsView(viewModel: viewModel)
    }
    
    @ViewBuilder
    var fullscreenViewerTarget: some View {
        let screenSize = screenSize
        GeometryReader { _ in
            WithPerceptionTracking {
                Color.clear
                    .matchedGeometryEffect(id: "fullScreenTarget", in: ns, anchor: .top, isSource: true)
                    .frame(width: screenSize.width, height: screenSize.width)
                    .offset(y: (screenSize.height - screenSize.width)/2)
                    .offset(y: viewModel.isFullscreenPreviewOpen ? 0 : viewModel.y)
                    .allowsHitTesting(false)
            }
        }
    }
}
