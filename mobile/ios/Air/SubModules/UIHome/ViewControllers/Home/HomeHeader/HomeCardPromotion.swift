import Foundation
import Kingfisher
import Perception
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

private enum HomeCardPromotionLayout {
    static let cardWidth: CGFloat = 345
    static let cardHeight: CGFloat = 200
    static let defaultHitAreaSize: CGFloat = 64
}

struct HomeCardPromotionVisual: View {
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            if let promotion = accountContext.activePromotion, promotion.kind == .cardOverlay {
                _HomeCardPromotionVisual(promotion: promotion)
            } else {
                EmptyView()
            }
        }
    }
}

private struct _HomeCardPromotionVisual: View {
    let promotion: ApiPromotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Image.airBundle("PromoCardBg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)

                mascotView(for: geometry.size)

                Image.airBundle("PromoCardOverlay")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mascotView(for cardSize: CGSize) -> some View {
        if let mascotIcon = promotion.cardOverlay.mascotIcon,
           let mascotURLString = mascotIcon.url.nilIfEmpty,
           let mascotURL = URL(string: mascotURLString)
        {
            let frame = makeFrame(for: mascotIcon, cardSize: cardSize)
            KFImage(mascotURL)
                .placeholder {
                    Color.clear
                }
                .fade(duration: 0.15)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: frame.size.width, height: frame.size.height)
                .rotationEffect(.degrees(mascotIcon.rotation))
                .offset(x: frame.offset.x, y: frame.offset.y)
                .accessibilityHidden(true)
        }
    }

    private func makeFrame(for mascotIcon: ApiPromotion.CardOverlay.MascotIcon, cardSize: CGSize) -> (size: CGSize, offset: CGPoint) {
        (
            size: CGSize(
                width: cardSize.width * mascotIcon.width / HomeCardPromotionLayout.cardWidth,
                height: cardSize.height * mascotIcon.height / HomeCardPromotionLayout.cardHeight
            ),
            offset: CGPoint(
                x: mascotIcon.right,
                y: -mascotIcon.top
            )
        )
    }
}

struct HomeCardPromotionHitArea: View {
    let promotion: ApiPromotion?
    let cardSize: CGSize

    var body: some View {
        if let promotion, promotion.kind == .cardOverlay {
            let frame = hitAreaFrame(for: promotion)
            Button {
                handlePromotionTap(promotion)
            } label: {
                Color.clear
                    .frame(width: frame.size.width, height: frame.size.height)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(promotionAccessibilityLabel(promotion))
            .offset(x: frame.offset.x, y: frame.offset.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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

        return (
            size: CGSize(
                width: cardSize.width * mascotIcon.width / HomeCardPromotionLayout.cardWidth,
                height: cardSize.height * mascotIcon.height / HomeCardPromotionLayout.cardHeight
            ),
            offset: CGPoint(
                x: mascotIcon.right,
                y: -mascotIcon.top
            )
        )
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
