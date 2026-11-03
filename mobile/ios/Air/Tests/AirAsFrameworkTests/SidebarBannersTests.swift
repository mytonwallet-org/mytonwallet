import Dependencies
import GRDB
import UIKit
import XCTest
import WalletResources
@testable import WalletCore
@testable import AirAsFramework

@MainActor
final class SidebarBannersTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
            $0[AccountConfigStore.self] = AccountConfigStore()
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            super.invokeTest()
        }
    }

    func testBannersFollowFocusedAccountAndDismissWithoutMovingTabActions() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            for accountId in ["first-mainnet", "second-mainnet"] {
                try MAccount(id: accountId, title: accountId, type: .mnemonic,
                    byChain: ["ton": AccountChain(address: "test-address")]).insert(db)
            }
        }
        @Dependency(\.accountSettings) var accountSettings
        await accountSettings.use(db: db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }

        let model = SplitRootViewModel()
        let sidebar = SplitRootSidebarViewController(viewModel: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 900))
        window.rootViewController = sidebar
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(sidebar.view.subviews.compactMap { $0 as? UICollectionView }.first)
        sidebar.focusAccount("first-mainnet", animated: false)
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 2)

        let first = AccountContext(accountId: "first-mainnet").config.banners
        let second = AccountContext(accountId: "second-mainnet").config.banners
        let banner = ApiPromotion(id: "offer", infoBanner: .init(
            title: "💎 Higher-yield staking available",
            description: "Tap Earn to restake your TON with higher returns.",
            actionButton: .init(title: "Restake Now", onClickAction: .openEarn)
        ))
        first.replace(home: [banner], staking: [])
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 3)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        let bannerFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
        let tabFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 1))).frame
        XCTAssertGreaterThan(bannerFrame.height, 44)
        XCTAssertLessThanOrEqual(bannerFrame.maxY, tabFrame.minY)
        let image = UIGraphicsImageRenderer(bounds: sidebar.view.bounds).image { context in
            sidebar.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Sidebar with promotion"
        attachment.lifetime = .keepAlways
        add(attachment)
        model.selectedTab = .explore
        _ = sidebar.collectionView(collection, shouldSelectItemAt: IndexPath(item: 0, section: 1))
        XCTAssertEqual(model.selectedTab, AppTabManager.shared.orderedTabIds.first)

        sidebar.focusAccount("second-mainnet", animated: false)
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 2)
        second.replace(home: [banner], staking: [])
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 3)
        second.dismissHome(id: banner.id)
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 2)
        XCTAssertEqual(first.home, [banner])

        sidebar.focusAccount("first-mainnet", animated: false)
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 3)
        first.replace(home: [], staking: [])
        try await settle(window)
        XCTAssertEqual(collection.numberOfSections, 2)
        model.selectedTab = .explore
        _ = sidebar.collectionView(collection, shouldSelectItemAt: IndexPath(item: 0, section: 0))
        XCTAssertEqual(model.selectedTab, AppTabManager.shared.orderedTabIds.first)
    }

    private func settle(_ window: UIWindow) async throws {
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
    }
}
