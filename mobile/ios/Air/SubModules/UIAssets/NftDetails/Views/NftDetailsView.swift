
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import SwiftUIIntrospect

struct NftDetailsView: View {

    @ObservedObject var viewModel: NftDetailsViewModel
    
    var nft: ApiNft { viewModel.nft }
    var navigationBarInset: CGFloat { viewModel.navigationBarInset }
    
    @Namespace private var ns
    @State private var reloadCard: Int = 0
    
    var body: some View {
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
        let frame = UIScreen.main.bounds
        GeometryReader { geom in
            Color.red
                .opacity(0.2)
                .opacity(0)
                .matchedGeometryEffect(id: "fullScreenTarget", in: ns, anchor: .top, isSource: true)
                .frame(width: frame.width, height: frame.width)
                .offset(y: (frame.height - frame.width)/2)
                .offset(y: viewModel.isFullscreenPreviewOpen ? 0 : viewModel.y)
                .allowsHitTesting(false)
        }
    }
}
