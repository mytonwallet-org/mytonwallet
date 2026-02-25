import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

@MainActor
@Perceptible
final class NftDetailsViewModel {

    enum State {
        case collapsed
        case expanded
        case preview
    }

    private var stateBeforePreview: State = .collapsed
    
    var state: State = .expanded {
        didSet {
            print("didSet state", state)
            if state != .preview {
                stateBeforePreview = state
            }
        }
    }
    
    var isExpanded: Bool {
        state == .expanded
    }
    
    var isFullscreenPreviewOpen: Bool {
        state == .preview
    }
    
    var nft: ApiNft
    var safeAreaInsets: UIEdgeInsets = .zero
    var y: CGFloat = 0
    var selectedSubmenu: String?
    var contentHeight: CGFloat = 2000.0
    var viewportHeight: CGFloat = 0.0
    var containerWidth: CGFloat = 0.0
    var isAnimatingSince: Date?
    
    var isAnimating: Bool { isAnimatingSince != nil }
    
    let listContextProvider: NftListContextProvider

    var shouldScaleOnDrag: Bool { isExpanded && !isFullscreenPreviewOpen }
    var shouldMaskAndClip: Bool { !isExpanded && !isFullscreenPreviewOpen }
    var shouldShowControls: Bool { !isFullscreenPreviewOpen }

    @PerceptionIgnored
    weak var viewController: NftDetailsVC?

    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(
        accountId: String,
        isExpanded: Bool = true,
        isFullscreenPreviewOpen: Bool = false,
        nft: ApiNft,
        listContext: NftCollectionFilter,
        fixedNfts: [ApiNft]? = nil
    ) {
        self._account = AccountContext(accountId: accountId)
        let initialState: State = isExpanded ? .expanded : .collapsed
        self.stateBeforePreview = initialState
        self.state = isFullscreenPreviewOpen ? .preview : initialState
        self.nft = nft
        self.listContextProvider = NftListContextProvider(accountId: accountId, filter: listContext, fixedNfts: fixedNfts)
    }
    
    var collapsedTopInset: CGFloat {
        safeAreaInsets.top - 8
    }
    
    func onImageTap() {
        switch state {
        case .collapsed:
            viewController?.updateIsExpanded(true)
        case .expanded:
            withAnimation(.spring(duration: 0.25)) {
                state = .preview
            }
        case .preview:
            withAnimation(.spring(duration: isExpanded ? 0.25 : 0.35)) {
                state = stateBeforePreview
            }
        }
    }
    
    func onImageLongTap() {
        if !isExpanded && !isFullscreenPreviewOpen {
            Haptics.play(.drag)
            withAnimation(.spring(duration: 0.3)) {
                state = .preview
            }
        } else { // fallback
            onImageTap()
        }
    }
    
    func onBack() {
        
    }
}
