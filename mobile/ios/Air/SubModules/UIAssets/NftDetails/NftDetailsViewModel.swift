import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

@MainActor
@Perceptible
final class NftDetailsViewModel {
    
    enum State {
        case collapsed
        case expanded
        case preview
    }
   
    var isExpanded = true
    var nft: ApiNft
    var navigationBarInset: CGFloat
    var safeAreaInsets: UIEdgeInsets = .zero
    var y: CGFloat = 0
    var isFullscreenPreviewOpen = false
    var selectedSubmenu: String?
    var contentHeight: CGFloat = 2000.0
    var isAnimatingSince: Date?
    
    var isAnimating: Bool { isAnimatingSince != nil }
    
    @PerceptionIgnored
    var accountId: String
    
    let listContextProvider: NftListContextProvider
    
    var state: State {
        isFullscreenPreviewOpen ? .preview : isExpanded ? .expanded : .collapsed
    }

    var shouldScaleOnDrag: Bool { isExpanded && !isFullscreenPreviewOpen }
    var shouldMaskAndClip: Bool { !isExpanded && !isFullscreenPreviewOpen }
    var shouldShowControls: Bool { !isFullscreenPreviewOpen }
    
    @PerceptionIgnored
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
