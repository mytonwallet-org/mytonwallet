//
//  NftDetailsImage.swift
//  MyTonWalletAir
//
//  Created by nikstar on 01.07.2025.
//

import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct NftDetailsImage: View {
    
    @ObservedObject var viewModel: NftDetailsViewModel
    private var listContextProvider: NftListContextProvider { viewModel.listContextProvider }
    
    @StateObject private var coverFlowViewModel = CoverFlowViewModel<ApiNft>(
        items: Array((NftStore.currentAccountShownNfts ?? [:]).values.map(\.nft)),
        selectedItem: "",
        onTap: { },
        onLongTap: { }
    )
    
    @Namespace private var ns
    
    init(viewModel: NftDetailsViewModel) {
        self.viewModel = viewModel
    }
    
    @State var hideImage = false
    
    var body: some View {
        ZStack(alignment: .center) {
            NftImage(
                nft: viewModel.nft,
                animateIfPossible:/* viewModel.state != .collapsed &&*/ !viewModel.isAnimating && !hideImage,
                playOnce: true
            )
                .aspectRatio(1, contentMode: .fit)
//                .overlay { Color.blue }
                .clipShape(.rect(cornerRadius: viewModel.state == .collapsed ? 12 : 0))
                .frame(height: viewModel.state != .collapsed ? nil : 144)
                .padding(.top, viewModel.state != .collapsed ? 0 : viewModel.safeAreaInsets.top + 44)
                .padding(.bottom, viewModel.isExpanded ? mirrorHeight : 16)
                .gesture(LongPressGesture(minimumDuration: 0.25, maximumDistance: 20)
                    .onEnded { _ in
                        viewModel.onImageLongTap()
                    })
                ._onButtonGesture { _ in
                } perform: {
                    viewModel.onImageTap()
                }
                .zIndex(1)
                .opacity(hideImage && viewModel.state == .collapsed ? 0 : 1)
//                .opacity(0.2)
//                .hidden()
                .allowsHitTesting(viewModel.state != .collapsed)
//                .matchedGeometryEffect(id: viewModel.isExpanded ? coverFlowViewModel.selectedItem : "", in: ns, isSource: true)
            
            if #available(iOS 17, *) {
                CoverFlowView(
                    viewModel: viewModel,
                    selectedId: viewModel.nft.id,
                    onSelect: { id in
                        coverFlowViewModel.selectedItem = id
                    }
                )
//                CoverFlow(isExpanded: false, viewModel: coverFlowViewModel) { nft in
//                    NftCoverFlowItem(nft: nft, hideImage: hideImage)
//                }
                .id("coverFlow")
                .visualEffect { [isExpanded = viewModel.isExpanded] content, geom in
                    content
                        .scaleEffect(isExpanded ? UIScreen.main.bounds.size.width/144.0 : 1.0, anchor: .top)
                }
                .opacity(viewModel.state != .collapsed ? 0 : 1)
                .padding(.top, viewModel.state != .collapsed ? 0 : viewModel.safeAreaInsets.top + 44)
                .padding(.bottom, viewModel.isExpanded ? mirrorHeight : 16)
            }
        }
        .scaleEffect(viewModel.state == .expanded ? max(1, 1 - viewModel.y * 0.005) : 1, anchor: .center)
        .onAppear {
            coverFlowViewModel.items = listContextProvider.nfts
            coverFlowViewModel.selectedItem = viewModel.nft.id
            coverFlowViewModel.onTap = {
                viewModel.onImageTap()
            }
            coverFlowViewModel.onLongTap = {
                viewModel.onImageLongTap()
            }
        }
        .coordinateSpace(name: ns)
        .onChange(of: coverFlowViewModel.selectedItem) { nftId in
            if let nft = NftStore.currentAccountNfts?[nftId]?.nft {
                withAnimation(.smooth(duration: 0.1)) {
                    viewModel.nft = nft
                }
            }
        }
        .onPreferenceChange(CoverFlowIsScrollingPreference.self) { isScrolling in
            self.hideImage = isScrolling
        }
    }
}


struct NftCoverFlowItem: View {
    
    var nft: ApiNft
    var hideImage: Bool
    
    @Environment(\.coverFlowIsCurrent) private var isCurrent
    
    var body: some View {
        NftImage(nft: nft, animateIfPossible: false)
//            .opacity(isCurrent && !hideImage ? 0 : 1)
            .contentShape(.containerRelative)
    }
}
