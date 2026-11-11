import Dependencies
import GRDB
import UIHome
import UIKit
import WalletResources
import XCTest
@testable import WalletCore
@testable import AirAsFramework

@MainActor
final class SidebarMarginsTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
            $0[AccountConfigStore.self] = AccountConfigStore()
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            super.invokeTest()
        }
    }

    @available(iOS 17, *)
    func testCardsAndRowsShareMarginsThroughResizingAndAccountSelection() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        try await database.write { database in
            for id in ["sidebar-first-mainnet", "sidebar-second-mainnet"] {
                try MAccount(id: id, title: id, type: .view,
                             byChain: [.tron: .init(address: "sidebar-fixture", isMultisig: true)]).insert(database)
            }
        }
        let store = _AccountStore(db: database)
        try store.use(db: database)
        defer { store.clean() }
        SettingsStore.liveValue.use(db: database)
        defer { SettingsStore.liveValue.clean() }
        @Dependency(\.accountSettings) var accountSettings
        await accountSettings.use(db: database)

        try await withDependencies {
            $0.accountStore = store
        } operation: {
            let accountIds = store.orderedAccountIds
            XCTAssertEqual(accountIds.count, 2)
            let banner = ApiPromotion(id: "sidebar-margin-offer", infoBanner: .init(
                title: "Offer", description: "Sidebar banner layout",
                actionButton: .init(title: "Learn more", onClickAction: .openEarn)
            ))
            for id in accountIds {
                AccountContext(accountId: id).config.banners.replace(home: [banner], staking: [])
            }
            for isRTL in [false, true] {
                let sidebar = SplitRootSidebarViewController(viewModel: SplitRootViewModel())
                sidebar.loadViewIfNeeded()
                sidebar.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
                sidebar.traitOverrides.layoutDirection = isRTL ? .rightToLeft : .leftToRight
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 388, height: 1000))
                window.rootViewController = sidebar
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                let selector = try XCTUnwrap(sidebar.view.subviews.compactMap { $0 as? HomeAccountSelector }.first)
                let cards = try XCTUnwrap(selector.subviews.compactMap { $0 as? UICollectionView }.first)
                let rows = try XCTUnwrap(sidebar.view.subviews.compactMap { $0 as? UICollectionView }.first)
                for (width, left, right) in [(388.0, 64.0, 0.0), (360, 0, 64), (466, 0, 0), (348, 0, 0)] {
                    window.frame.size.width = width
                    sidebar.view.frame = window.bounds
                    sidebar.additionalSafeAreaInsets = .init(top: 0, left: left, bottom: 0, right: right)
                    for (index, id) in accountIds.enumerated() {
                        sidebar.focusAccount(id, animated: false)
                        try await settle(window)
                        let expected = sidebar.view.layoutMarginsGuide.layoutFrame
                        let card = try XCTUnwrap(cards.cellForItem(at: IndexPath(item: index, section: 0)))
                        let cardFrame = card.convert(card.bounds, to: sidebar.view)
                        XCTAssertEqual(selector.frame.minX, 0)
                        XCTAssertEqual(selector.frame.width, sidebar.view.bounds.width)
                        XCTAssertEqual(cards.frame, selector.bounds)
                        XCTAssertEqual(cardFrame.minX, expected.minX, accuracy: 1)
                        XCTAssertEqual(cardFrame.maxX, expected.maxX, accuracy: 1)
                        XCTAssertEqual(card.bounds.height, selector.bounds.height, accuracy: 1)
                        XCTAssertEqual(rows.numberOfSections, 4)
                        for section in 0..<rows.numberOfSections {
                            for item in 0..<rows.numberOfItems(inSection: section) {
                                let attributes = try XCTUnwrap(rows.layoutAttributesForItem(at: IndexPath(item: item, section: section)))
                                let rowFrame = rows.convert(attributes.frame, to: sidebar.view)
                                XCTAssertEqual(rowFrame.minX, expected.minX, accuracy: 1, "Section \(section), RTL \(isRTL)")
                                XCTAssertEqual(rowFrame.maxX, expected.maxX, accuracy: 1, "Section \(section), RTL \(isRTL)")
                            }
                        }
                        XCTAssertEqual(rows.adjustedContentInset.left, 0)
                        XCTAssertEqual(rows.adjustedContentInset.right, 0)
                        XCTAssertEqual(rows.contentSize.width, rows.bounds.width, accuracy: 1)
                    }
                }
            }
        }
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
    }
}
