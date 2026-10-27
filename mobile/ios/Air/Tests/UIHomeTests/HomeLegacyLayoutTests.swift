import Dependencies
import GRDB
import UIKit
import XCTest
import UIAssets
import UIComponents
import UIEarn
import WalletContext
import WalletResources
@testable import WalletCore
@testable import UIHome

@MainActor
final class HomeLegacyLayoutTests: XCTestCase {
    func testHomeAllocatesTokenRowsCardSpacingAndCollectibles() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(id: "870001-mainnet", title: "Layout fixture", type: .mnemonic,
                               byChain: [.ton: .init(address: "layout-fixture")])
        try await db.write { db in
            try account.insert(db)
            try _ActivityStore.AccountState(accountId: account.id, byId: [:], idsMain: [],
                idsBySlug: [:], isMainHistoryEndReached: true, isHistoryEndReachedBySlug: [:]).insert(db)
        }
        SettingsStore.liveValue.use(db: db)
        await _ActivityStore.shared.use(db: db)
        defer {
            SettingsStore.liveValue.clean()
            BalancesStore.for(accountId: account.id).replaceAll(byChain: [:])
            NftStore.walletCore(event: .accountDeleted(accountId: account.id))
        }
        try await withDependencies {
            $0.context = .live
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            // Home schedules this singleton's first access outside the dependency scope.
            _ = EarnVM.sharedTon
            AppStorageHelper.hideNoCostTokens = false
            BalancesStore.for(accountId: account.id).replace(chain: .ton, balances: [
                TONCOIN_SLUG: 1_000_000_000, "layout-token-2": 100, "layout-token-3": 200,
            ])
            BalanceDataStore.walletCore(event: .rawBalancesChanged(accountId: account.id))
            var nft = ApiNft.sample
            nft.address = "layout-nft"
            nft.collectionAddress = nil
            nft.image = nil
            nft.thumbnail = nil
            NftStore.walletCore(event: .updateNfts(.init(accountId: account.id, nfts: [nft], chain: .ton)))
            for _ in 0..<100 where BalanceDataStore.walletTokensData(accountId: account.id) == nil
                || NftStore.getAccountNfts(accountId: account.id)?.count != 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
            let home = HomeVC(accountSource: .constant(account))
            let navigation = WNavigationController(rootViewController: home)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()

            let rows = home.collectionView.visibleCells.compactMap { $0 as? WalletTokenCell }
            XCTAssertGreaterThanOrEqual(rows.count, 3)
            for row in rows {
                XCTAssertEqual(row.bounds.height, WalletTokenCell.defaultHeight, accuracy: 0.5)
                XCTAssertEqual(row.contentView.bounds.height, row.bounds.height, accuracy: 0.5)
                let content = try XCTUnwrap(row.contentView.subviews.first)
                XCTAssertEqual(content.bounds.height, row.bounds.height, accuracy: 0.5)
            }
            let views = descendants(of: home.view)
            let actions = try XCTUnwrap(views.compactMap { $0 as? ActionsContainerView }.first)
            let header = try XCTUnwrap(views.compactMap { $0 as? HomeHeaderContainer }.first)
            let actionsFrame = actions.convert(actions.bounds, to: home.view)
            let headerFrame = header.convert(header.bounds, to: home.view)
            XCTAssertEqual(actionsFrame.minY - headerFrame.maxY, 16, accuracy: 0.5)
            attach(window, name: "Home initial layout")

            let assetsFrame = try XCTUnwrap(home.firstItemFrame(inCustomSection: "assets"))
            home.collectionView.contentOffset.y = assetsFrame.minY - home.collectionView.adjustedContentInset.top
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let assetsCell = try XCTUnwrap(home.visibleCustomSectionCell(id: "assets"))
            for row in home.collectionView.visibleCells.compactMap({ $0 as? WalletTokenCell }) {
                XCTAssertEqual(row.bounds.height, WalletTokenCell.defaultHeight, accuracy: 0.5, "Token height after scrolling")
            }
            let assets = try XCTUnwrap(home.children.compactMap { $0 as? WalletAssetsVC }.first)
            XCTAssertGreaterThan(assetsCell.bounds.height, 100)
            XCTAssertEqual(assetsCell.contentView.bounds.height, assetsCell.bounds.height, accuracy: 0.5)
            XCTAssertEqual(assets.view.bounds.height, assetsCell.bounds.height, accuracy: 0.5)
            let nftCollection = try XCTUnwrap(descendants(of: assets.view).compactMap { $0 as? UICollectionView }.last)
            XCTAssertFalse(nftCollection.visibleCells.isEmpty)
            attach(window, name: "Home collectibles layout")

            home.invalidateCustomSectionLayout(id: "assets")
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            for row in home.collectionView.visibleCells.compactMap({ $0 as? WalletTokenCell }) {
                XCTAssertEqual(row.bounds.height, WalletTokenCell.defaultHeight, accuracy: 0.5, "Token height after collectibles invalidation")
            }
            XCTAssertEqual(assetsCell.bounds.height, assets.computedHeight() - 16, accuracy: 0.5)
            XCTAssertEqual(assets.view.bounds.height, assetsCell.bounds.height, accuracy: 0.5)

            home.expandHeader()
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let expandedActions = actions.convert(actions.bounds, to: home.view)
            let expandedHeader = header.convert(header.bounds, to: home.view)
            XCTAssertEqual(expandedActions.minY - expandedHeader.maxY, 16, accuracy: 0.5)
            for row in home.collectionView.visibleCells.compactMap({ $0 as? WalletTokenCell }) {
                XCTAssertEqual(row.bounds.height, WalletTokenCell.defaultHeight, accuracy: 0.5, "Token height after expanding the card")
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
