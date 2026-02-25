//
//  NftDetailsImage.swift
//  MyTonWalletAir
//
//  Created by nikstar on 01.07.2025.
//

import SwiftUI
import UIComponents
import WalletCore
import Perception

private let expandedImageMaxWidth: CGFloat = 600
private let imageBottomInset: CGFloat = 16

struct NftDetailsImage: View {
    
    var viewModel: NftDetailsViewModel
    private var listContextProvider: NftListContextProvider { viewModel.listContextProvider }
    
    @State private var coverFlowViewModel: CoverFlowViewModel<ApiNft>
    
    @Namespace private var ns
    
    init(viewModel: NftDetailsViewModel) {
        self.viewModel = viewModel
        self._coverFlowViewModel = State(
            wrappedValue: CoverFlowViewModel<ApiNft>(
                items: (NftStore.getAccountShownNfts(accountId: viewModel.account.id))?.values.map(\.nft) ?? [viewModel.nft],
                selectedItem: "",
                onTap: { },
                onLongTap: { }
            )
        )
    }
    
    @State var hideImage = false
    
    private var expandedImageSize: CGFloat {
        min(max(viewModel.containerWidth, collapsedImageSize), expandedImageMaxWidth)
    }
    
    private var currentImageSize: CGFloat {
        viewModel.state == .collapsed ? collapsedImageSize : expandedImageSize
    }
    
    private var currentTopInset: CGFloat {
        viewModel.state == .collapsed ? viewModel.collapsedTopInset : 0
    }
    
    private var currentSectionHeight: CGFloat {
        currentImageSize + currentTopInset + imageBottomInset
    }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            ZStack(alignment: .center) {
                NftImage(
                    nft: viewModel.nft,
                    animateIfPossible:/* viewModel.state != .collapsed &&*/ !viewModel.isAnimating && !hideImage,
                    playOnce: true
                )
                    .frame(width: currentImageSize, height: currentImageSize)
                    .clipShape(.rect(cornerRadius: viewModel.state == .collapsed ? 12 : 0))
                    .padding(.top, currentTopInset)
                    .padding(.bottom, imageBottomInset)
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
                    .id("coverFlow")
                    .scaleEffect(viewModel.isExpanded ? min(viewModel.containerWidth, expandedImageMaxWidth) / collapsedImageSize : 1.0, anchor: .top)
                    .opacity(viewModel.state != .collapsed ? 0 : 1)
                    .padding(.top, viewModel.collapsedTopInset)
                    .padding(.bottom, imageBottomInset)
                }
            }
            .onChange(of: viewModel.isExpanded) { isExpanded in
                print("isExpanded", isExpanded)
            }
            .onChange(of: viewModel.isAnimating) { isExpanded in
                print("isAnimating", isExpanded)
            }
            .onAppear {
                print("appear")
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: currentSectionHeight, alignment: .top)
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
                if let nft = NftStore.getAccountNfts(accountId: viewModel.account.id)?[nftId]?.nft ?? listContextProvider.nfts.first(id: nftId) {
                    withAnimation(.smooth(duration: 0.1)) {
                        viewModel.nft = nft
                    }
                }
            }
            .onPreferenceChange(CoverFlowIsScrollingPreference.self) { isScrolling in
                self.hideImage = isScrolling
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                viewModel.containerWidth = width
            }
        }
    }
}
