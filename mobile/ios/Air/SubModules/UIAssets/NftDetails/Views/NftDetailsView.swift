
import SwiftUI
import UIComponents
import Perception

private let expandedContentMaxWidth: CGFloat = 600

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
        VStack(spacing: 0) {
            headerView
                .fixedSize(horizontal: false, vertical: true)
                
            detailsSection
                .offset(y: viewModel.isFullscreenPreviewOpen ? 500 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(viewModel.shouldShowControls ? 1 : 0)
        }
    }
    
    @ViewBuilder
    var headerView: some View {
        NftDetailsHeaderView(viewModel: viewModel, ns: ns)
            .frame(maxWidth: viewModel.isExpanded ? expandedContentMaxWidth : .infinity)
            .frame(maxWidth: .infinity)
            .matchedGeometryEffect(id: viewModel.isFullscreenPreviewOpen ? "fullScreenTarget" : "", in: ns, properties: .position, anchor: .top, isSource: false)
    }
    
    @ViewBuilder
    var detailsSection: some View {
        NftDetailsDetailsView(viewModel: viewModel)
    }
    
    @ViewBuilder
    var fullscreenViewerTarget: some View {
        GeometryReader { proxy in
            let size = proxy.size
            WithPerceptionTracking {
                let viewportHeight = viewModel.viewportHeight > 0 ? viewModel.viewportHeight : size.height
                Color.clear
                    .matchedGeometryEffect(id: "fullScreenTarget", in: ns, anchor: .top, isSource: true)
                    .frame(width: size.width, height: size.width)
                    .offset(y: (viewportHeight - size.width)/2)
                    .offset(y: viewModel.isFullscreenPreviewOpen ? 0 : viewModel.y)
                    .allowsHitTesting(false)
            }
        }
    }
}
