
import SwiftUI
import UIKit
import WalletCore
import WalletContext
import UIComponents
import Perception


internal struct NftCell: View {
    
    var nft: ApiNft?
    var compactMode: Bool
    
    var isHighlighted: Bool
    var animateIfPossible: Bool
    
    var scrollingContext: ScrollingContext
    @State private var startedAnimation: Bool = false
    
    init(nft: ApiNft? = nil, compactMode: Bool, isHighlighted: Bool, animateIfPossible: Bool, scrollingContext: ScrollingContext) {
        self.nft = nft
        self.compactMode = compactMode
        self.isHighlighted = isHighlighted
        self.animateIfPossible = animateIfPossible
        self.scrollingContext = scrollingContext
    }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var scrollingContext = scrollingContext
            ZStack {
                Color(compactMode ? WTheme.groupedItem : WTheme.pickerBackground)
    
                let nft = self.nft ?? ApiNft.ERROR
                VStack(spacing: 8) {
                    ZStack {
                        Color(WTheme.secondaryFill)
                        NftImage(nft: nft, animateIfPossible: animateIfPossible && startedAnimation, loadFullSize: false)
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: compactMode ? 8 : 12))
                    .highlightScale(isHighlighted, scale: 0.85, isEnabled: true)
                    
                    if !compactMode {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nft.name?.nilIfEmpty ?? formatStartEndAddress(nft.address, prefix: 4, suffix: 4))
                                .font(.system(size: 14))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(nft.collectionName?.nilIfEmpty ?? lang("Standalone NFT"))
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundStyle(Color(WTheme.secondaryLabel))
                        }
                    }
                }
            }
            .onAppear {
                startedAnimation = !scrollingContext.isScrolling
            }
            .onChange(of: nft?.address) { _ in
                startedAnimation = !scrollingContext.isScrolling
            }
            .onChange(of: scrollingContext.isScrolling) { isScrolling in
                if !isScrolling {
                    startedAnimation = true
                }
            }
        }
    }
}
