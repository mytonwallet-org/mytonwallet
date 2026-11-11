import Dependencies
import GRDB
import UIKit
import XCTest
import UIComponents
import UIEarn
import WalletContext
import WalletResources
@testable import WalletCore
@testable import UIHome

@MainActor
final class HomeBannerAppearanceTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
            $0[AccountConfigStore.self] = AccountConfigStore()
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            super.invokeTest()
        }
    }

    func testLoadedBannerAnimatesWithTokens() async throws {
        try await checkLoadedBanner(isMultichain: false)
    }

    func testLoadedBannerAnimatesWithFuturesAvailable() async throws {
        try await checkLoadedBanner(isMultichain: true)
    }

    private func checkLoadedBanner(isMultichain: Bool) async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion disables Home content animations")
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        var account = MAccount(id: "14444-mainnet", title: "Banner fixture", type: .mnemonic,
                              byChain: [.ton: .init(address: "banner-fixture")])
        if isMultichain { account.byChain["arbitrum"] = .init(address: "arbitrum-fixture") }
        let fixtureAccount = account
        try await database.write { database in
            try fixtureAccount.insert(database)
            try _ActivityStore.AccountState(accountId: fixtureAccount.id, byId: [:], idsMain: [],
                idsBySlug: [:], isMainHistoryEndReached: true, isHistoryEndReachedBySlug: [:]).insert(database)
        }
        SettingsStore.liveValue.use(db: database)
        await _ActivityStore.shared.use(db: database)
        @Dependency(\.accountSettings) var accountSettings
        await accountSettings.use(db: database)
        defer { SettingsStore.liveValue.clean() }

        try await withDependencies {
            $0.accountStore = _AccountStore(db: database)
        } operation: {
            _ = EarnVM.sharedTon
            let home = HomeVC(accountSource: .constant(account))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = WNavigationController(rootViewController: home)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(700))
            window.layoutIfNeeded()
            XCTAssertTrue(home.shouldAnimateContentUpdates)
            let tokens = try XCTUnwrap(home.visibleCustomSectionCell(id: "tokens"))
            let initialY = tokens.frame.minY
            let banners = AccountContext(accountId: account.id).config.banners
            banners.replace(home: [ApiPromotion(id: "offer", infoBanner: .init(
                title: "Higher-yield staking available",
                description: "Tap to restake your TON with higher returns.",
                actionButton: .init(title: "Restake Now", onClickAction: .openEarn)
            ))], staking: [])

            var positions: [CGFloat] = []
            var opacities: [Float] = []
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(16))
                positions.append(tokens.layer.presentation()?.frame.minY ?? tokens.frame.minY)
                if let banner = home.visibleCustomSectionCell(id: "home-banners") {
                    opacities.append(banner.layer.presentation()?.opacity ?? banner.layer.opacity)
                }
            }
            let finalY = tokens.frame.minY
            XCTAssertGreaterThan(finalY, initialY + 50)
            XCTAssertTrue(positions.contains { $0 > initialY + 1 && $0 < finalY - 1 },
                          "Tokens must slide through intermediate positions when the banner arrives")
            XCTAssertTrue(opacities.contains { $0 > 0 && $0 < 1 },
                          "The banner must fade in instead of appearing fully opaque")
        }
    }
}
