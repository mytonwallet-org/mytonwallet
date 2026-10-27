import Dependencies
import Perception

@MainActor @Perceptible
public final class AccountBanners: Sendable {
    private let accountId: String
    private var homeSnapshot: [ApiPromotion] = []
    private var stakingSnapshot: [ApiPromotion] = []
    private var submittedStakingIds: Set<String> = []

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    private var settings: AccountSettings {
        @Dependency(\.accountSettings) var accountSettings
        return accountSettings.for(accountId: accountId)
    }

    public var home: [ApiPromotion] {
        let dismissedHomeIds = settings.dismissedHomeBannerIds
        let visibleLinks = Set(staking.compactMap(\.linkedBannerId))
        let allLinks = Set(stakingSnapshot.compactMap(\.linkedBannerId))
        return homeSnapshot.filter {
            !dismissedHomeIds.contains($0.id) && (!allLinks.contains($0.id) || visibleLinks.contains($0.id))
        }
    }

    public var staking: [ApiPromotion] {
        stakingSnapshot.filter { !submittedStakingIds.contains($0.id) }
    }

    func replace(home: [ApiPromotion], staking: [ApiPromotion]) {
        homeSnapshot = home
        stakingSnapshot = staking
        submittedStakingIds.formIntersection(staking.map(\.id))
    }

    public func dismissHome(id: String) {
        guard home.first?.id == id else { return }
        settings.dismissHomeBanner(id: id)
    }

    public func didSubmitUnstake(id: String) {
        guard stakingSnapshot.contains(where: { $0.id == id }) else { return }
        submittedStakingIds.insert(id)
    }
}
