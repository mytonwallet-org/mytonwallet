import Dependencies
import GRDB
import UIComponents
import UIKit
import WalletContext
import WalletResources
import XCTest
@testable import UIAssets
@testable import WalletCore

@MainActor
final class AssetsTabViewportTests: XCTestCase {
    private let account = MAccount(id: "assets-margins-mainnet", title: "Margins", type: .view,
                                   byChain: [.ton: .init(address: "assets-margins")])

    override func setUp() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
        AppStorageHelper.hideNoCostTokens = false
        BalancesStore.for(accountId: account.id).replace(chain: .ton, balances: ["toncoin": 1000000000])
        withDependencies { $0.context = .live } operation: {
            BalanceDataStore.walletCore(event: .rawBalancesChanged(accountId: account.id))
        }
        let nfts = (0..<8).map { index in
            var nft = ApiNft.sample
            nft.address = "assets-margin-\(index)"
            nft.collectionAddress = nil
            nft.thumbnail = nil
            nft.image = nil
            return nft
        }
        NftStore.walletCore(event: .updateNfts(.init(accountId: account.id, nfts: nfts, chain: .ton)))
        for _ in 0..<100 where BalanceDataStore.walletTokensData(accountId: account.id) == nil
            || NftStore.getAccountNfts(accountId: account.id)?.count != nfts.count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(BalanceDataStore.walletTokensData(accountId: account.id))
        XCTAssertEqual(NftStore.getAccountNfts(accountId: account.id)?.count, nfts.count)
    }

    override func tearDown() async throws {
        BalancesStore.for(accountId: account.id).replaceAll(byChain: [:])
        await BalanceDataStore.clean()
        NftStore.walletCore(event: .accountDeleted(accountId: account.id))
        SettingsStore.liveValue.clean()
    }

    func testPagesFollowResolvedMarginsThroughSidebarChangesAndResizing() throws {
        try withDependencies { $0.context = .live } operation: {
            let controller = AssetsTabVC(accountSource: .constant(account), defaultTab: .tokens)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let pager = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WSegmentedController }.first)
            for (width, left, right) in [(466.0, 0.0, 86.0), (466, 86, 0), (956, 62, 62), (842, 0, 86), (402, 0, 0)] {
                window.frame.size.width = width
                controller.view.frame = window.bounds
                controller.additionalSafeAreaInsets = .init(top: 0, left: left, bottom: 0, right: right)
                window.layoutIfNeeded()
                controller.view.layoutIfNeeded()
                for tab in [DisplayAssetTab.tokens, .nfts, .tokens] {
                    XCTAssertTrue(controller.show(accountSource: .constant(account), tab: tab, animated: false))
                    controller.view.layoutIfNeeded()
                    let page = try XCTUnwrap(pager.viewControllers[pager.selectedIndex ?? 0])
                    page.view.layoutIfNeeded()
                    let collection = try XCTUnwrap(page.scrollingView as? UICollectionView)
                    collection.layoutIfNeeded()
                    XCTAssertEqual(pager.frame, controller.view.bounds)
                    XCTAssertEqual(collection.bounds.width, controller.view.bounds.width)
                    XCTAssertEqual(collection.adjustedContentInset.left, 0)
                    XCTAssertEqual(collection.adjustedContentInset.right, 0)
                    XCTAssertEqual(collection.contentSize.width, collection.bounds.width, accuracy: 1)
                    let margins = controller.view.layoutMargins
                    XCTAssertEqual(page.view.layoutMargins.left, margins.left)
                    XCTAssertEqual(page.view.layoutMargins.right, margins.right)
                    if tab == .tokens {
                        let cell = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AssetsWalletTokenCell }.first)
                        let content = try XCTUnwrap(cell.tokenContent)
                        let icon = try XCTUnwrap(descendants(content).compactMap { $0 as? IconView }.first)
                        XCTAssertEqual(icon.convert(icon.bounds, to: page.view).minX, margins.left, accuracy: 1)
                        let contentContainer = try XCTUnwrap(icon.superview)
                        XCTAssertEqual(contentContainer.convert(contentContainer.bounds, to: page.view).maxX,
                                       page.view.bounds.width - margins.right, accuracy: 1)
                    } else {
                        let frames = (0..<collection.numberOfItems(inSection: 0)).compactMap {
                            collection.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
                        }
                        let firstRow = frames.filter { abs($0.minY - (frames.first?.minY ?? 0)) < 1 }
                        XCTAssertGreaterThan(firstRow.count, 1)
                        XCTAssertEqual(try XCTUnwrap(firstRow.map(\.minX).min()), margins.left, accuracy: 1)
                        XCTAssertEqual(try XCTUnwrap(firstRow.map(\.maxX).max()), page.view.bounds.width - margins.right, accuracy: CGFloat(firstRow.count))
                    }
                    let offset = collection.contentOffset
                    pager.scrollView.contentOffset.x += 100
                    pager.layoutIfNeeded()
                    XCTAssertEqual(page.view.layoutMargins.left, margins.left)
                    XCTAssertEqual(page.view.layoutMargins.right, margins.right)
                    XCTAssertEqual(collection.contentOffset, offset)
                }
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
