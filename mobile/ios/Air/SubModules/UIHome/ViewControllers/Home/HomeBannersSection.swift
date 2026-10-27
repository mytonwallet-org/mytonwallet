import Perception
import SwiftUI
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

@MainActor @Perceptible
public final class HomeBannersSection {
    public let id = "home-banners"
    public private(set) var isVisible = false
    private var accountContext: AccountContext?
    private let topSpacing: CGFloat
    private let bottomSpacing: CGFloat

    @PerceptionIgnored private lazy var registration = UICollectionView.CellRegistration<UICollectionViewCell, ActivityListViewController.Row> { [weak self] cell, _, _ in
        guard let accountContext = self?.accountContext else { return }
        cell.contentConfiguration = UIHostingConfiguration {
            HomeAccountBannersView(accountContext: accountContext)
        }
        .background { Color.clear }
        .margins(.all, 0)
    }

    @PerceptionIgnored public lazy var descriptor = ActivityListViewController.CustomSectionDescriptor(id: id, usesInsetGroupedMargins: true, topSpacing: topSpacing, bottomSpacing: bottomSpacing) { [unowned self] collectionView, indexPath in
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: .custom(id))
    }

    public init(topSpacing: CGFloat = 0, bottomSpacing: CGFloat = 8) {
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
        // UIKit requires registration before the diffable data source requests a cell.
        _ = registration
    }

    public func update(accountContext: AccountContext) -> Bool {
        let isVisible = !accountContext.config.banners.home.isEmpty
        let changed = self.accountContext?.accountId != accountContext.accountId || self.isVisible != isVisible
        if self.accountContext?.accountId != accountContext.accountId { self.accountContext = accountContext }
        if self.isVisible != isVisible { self.isVisible = isVisible }
        return changed
    }
}

private struct HomeAccountBannersView: View {
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            let banners = accountContext.config.banners
            HomePromotionStack(
                promotions: banners.home,
                onAction: { promotion in
                    guard banners.home.first?.id == promotion.id else { return }
                    AppActions.showAddStake(accountContext: accountContext, tokenSlug: TONCOIN_SLUG)
                },
                onDismiss: { banners.dismissHome(id: $0.id) }
            )
            // Keep the same spacing to assets when the final backplate disappears.
            .padding(.bottom, banners.home.count == 1 ? 8 : 0)
        }
    }
}
