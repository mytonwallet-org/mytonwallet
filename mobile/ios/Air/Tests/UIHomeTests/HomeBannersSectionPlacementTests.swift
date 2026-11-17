import Dependencies
import XCTest
import UIComponents
@testable import WalletCore
@testable import UIHome

@MainActor
final class HomeBannersSectionPlacementTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
            $0[AccountConfigStore.self] = AccountConfigStore()
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            super.invokeTest()
        }
    }

    /// Only the current account's banners float above the toolbar, so a Home showing another account keeps its own
    func testOnlyTheCurrentAccountsBannersLeaveTheListWhileTheyFloat() {
        let placement = HomePromotionPlacement.shared
        let isOverlayInitially = placement.isOverlay
        let banners = AccountContext(accountId: "placement-mainnet").config.banners
        defer {
            placement.isOverlay = isOverlayInitially
            banners.replace(home: [], staking: [])
        }
        banners.replace(home: [ApiPromotion(id: "offer", infoBanner: .init(
            title: "Higher-yield staking available",
            description: "Tap Earn to restake your TON with higher returns.",
            actionButton: .init(title: "Restake Now", onClickAction: .openEarn)
        ))], staking: [])
        let section = HomeBannersSection()
        let context = AccountContext(accountId: "placement-mainnet")

        placement.isOverlay = false
        XCTAssertTrue(section.update(accountContext: context, canFloat: true))
        XCTAssertTrue(section.isVisible)

        placement.isOverlay = true
        XCTAssertTrue(section.update(accountContext: context, canFloat: true))
        XCTAssertFalse(section.isVisible)

        XCTAssertTrue(section.update(accountContext: context, canFloat: false))
        XCTAssertTrue(section.isVisible)
    }
}
