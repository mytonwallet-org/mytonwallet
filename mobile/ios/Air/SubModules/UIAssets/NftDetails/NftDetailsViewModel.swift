import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class NftDetailsViewModel: ObservableObject {
    
    enum State {
        case collapsed
        case expanded
        case preview
    }
   
    @Published var isExpanded = true
    @Published var nft: ApiNft
    @Published var navigationBarInset: CGFloat
    @Published var safeAreaInsets: UIEdgeInsets = .zero
    @Published var y: CGFloat = 0
    @Published var isFullscreenPreviewOpen = false
    @Published var selectedSubmenu: String?
    @Published var contentHeight: CGFloat = 2000.0
    @Published var isAnimatingSince: Date?
    
    var isAnimating: Bool { isAnimatingSince != nil }
    
    var accountId: String
    
    let listContextProvider: NftListContextProvider
    
    var state: State {
        isFullscreenPreviewOpen ? .preview : isExpanded ? .expanded : .collapsed
    }

    var shouldScaleOnDrag: Bool { isExpanded && !isFullscreenPreviewOpen }
    var shouldMaskAndClip: Bool { !isExpanded && !isFullscreenPreviewOpen }
    var shouldShowControls: Bool { !isFullscreenPreviewOpen }
    
    weak var viewController: NftDetailsVC?
    
    init(accountId: String, isExpanded: Bool = true, isFullscreenPreviewOpen: Bool = false, nft: ApiNft, listContext: NftCollectionFilter, navigationBarInset: CGFloat) {
        self.accountId = accountId
        self.isExpanded = isExpanded
        self.isFullscreenPreviewOpen = isFullscreenPreviewOpen
        self.nft = nft
        self.listContextProvider = NftListContextProvider(accountId: accountId,  filter: listContext)
        self.navigationBarInset = navigationBarInset
    }
    
    var collapsedTopInset: CGFloat {
        44 + safeAreaInsets.top + (IOS_26_MODE_ENABLED ? -52 : 0)
    }
    
    var onHeightChange: (CGFloat) -> () = { _ in }
    
    func onImageTap() {
        switch state {
        case .collapsed:
            viewController?.updateIsExpanded(true)
        case .expanded:
            withAnimation(.spring(duration: 0.25)) {
                isFullscreenPreviewOpen = true
            }
        case .preview:
            withAnimation(.spring(duration: isExpanded ? 0.25 : 0.35)) {
                isFullscreenPreviewOpen = false
            }
        }
    }
    
    func onImageLongTap() {
        if !isExpanded && !isFullscreenPreviewOpen {
            Haptics.play(.drag)
            withAnimation(.spring(duration: 0.3)) {
                isFullscreenPreviewOpen = true
            }
        } else { // fallback
            onImageTap()
        }
    }
}
