import Foundation
import Kingfisher
import Perception
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

private enum HomeCardPromotionLayout {
    private static let maskotWidthRatio: CGFloat = 1.072
    private static let maskotHeightRatio: CGFloat = 1.075
    static let defaultHitAreaSize: CGFloat = 64

    static func physicalTopTrailingAlignment(for layoutDirection: LayoutDirection) -> Alignment {
        layoutDirection == .rightToLeft ? .topLeading : .topTrailing
    }

    static func physicalTrailingOffset(_ offset: CGFloat, layoutDirection: LayoutDirection) -> CGFloat {
        layoutDirection == .rightToLeft ? -offset : offset
    }
    
    static func mascotFrame(for mascotIcon: ApiPromotion.CardOverlay.MascotIcon) -> (size: CGSize, offset: CGPoint) {
        (
            size: CGSize(
                width: mascotIcon.width * maskotWidthRatio,
                height: mascotIcon.height * maskotHeightRatio
            ),
            offset: CGPoint(
                x: mascotIcon.right,
                y: -mascotIcon.top
            )
        )
    }
}

struct HomeCardPromotionVisual: View {
    let accountContext: AccountContext

    var body: some View {
        if !IS_GRAM_WALLET {
            WithPerceptionTracking {
                let promotion = cardOverlayPromotion
                ZStack {
                    if let promotion {
                        _HomeCardPromotionVisual(promotion: promotion)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: 0.3), value: promotion?.id)
            }
        } else {
            EmptyView()
        }
    }

    private var cardOverlayPromotion: ApiPromotion? {
        guard let promotion = accountContext.activePromotion, promotion.kind == .cardOverlay else {
            return nil
        }
        return promotion
    }
}

private struct _HomeCardPromotionVisual: View {
    let promotion: ApiPromotion

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let alignment = HomeCardPromotionLayout.physicalTopTrailingAlignment(for: layoutDirection)
        ZStack(alignment: alignment) {
            Image.airBundle("PromoCardBg")
            mascotView()
            Image.airBundle("PromoCardOverlay")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func mascotView() -> some View {
        if let mascotIcon = promotion.cardOverlay.mascotIcon,
           let mascotURLString = mascotIcon.url.nilIfEmpty,
           let mascotURL = URL(string: mascotURLString)
        {
            let frame = HomeCardPromotionLayout.mascotFrame(for: mascotIcon)
            KFImage(mascotURL)
                .placeholder {
                    Color.clear
                }
                .fade(duration: 0.15)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: frame.size.width, height: frame.size.height)
                .rotationEffect(.degrees(mascotIcon.rotation))
                .offset(
                    x: HomeCardPromotionLayout.physicalTrailingOffset(frame.offset.x, layoutDirection: layoutDirection),
                    y: frame.offset.y
                )
        }
    }
}

struct HomeCardPromotionHitArea: View {
    let promotion: ApiPromotion?
    let cardSize: CGSize

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if !IS_GRAM_WALLET, let promotion, promotion.kind == .cardOverlay {
            let frame = hitAreaFrame(for: promotion)
            let alignment = HomeCardPromotionLayout.physicalTopTrailingAlignment(for: layoutDirection)
            Button {
                handlePromotionTap(promotion)
            } label: {
                Color.clear
                    .frame(width: frame.size.width, height: frame.size.height)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(promotionAccessibilityLabel(promotion))
            .offset(
                x: HomeCardPromotionLayout.physicalTrailingOffset(frame.offset.x, layoutDirection: layoutDirection),
                y: frame.offset.y
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        } else {
            EmptyView()
        }
    }

    private func hitAreaFrame(for promotion: ApiPromotion) -> (size: CGSize, offset: CGPoint) {
        guard let mascotIcon = promotion.cardOverlay.mascotIcon else {
            return (
                size: CGSize(width: HomeCardPromotionLayout.defaultHitAreaSize, height: HomeCardPromotionLayout.defaultHitAreaSize),
                offset: .zero
            )
        }
        
        return HomeCardPromotionLayout.mascotFrame(for: mascotIcon)
    }
}

@MainActor
private func handlePromotionTap(_ promotion: ApiPromotion) {
    switch promotion.cardOverlay.onClickAction {
    case .openPromotionModal:
        AppActions.showPromotion(promotion)
    case .openMintCardModal:
        AppActions.showUpgradeCard()
    }
}

private func promotionAccessibilityLabel(_ promotion: ApiPromotion) -> String {
    switch promotion.cardOverlay.onClickAction {
    case .openPromotionModal:
        promotion.modal?.title.nilIfEmpty
            ?? promotion.modal?.actionButton?.title.nilIfEmpty
            ?? lang("More")
    case .openMintCardModal:
        lang("Mint Cards")
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview("Promotion Card Overlay", traits: .sizeThatFitsLayout) {
    ZStack {
        MtwCardBackground(nft: nil)
            .aspectRatio(1 / CARD_RATIO, contentMode: .fit)
        _HomeCardPromotionVisual(promotion: DebugPromotionPreset.airPromotion)
    }
    .frame(width: 345, height: 200)
    .clipShape(.rect(cornerRadius: 26))
}
#endif
