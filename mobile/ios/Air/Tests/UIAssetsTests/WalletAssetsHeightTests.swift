import Dependencies
import GRDB
import XCTest
import UIKit
@testable import UIAssets
@testable import WalletCore

@MainActor
final class WalletAssetsHeightTests: XCTestCase {
    func testHeightFollowsTheLaidOutCollectiblesWidth() throws {
        try checkHeight(account: DUMMY_ACCOUNT)
    }

    func testLoadedCollectionsKeepTheirHeight() async throws {
        for itemCount in 0...7 {
            try await checkLoadedCollection(itemCount: itemCount)
        }
    }

    func testAccountReplacementReusesCollectiblesControllerWithNewContentAndHeight() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let store = _AccountStore(db: db)
        let accounts = [1, 7].map { count in
            MAccount(id: "\(90000 + count)-mainnet", title: "Replacement fixture", type: .view,
                     byChain: [.ton: .init(address: "replacement-fixture")])
        }
        try await db.write { db in
            for account in accounts { try account.insert(db) }
        }
        defer {
            for account in accounts { NftStore.walletCore(event: .accountDeleted(accountId: account.id)) }
        }
        for (account, count) in zip(accounts, [1, 7]) {
            _ = try await store.accountForActivation(accountId: account.id)
            let nfts = (0..<count).map { index in
                var nft = ApiNft.sample
                nft.address = "\(account.id)-\(index)"
                nft.collectionAddress = nil
                nft.thumbnail = nil
                nft.image = nil
                return nft
            }
            NftStore.walletCore(event: .updateNfts(.init(accountId: account.id, nfts: nfts, chain: .ton)))
            for _ in 0..<100 where NftStore.getAccountNfts(accountId: account.id)?.count != count {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(NftStore.getAccountNfts(accountId: account.id)?.count, count)
        }
        try withDependencies {
            $0.accountStore = store
            $0[DomainsStore.self] = DomainsStore.liveValue
        } operation: {
            let controller = WalletAssetsVC(accountSource: .accountId(accounts[0].id))
            controller.loadViewIfNeeded()
            let view = try XCTUnwrap(controller.view as? WalletAssetsView)
            view.frame = CGRect(x: 0, y: 0, width: 408, height: 600)
            view.layoutIfNeeded()
            let collectibles = try XCTUnwrap(controller.children.first as? NftsVC)
            let initialHeight = controller.computedHeight()
            XCTAssertEqual(collectibles.allShownNftsCount, 1)
            let nftCollection = try XCTUnwrap(collectibles.view.subviews.compactMap { $0 as? UICollectionView }.first)
            let layout = nftCollection.collectionViewLayout
            let itemPath = IndexPath(item: 0, section: 0)
            let initialItemWidth = try XCTUnwrap(layout.layoutAttributesForItem(at: itemPath)).size.width

            controller.switchAccountTo(accounts[1].id)
            view.layoutIfNeeded()
            XCTAssertTrue(controller.children.first === collectibles)
            XCTAssertEqual(collectibles.allShownNftsCount, 7)
            XCTAssertEqual(collectibles.$account.source, .accountId(accounts[1].id))
            XCTAssertGreaterThan(controller.computedHeight(), initialHeight)
            XCTAssertTrue(nftCollection.collectionViewLayout === layout)
            XCTAssertLessThan(try XCTUnwrap(layout.layoutAttributesForItem(at: itemPath)).size.width, initialItemWidth)

            controller.switchAccountTo(accounts[0].id)
            view.layoutIfNeeded()
            XCTAssertTrue(controller.children.first === collectibles)
            XCTAssertEqual(collectibles.allShownNftsCount, 1)
            XCTAssertEqual(collectibles.$account.source, .accountId(accounts[0].id))
            XCTAssertEqual(controller.computedHeight(), initialHeight, accuracy: 1)
        }
    }

    private func checkLoadedCollection(itemCount: Int) async throws {
        let account = MAccount(
            id: "\(10000 + itemCount)-mainnet",
            title: "Height fixture",
            type: .view,
            byChain: [.ton: .init(address: "height-fixture")]
        )
        let nfts = (0..<itemCount).map { index in
            var nft = ApiNft.sample
            nft.address = "height-fixture-\(index)"
            nft.collectionAddress = index < 2 ? "short-collection" : "other-collection"
            nft.thumbnail = nil
            nft.image = nil
            return nft
        }
        NftStore.walletCore(event: .updateNfts(.init(accountId: account.id, nfts: nfts, chain: .ton)))
        defer { NftStore.walletCore(event: .accountDeleted(accountId: account.id)) }
        for _ in 0..<100 where NftStore.getAccountNfts(accountId: account.id)?.count != itemCount {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(NftStore.getAccountNfts(accountId: account.id)?.count, itemCount)
        try checkHeight(account: account, expectedVisibleContent: itemCount > 0)
    }

    private func checkHeight(account: MAccount, expectedVisibleContent: Bool = true) throws {
        try withDependencies {
            $0[DomainsStore.self] = DomainsStore.liveValue
        } operation: {
            try checkLayout(account: account, expectedVisibleContent: expectedVisibleContent)
        }
    }

    private func checkLayout(account: MAccount, expectedVisibleContent: Bool) throws {
        let controller = WalletAssetsVC(accountSource: .constant(account))
        controller.loadViewIfNeeded()
        let view = try XCTUnwrap(controller.view as? WalletAssetsView)
        view.translatesAutoresizingMaskIntoConstraints = true
        let collectibles = try XCTUnwrap(controller.children.first as? NftsVC)
        XCTAssertEqual(controller.hasVisibleContent, expectedVisibleContent)

        var pages = [collectibles]
        if collectibles.allShownNftsCount > 2 {
            let shortCollection = NftsVC(
                accountSource: .constant(account),
                manager: nil,
                layoutMode: .compact,
                filter: .collection(.init(chain: .ton, address: "short-collection", name: "Short"))
            )
            controller.addChild(shortCollection)
            shortCollection.didMove(toParent: controller)
            pages.append(shortCollection)
            view.tabsContainer.isSegmentedControlHidden = false
            view.tabsContainer.replace(items: [
                .init(id: "all", title: "All", viewController: collectibles),
                .init(id: "short", title: "Short", viewController: shortCollection),
            ])
        }

        // Home can request a height before the pager has received its new width.
        view.frame = .zero
        _ = controller.computedHeight()
        for width: CGFloat in [408, 600, 408] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 400)
            let heightBeforeLayout = controller.computedHeight()
            view.setNeedsLayout()
            view.layoutIfNeeded()
            XCTAssertEqual(heightBeforeLayout, controller.computedHeight(), accuracy: 1, "Width: \(width), account: \(account.id)")
            for index in Array(pages.indices) + [0] {
                view.tabsContainer.handleSegmentChange(to: index, animated: false)
                let expected = view.tabsContainer.contentTopInset
                    + pages[index].calculateHeight(isHosted: false) + 16
                XCTAssertEqual(controller.computedHeight(), expected, accuracy: 1, "Width: \(width), page: \(index), account: \(account.id)")
            }
        }
    }
}
