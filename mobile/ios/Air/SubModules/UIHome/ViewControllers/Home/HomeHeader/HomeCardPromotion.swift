#if DEBUG
// Pre-migration SwiftUI reference for the Home Card Content Lab.
import Foundation
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

struct HomeCardPromotionHitArea: View {
    let promotion: ApiPromotion?
    let cardSize: CGSize

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let promotion, promotion.kind == .cardOverlay {
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
        guard let mascotIcon = promotion.cardOverlay?.mascotIcon else {
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
    guard let cardOverlay = promotion.cardOverlay else { return }
    switch cardOverlay.onClickAction {
    case .openPromotionModal:
        AppActions.showPromotion(promotion)
    case .openMintCardModal:
        AppActions.showUpgradeCard()
    }
}

private func promotionAccessibilityLabel(_ promotion: ApiPromotion) -> String {
    guard let cardOverlay = promotion.cardOverlay else { return lang("More") }
    return switch cardOverlay.onClickAction {
    case .openPromotionModal:
        promotion.modal?.title.nilIfEmpty
            ?? promotion.modal?.actionButton?.title.nilIfEmpty
            ?? lang("More")
    case .openMintCardModal:
        lang("Mint Cards")
    }
}

#endif
